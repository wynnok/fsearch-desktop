#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"

ACTION="${1:-build}"
ARCHITECTURE="${2:-all}"
CONFIGURATION="${3:-debug}"
TEST_OPTIONS=("${@:4}")

if [[ "$ACTION" == prepare ]]; then
    # Install exactly the currently selected version, only into this project.
    VERSION="$(rustc -V | awk '{print $2}')"
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "An exact stable Rust release is required for isolated target preparation" >&2
        exit 2
    fi
    export RUSTUP_HOME="$PROJECT_ROOT/.build/rustup-home"
    mkdir -p "$RUSTUP_HOME"
    rustup toolchain install "$VERSION" --profile minimal --no-self-update --target aarch64-apple-darwin,x86_64-apple-darwin
    printf '%s\n' "$VERSION" > "$RUSTUP_HOME/toolchain-version"
    exit 0
fi

case "$ACTION" in build|verify|smoke|service-test) ;; *) echo "Usage: bash scripts/architecture.sh {prepare|build|verify|smoke|service-test} [all|arm64|x86_64] [debug|release]" >&2; exit 2 ;; esac
if [[ "$ARCHITECTURE" == all ]]; then
    for architecture in arm64 x86_64; do
        if ((${#TEST_OPTIONS[@]})); then
            bash "$0" "$ACTION" "$architecture" "$CONFIGURATION" "${TEST_OPTIONS[@]}"
        else
            bash "$0" "$ACTION" "$architecture" "$CONFIGURATION"
        fi
    done
    exit 0
fi

select_architecture "$ARCHITECTURE" "$CONFIGURATION"
SCRATCH="$PROJECT_ROOT/.build/swift-$ARCHITECTURE-$CONFIGURATION"
ARTIFACTS="$PROJECT_ROOT/.build/artifacts/$ARCHITECTURE/$CONFIGURATION"
APP="$ARTIFACTS/FsearchSample.app"
EXECUTABLE="$APP/Contents/MacOS/FsearchSample"
SWIFT_OPTIONS+=(--scratch-path "$SCRATCH" --triple "$ARCHITECTURE-apple-macosx13.0" --sdk "$(xcrun --show-sdk-path)" --configuration "$CONFIGURATION")

case "$ACTION" in
    build)
        build_rust
        mkdir -p "$SCRATCH" "$APP/Contents/MacOS" "$APP/Contents/Resources"
        invalidate_swift_link "$SCRATCH/swift-linked-rust"
        swift build "${SWIFT_OPTIONS[@]}" --product FsearchSample
        BIN_PATH="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
        cp "$BIN_PATH/FsearchSample" "$EXECUTABLE"
        ditto "$PROJECT_ROOT/fixtures/sample" "$APP/Contents/Resources/sample"
        cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
        cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FsearchSample</string>
<key>CFBundleIdentifier</key><string>dev.fsearch.sample</string>
<key>CFBundleName</key><string>FsearchSample</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
        # Local test bundle only; distribution signing and notarization are separate.
        codesign --force --sign - "$APP"
        touch "$SCRATCH/swift-linked-rust"
        {
            printf 'Architecture: %s\nRust target: %s\nCPU baseline: %s\nDeployment target: 13.0\n' "$ARCHITECTURE" "$RUST_TARGET" "$BASELINE_CPU"
            rustc -Vv
            cargo -V
            swift --version
            xcodebuild -version
            xcrun --show-sdk-path
            sw_vers
            printf 'Fsearch upstream: %s\n' "$(sed -n 's/^fsearch = .*rev = "\([0-9a-f]\{40\}\)".*$/\1/p' bridge/Cargo.toml)"
            shasum -a 256 bridge/Cargo.lock "$RUST_ARCHIVE" "$EXECUTABLE"
        } > "$ARTIFACTS/build-record.txt"
        bash "$PROJECT_ROOT/scripts/verify-artifact.sh" "$ARCHITECTURE" "$CONFIGURATION"
        ;;
    verify) bash "$PROJECT_ROOT/scripts/verify-artifact.sh" "$ARCHITECTURE" "$CONFIGURATION" ;;
    service-test)
        build_rust
        mkdir -p "$SCRATCH"
        invalidate_swift_link "$SCRATCH/swift-linked-rust"
        swift build "${SWIFT_OPTIONS[@]}" --build-tests
        if [[ "$ARCHITECTURE" == "$(uname -m)" ]]; then
            if ((${#TEST_OPTIONS[@]})); then
                swift test "${SWIFT_OPTIONS[@]}" "${TEST_OPTIONS[@]}"
            else
                swift test "${SWIFT_OPTIONS[@]}"
            fi
        else
            CONFIG_PRODUCT="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIGURATION:0:1}")${CONFIGURATION:1}"
            TEST_BUNDLE="$SCRATCH/out/Products/$CONFIG_PRODUCT/FsearchServiceTests.xctest"
            if ! arch "-$ARCHITECTURE" /usr/bin/true 2>/dev/null; then
                echo "$ARCHITECTURE service tests are not verified: the Rosetta runtime is unavailable" >&2
                exit 2
            fi
            arch "-$ARCHITECTURE" "$(xcrun --find xctest)" "$TEST_BUNDLE"
        fi
        touch "$SCRATCH/swift-linked-rust"
        ;;
    smoke)
        bash "$PROJECT_ROOT/scripts/verify-artifact.sh" "$ARCHITECTURE" "$CONFIGURATION"
        OUTPUT="$PROJECT_ROOT/.build/native-smoke/$ARCHITECTURE-$CONFIGURATION"
        mkdir -p "$OUTPUT"
        printf 'Requested architecture: %s\nHost architecture: %s\n' "$ARCHITECTURE" "$(uname -m)" > "$OUTPUT/environment.txt"
        sw_vers >> "$OUTPUT/environment.txt"
        if [[ "$ARCHITECTURE" != "$(uname -m)" ]]; then
            printf 'Execution: translated (Rosetta on Apple Silicon), not Intel hardware\n' >> "$OUTPUT/environment.txt"
        else
            printf 'Execution: native\n' >> "$OUTPUT/environment.txt"
        fi
        arch "-$ARCHITECTURE" "$EXECUTABLE" "$PROJECT_ROOT/fixtures/sample" --smoke "$OUTPUT" > "$OUTPUT/launch.log" 2>&1
        cat "$OUTPUT/launch.log"
        ;;
esac
