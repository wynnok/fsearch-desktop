#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
source "$PROJECT_ROOT/scripts/dev-dmg-common.sh"

APP_VERSION="${FSEARCH_DEV_VERSION:-$DEV_DMG_DEFAULT_VERSION}"
case "$APP_VERSION" in
    *[!0-9A-Za-z._-]*) echo "FSEARCH_DEV_VERSION contains unsupported characters" >&2; exit 2 ;;
esac

bash "$PROJECT_ROOT/scripts/check-upstream-pin.sh"

UPSTREAM_VERSION="$(dev_dmg_upstream_version)"
[[ -n "$UPSTREAM_VERSION" ]] || { echo "Cannot read the embedded Fsearch version" >&2; exit 1; }

BUILD_COMMIT="$(git rev-parse HEAD)"
BUILD_SHORT_COMMIT="$(git rev-parse --short=12 HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    WORKTREE_STATE=dirty
else
    WORKTREE_STATE=clean
fi

APP_NAME="$DEV_DMG_APP_NAME"
DMG_NAME="${DEV_DMG_ARTIFACT_PREFIX}-${APP_VERSION}-dev-${BUILD_SHORT_COMMIT}-universal.dmg"
OUTPUT_DIR="$DEV_DMG_OUTPUT_DIR"
PACKAGE_DIR="$DEV_DMG_ROOT/package"
STAGING_APP="$PACKAGE_DIR/$APP_NAME.app"
DMG_ROOT="$PACKAGE_DIR/dmg-root"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
MANIFEST="$OUTPUT_DIR/build-manifest.txt"
NOTICES="$OUTPUT_DIR/THIRD-PARTY-NOTICES.txt"
DEVELOPMENT_README="$PACKAGE_DIR/DEVELOPMENT-README.txt"

select_architecture arm64 release
ARM_ARCHIVE="$RUST_ARCHIVE"
select_architecture x86_64 release
X86_ARCHIVE="$RUST_ARCHIVE"

ARM_APP="$PROJECT_ROOT/.build/artifacts/arm64/release/FsearchSample.app"
X86_APP="$PROJECT_ROOT/.build/artifacts/x86_64/release/FsearchSample.app"
ARM_EXECUTABLE="$ARM_APP/Contents/MacOS/FsearchSample"
X86_EXECUTABLE="$X86_APP/Contents/MacOS/FsearchSample"
STAGED_EXECUTABLE="$STAGING_APP/Contents/MacOS/FsearchSample"
STAGED_RESOURCES="$STAGING_APP/Contents/Resources"
STAGED_PLIST="$STAGING_APP/Contents/Info.plist"

set_plist_string() {
    local key="$1"
    local value="$2"
    if plutil -extract "$key" raw -o - "$STAGED_PLIST" >/dev/null 2>&1; then
        plutil -replace "$key" -string "$value" "$STAGED_PLIST"
    else
        plutil -insert "$key" -string "$value" "$STAGED_PLIST"
    fi
}

set_plist_bool() {
    local key="$1"
    local value="$2"
    if plutil -extract "$key" raw -o - "$STAGED_PLIST" >/dev/null 2>&1; then
        plutil -replace "$key" -bool "$value" "$STAGED_PLIST"
    else
        plutil -insert "$key" -bool "$value" "$STAGED_PLIST"
    fi
}

bash "$PROJECT_ROOT/scripts/architecture.sh" build all release

for app in "$ARM_APP" "$X86_APP"; do
    [[ -d "$app" ]] || { echo "Missing architecture application: $app" >&2; exit 1; }
done
[[ "$(lipo -archs "$ARM_EXECUTABLE")" == arm64 ]]
[[ "$(lipo -archs "$X86_EXECUTABLE")" == x86_64 ]]
[[ "$(lipo -archs "$ARM_ARCHIVE")" == arm64 ]]
[[ "$(lipo -archs "$X86_ARCHIVE")" == x86_64 ]]

rm -rf "$PACKAGE_DIR" "$OUTPUT_DIR"
mkdir -p "$PACKAGE_DIR" "$OUTPUT_DIR" "$DMG_ROOT/build-records"

bash "$PROJECT_ROOT/scripts/generate-third-party-notices.sh" "$NOTICES"

ditto "$ARM_APP" "$STAGING_APP"
lipo -create "$ARM_EXECUTABLE" "$X86_EXECUTABLE" -output "$STAGED_EXECUTABLE"

set_plist_string CFBundleIdentifier dev.fsearch.desktop.development
set_plist_string CFBundleName "$APP_NAME"
set_plist_string CFBundleDisplayName "$APP_NAME"
set_plist_string CFBundleShortVersionString "$APP_VERSION"
set_plist_string FsearchDevelopmentVersion "${APP_VERSION}-dev.${BUILD_SHORT_COMMIT}"
set_plist_string FsearchBuildCommit "$BUILD_COMMIT"
set_plist_string FsearchEngineVersion "$UPSTREAM_VERSION"
set_plist_string FsearchPackageStatus "$DEV_DMG_PACKAGE_STATUS"
set_plist_bool FsearchDevelopmentBuild true
set_plist_bool FsearchNotarized false

cp "$PROJECT_ROOT/LICENSE" "$STAGED_RESOURCES/PROJECT-LICENSE.txt"
cp "$PROJECT_ROOT/bridge/FSEARCH-LICENSE" "$STAGED_RESOURCES/FSEARCH-LICENSE.txt"
cp "$NOTICES" "$STAGED_RESOURCES/THIRD-PARTY-NOTICES.txt"
cp "$PROJECT_ROOT/.build/artifacts/arm64/release/build-record.txt" "$STAGED_RESOURCES/BUILD-RECORD-arm64.txt"
cp "$PROJECT_ROOT/.build/artifacts/x86_64/release/build-record.txt" "$STAGED_RESOURCES/BUILD-RECORD-x86_64.txt"

cat > "$DEVELOPMENT_README" <<EOF
Fsearch Desktop Development

This is a development verification package, not a stable release.
- Not notarized and not Developer ID signed.
- The application and embedded Fsearch engine contain arm64 and x86_64 slices.
- The package was built from commit $BUILD_COMMIT.
- Intel Mac and macOS 13 runtime evidence is not implied unless the generated verification report records it.

Install by dragging "$APP_NAME.app" onto the Applications link in this disk image.
Use a disposable test account or machine. This package does not run a CLI installer,
change privacy settings, install global tools, or publish a stable release.
EOF

cat > "$MANIFEST" <<EOF
Fsearch Desktop Development Package
Package status: $DEV_DMG_PACKAGE_STATUS
Release channel: development verification artifact only
Application version: $APP_VERSION
Git commit: $BUILD_COMMIT
Git worktree at package time: $WORKTREE_STATE
Engine: Fsearch $UPSTREAM_VERSION
Architectures: arm64 x86_64
Minimum macOS: 13.0
Build timestamp (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Runner image: $(dev_dmg_runner_image)
Rust requested pin: $(dev_dmg_rust_pin)
Rust: $(rustc -V)
Cargo: $(cargo -V)
Swift: $(swift --version | awk 'NR == 1 {print}')
Xcode: $(xcodebuild -version | awk 'NR <= 2 {printf "%s%s", separator, $0; separator="; "}')
License SHA-256 (project): $(shasum -a 256 "$PROJECT_ROOT/LICENSE" | awk '{print $1}')
License SHA-256 (Fsearch): $(shasum -a 256 "$PROJECT_ROOT/bridge/FSEARCH-LICENSE" | awk '{print $1}')
Third-party notices SHA-256: $(shasum -a 256 "$NOTICES" | awk '{print $1}')
Cargo lock SHA-256: $(shasum -a 256 "$PROJECT_ROOT/bridge/Cargo.lock" | awk '{print $1}')
Final DMG SHA-256: see SHA256SUMS
$(dev_dmg_toolchain_pin_note)

Runtime verification is recorded separately by scripts/verify-dev-dmg.sh.
The package must not be represented as stable, signed, notarized, or alpha-accepted.
EOF

codesign --force --sign - "$STAGING_APP"

ditto "$STAGING_APP" "$DMG_ROOT/$APP_NAME.app"
cp "$DEVELOPMENT_README" "$DMG_ROOT/DEVELOPMENT-README.txt"
cp "$MANIFEST" "$DMG_ROOT/BUILD-MANIFEST.txt"
cp "$PROJECT_ROOT/LICENSE" "$DMG_ROOT/PROJECT-LICENSE.txt"
cp "$PROJECT_ROOT/bridge/FSEARCH-LICENSE" "$DMG_ROOT/FSEARCH-LICENSE.txt"
cp "$NOTICES" "$DMG_ROOT/THIRD-PARTY-NOTICES.txt"
cp "$PROJECT_ROOT/.build/artifacts/arm64/release/build-record.txt" "$DMG_ROOT/build-records/arm64.txt"
cp "$PROJECT_ROOT/.build/artifacts/x86_64/release/build-record.txt" "$DMG_ROOT/build-records/x86_64.txt"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"
(cd "$OUTPUT_DIR" && shasum -a 256 "$DMG_NAME" > SHA256SUMS)

printf 'Created %s\n' "$DMG_PATH"
printf 'SHA-256 %s\n' "$(awk '{print $1}' "$OUTPUT_DIR/SHA256SUMS")"
printf 'Manifest %s\n' "$MANIFEST"
