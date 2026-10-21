#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
source "$PROJECT_ROOT/scripts/dev-dmg-common.sh"

DMG_INPUT=""
MANIFEST_INPUT=""
SHA256SUMS_INPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)
            [[ $# -ge 2 ]] || { echo "--dmg requires a path" >&2; exit 2; }
            DMG_INPUT="$2"
            shift 2
            ;;
        --manifest)
            [[ $# -ge 2 ]] || { echo "--manifest requires a path" >&2; exit 2; }
            MANIFEST_INPUT="$2"
            shift 2
            ;;
        --sha256sums)
            [[ $# -ge 2 ]] || { echo "--sha256sums requires a path" >&2; exit 2; }
            SHA256SUMS_INPUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: bash scripts/verify-dev-dmg.sh --dmg <path> [--manifest <path>] [--sha256sums <path>]" >&2
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
        *)
            [[ -z "$DMG_INPUT" ]] || { echo "Only one DMG path may be supplied" >&2; exit 2; }
            DMG_INPUT="$1"
            shift
            ;;
    esac
done
if [[ $# -gt 0 ]]; then
    [[ -z "$DMG_INPUT" && $# -eq 1 ]] || { echo "Unexpected arguments: $*" >&2; exit 2; }
    DMG_INPUT="$1"
fi
[[ -n "$DMG_INPUT" ]] || {
    echo "Usage: bash scripts/verify-dev-dmg.sh --dmg <path> [--manifest <path>] [--sha256sums <path>]" >&2
    exit 2
}
[[ -f "$DMG_INPUT" ]] || { echo "DMG does not exist: $DMG_INPUT" >&2; exit 2; }

DMG_PATH="$(cd "$(dirname "$DMG_INPUT")" && pwd)/$(basename "$DMG_INPUT")"
DMG_BASENAME="$(basename "$DMG_PATH")"
ARTIFACT_DIR="$(dirname "$DMG_PATH")"
MANIFEST_INPUT="${MANIFEST_INPUT:-$ARTIFACT_DIR/build-manifest.txt}"
SHA256SUMS_INPUT="${SHA256SUMS_INPUT:-$ARTIFACT_DIR/SHA256SUMS}"
[[ -f "$MANIFEST_INPUT" ]] || { echo "Missing build manifest: $MANIFEST_INPUT" >&2; exit 1; }
[[ -f "$SHA256SUMS_INPUT" ]] || { echo "Missing SHA256SUMS: $SHA256SUMS_INPUT" >&2; exit 1; }
MANIFEST="$(cd "$(dirname "$MANIFEST_INPUT")" && pwd)/$(basename "$MANIFEST_INPUT")"
SHA256SUMS="$(cd "$(dirname "$SHA256SUMS_INPUT")" && pwd)/$(basename "$SHA256SUMS_INPUT")"
mkdir -p "$DEV_DMG_VERIFICATION_DIR"
REPORT="$DEV_DMG_VERIFICATION_DIR/verification-report.txt"
APP_NAME="$DEV_DMG_APP_NAME"
APP_RELATIVE_PATH="$APP_NAME.app"
VERIFY_ROOT="$DEV_DMG_ROOT"
mkdir -p "$VERIFY_ROOT"
TEMP_DIR="$(mktemp -d "$VERIFY_ROOT/verify.XXXXXX")"
MOUNT_POINT="$TEMP_DIR/mount"
INSTALL_ROOT="$TEMP_DIR/Applications"
INSTALLED_APP="$INSTALL_ROOT/$APP_RELATIVE_PATH"
INSTALLED_SAMPLE="$INSTALLED_APP/Contents/Resources/sample"
SMOKE_OUTPUT="$TEMP_DIR/smoke"
SMOKE_LOG="$TEMP_DIR/smoke.log"
GENERATED_NOTICES="$TEMP_DIR/THIRD-PARTY-NOTICES.txt"
MOUNTED=0

cleanup() {
    dev_dmg_stop_smoke
    if [[ "$MOUNTED" == 1 ]]; then
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

UPSTREAM_VERSION="$(sed -n 's/^const UPSTREAM_VERSION: &str = "\(.*\)";$/\1/p' "$PROJECT_ROOT/bridge/src/lib.rs")"
[[ -n "$UPSTREAM_VERSION" ]] || { echo "Cannot read the embedded Fsearch version" >&2; exit 1; }
rm -f "$REPORT"
mkdir -p "$MOUNT_POINT" "$INSTALL_ROOT"

EXPECTED_HASH="$(awk -v artifact="$DMG_BASENAME" '$2 == artifact || $2 == "*" artifact {print $1}' "$SHA256SUMS")"
ACTUAL_HASH="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
[[ -n "$EXPECTED_HASH" && "$EXPECTED_HASH" == "$ACTUAL_HASH" ]] || {
    echo "DMG SHA-256 does not match SHA256SUMS" >&2
    exit 1
}

hdiutil verify "$DMG_PATH"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
MOUNTED=1

APP="$MOUNT_POINT/$APP_RELATIVE_PATH"
EXECUTABLE="$APP/Contents/MacOS/FsearchSample"
PLIST="$APP/Contents/Info.plist"
RESOURCES="$APP/Contents/Resources"
MOUNTED_APP_TRANSACTION="$MOUNT_POINT/Applications"

[[ -d "$APP" ]] || { echo "DMG does not contain $APP_RELATIVE_PATH" >&2; exit 1; }
[[ -L "$MOUNTED_APP_TRANSACTION" && "$(readlink "$MOUNTED_APP_TRANSACTION")" == /Applications ]] || {
    echo "DMG does not contain an Applications installation link" >&2
    exit 1
}
for file in \
    "$MOUNT_POINT/DEVELOPMENT-README.txt" \
    "$MOUNT_POINT/BUILD-MANIFEST.txt" \
    "$MOUNT_POINT/PROJECT-LICENSE.txt" \
    "$MOUNT_POINT/FSEARCH-LICENSE.txt" \
    "$MOUNT_POINT/THIRD-PARTY-NOTICES.txt" \
    "$MOUNT_POINT/build-records/arm64.txt" \
    "$MOUNT_POINT/build-records/x86_64.txt" \
    "$RESOURCES/PROJECT-LICENSE.txt" \
    "$RESOURCES/FSEARCH-LICENSE.txt" \
    "$RESOURCES/THIRD-PARTY-NOTICES.txt" \
    "$RESOURCES/AppIcon.icns" \
    "$RESOURCES/BUILD-RECORD-arm64.txt" \
    "$RESOURCES/BUILD-RECORD-x86_64.txt"; do
    [[ -f "$file" ]] || { echo "Missing packaged file: $file" >&2; exit 1; }
done

EXPECTED_ARCHITECTURES="arm64 x86_64"
actual_architectures() {
    lipo -archs "$1" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//'
}
[[ "$(actual_architectures "$EXECUTABLE")" == "$EXPECTED_ARCHITECTURES" ]] || {
    echo "Unexpected application architectures: $(lipo -archs "$EXECUTABLE")" >&2
    exit 1
}
while IFS= read -r -d '' path; do
    if file "$path" | grep -q 'Mach-O'; then
        [[ "$(actual_architectures "$path")" == "$EXPECTED_ARCHITECTURES" ]] || {
            echo "Embedded Mach-O is not Universal: $path ($(lipo -archs "$path"))" >&2
            exit 1
        }
    fi
done < <(find "$APP/Contents" -type f -print0)

while IFS= read -r dependency; do
    case "$dependency" in
        /System/Library/*|/usr/lib/*) ;;
        *) echo "Unexpected non-system dynamic dependency: $dependency" >&2; exit 1 ;;
    esac
done < <(otool -L "$EXECUTABLE" | awk '/^\t/ {print $1}')

plutil -lint "$PLIST"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == dev.fsearch.desktop ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")" == "$APP_NAME" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST")" == "$APP_NAME" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")" == AppIcon ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" == 13.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :FsearchPackageStatus' "$PLIST")" == "$DEV_DMG_PACKAGE_STATUS" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :FsearchDevelopmentBuild' "$PLIST")" == true ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :FsearchNotarized' "$PLIST")" == false ]]

PACKAGE_VERSION="$(awk '/^Application version:/ {print $3}' "$MANIFEST")"
[[ -n "$PACKAGE_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$PACKAGE_VERSION" ]]
grep -F -q "Package status: $DEV_DMG_PACKAGE_STATUS" "$MANIFEST"
grep -q '^Architectures: arm64 x86_64$' "$MANIFEST"
grep -F -q "Engine: Fsearch $UPSTREAM_VERSION" "$MANIFEST"
grep -q '^Runner image: ' "$MANIFEST"
grep -q '^Rust: rustc ' "$MANIFEST"
grep -q '^Swift: Apple Swift version ' "$MANIFEST"
grep -q '^Xcode: Xcode ' "$MANIFEST"
grep -q '^Architecture: arm64$' "$MOUNT_POINT/build-records/arm64.txt"
grep -q '^Architecture: x86_64$' "$MOUNT_POINT/build-records/x86_64.txt"
cmp -s "$PROJECT_ROOT/LICENSE" "$MOUNT_POINT/PROJECT-LICENSE.txt"
cmp -s "$PROJECT_ROOT/bridge/FSEARCH-LICENSE" "$MOUNT_POINT/FSEARCH-LICENSE.txt"
bash "$PROJECT_ROOT/scripts/generate-third-party-notices.sh" "$GENERATED_NOTICES"
cmp -s "$GENERATED_NOTICES" "$MOUNT_POINT/THIRD-PARTY-NOTICES.txt"
cmp -s "$GENERATED_NOTICES" "$RESOURCES/THIRD-PARTY-NOTICES.txt"
NOTICES_HASH="$(shasum -a 256 "$GENERATED_NOTICES" | awk '{print $1}')"
MANIFEST_NOTICES_HASH="$(awk '/^Third-party notices SHA-256:/ {print $NF}' "$MANIFEST")"
[[ -n "$MANIFEST_NOTICES_HASH" && "$NOTICES_HASH" == "$MANIFEST_NOTICES_HASH" ]] || {
    echo "Third-party notices SHA-256 does not match the build manifest" >&2
    exit 1
}

codesign --verify --deep --strict "$APP"
CODESIGN_DETAILS="$(codesign -dvvv "$APP" 2>&1)"
printf '%s\n' "$CODESIGN_DETAILS" | grep -q 'Signature=adhoc'
if printf '%s\n' "$CODESIGN_DETAILS" | grep -q '^Authority='; then
    echo "Development package unexpectedly carries a signing Authority" >&2
    exit 1
fi

ditto "$APP" "$INSTALLED_APP"
codesign --verify --deep --strict "$INSTALLED_APP"
bash "$PROJECT_ROOT/scripts/desktop-validation.sh" "$INSTALLED_APP"
[[ -d "$INSTALLED_SAMPLE" ]] || { echo "Installed application is missing its sample resource" >&2; exit 1; }

HOST_ARCHITECTURE="$(uname -m)"
case "$HOST_ARCHITECTURE" in
    arm64|x86_64) ;;
    *) echo "Unsupported runtime architecture: $HOST_ARCHITECTURE" >&2; exit 1 ;;
esac
if [[ "$HOST_ARCHITECTURE" == x86_64 && "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" == 1 ]]; then
    RUNTIME_CLASS="x86_64 translated by Rosetta; this is not Intel hardware evidence"
else
    RUNTIME_CLASS="native $HOST_ARCHITECTURE process; no Intel Mac or macOS 13 hardware gate is inferred"
fi

mkdir -p "$SMOKE_OUTPUT"
if ! dev_dmg_run_smoke "$INSTALLED_APP/Contents/MacOS/FsearchSample" "$INSTALLED_SAMPLE" "$SMOKE_OUTPUT" "$SMOKE_LOG"; then
    cp "$SMOKE_LOG" "$DEV_DMG_VERIFICATION_DIR/smoke-failure.log"
    if [[ -f "$SMOKE_LOG.sample.txt" ]]; then
        cp "$SMOKE_LOG.sample.txt" "$DEV_DMG_VERIFICATION_DIR/smoke-timeout.sample.txt"
    fi
    cat "$SMOKE_LOG" >&2
    echo "Installed application smoke failed" >&2
    exit 1
fi
cat "$SMOKE_LOG"
for file in page-final.png responsive-latest.png responsiveness.txt search-journey.json file-journey.json file-actions.json diagnostics.json settings-window-reopened.png manual-update-entry.png file-journey.png; do
    [[ -f "$SMOKE_OUTPUT/$file" ]] || { echo "Installed smoke did not produce $file" >&2; exit 1; }
done
grep -q 'Native smoke page-final: passed' "$SMOKE_LOG"
grep -q 'NATIVE_RESPONSIVENESS' "$SMOKE_LOG"
grep -q 'Native search and file acceptance journeys: passed' "$SMOKE_LOG"
ruby -rjson - "$SMOKE_OUTPUT" <<'RUBY'
%w[search-journey.json file-journey.json file-actions.json].each do |name|
  checks = JSON.parse(File.read(File.join(ARGV[0], name)))
  raise "Acceptance checks missing or failed: #{name}" if checks.empty? || checks.values.any? { |value| value != true }
end
RUBY

{
    printf 'Development DMG verification: PASSED\n'
    printf 'DMG: %s\n' "$DMG_BASENAME"
    printf 'DMG source: %s\n' "$DMG_PATH"
    printf 'SHA-256: %s\n' "$ACTUAL_HASH"
    printf 'Package status: %s\n' "$DEV_DMG_PACKAGE_STATUS"
    printf 'Application architectures: %s\n' "$EXPECTED_ARCHITECTURES"
    printf 'Engine: %s\n' "$(awk '/^Engine:/ {sub(/^Engine: /, ""); print}' "$MANIFEST")"
    printf 'Packaged runner image: %s\n' "$(awk '/^Runner image:/ {sub(/^Runner image: /, ""); print}' "$MANIFEST")"
    printf 'Packaged Rust requested pin: %s\n' "$(awk '/^Rust requested pin:/ {sub(/^Rust requested pin: /, ""); print}' "$MANIFEST")"
    printf 'Packaged Rust: %s\n' "$(awk '/^Rust:/ {sub(/^Rust: /, ""); print}' "$MANIFEST")"
    printf 'Packaged Swift: %s\n' "$(awk '/^Swift:/ {sub(/^Swift: /, ""); print}' "$MANIFEST")"
    printf 'Packaged Xcode: %s\n' "$(awk '/^Xcode:/ {sub(/^Xcode: /, ""); print}' "$MANIFEST")"
    printf 'Verification runner image: %s\n' "$(dev_dmg_runner_image)"
    printf 'Verification Rust: %s\n' "$(rustc -V)"
    printf 'Verification Swift: %s\n' "$(swift --version | awk 'NR == 1 {print}')"
    printf 'Verification Xcode: %s\n' "$(xcodebuild -version | awk 'NR <= 2 {printf "%s%s", separator, $0; separator="; "}')"
    printf 'Packaged toolchain reproducibility: %s\n' "$(awk '/^Reproducibility note:/ {sub(/^Reproducibility note: /, ""); print}' "$MANIFEST")"
    printf 'Third-party notices SHA-256: %s\n' "$NOTICES_HASH"
    printf 'Install path: temporary copy from mounted DMG (system Applications was not modified)\n'
    printf 'Runtime host: %s %s\n' "$(sw_vers -productName)" "$(sw_vers -productVersion)"
    printf 'Runtime architecture evidence: %s\n' "$RUNTIME_CLASS"
    printf 'Runtime smoke: desktop Engine startup/name/content/permission probe/live changes, fixture query suite, and exit passed\n'
    printf 'Notarization: not performed; ad-hoc development signature only\n'
    printf 'T06 Intel Mac and macOS 13 hardware gates: not evaluated\n'
} > "$REPORT"

cp "$SMOKE_LOG" "$DEV_DMG_VERIFICATION_DIR/smoke.log"
mkdir -p "$DEV_DMG_VERIFICATION_DIR/journeys"
for evidence in search-journey.json file-journey.json file-actions.json diagnostics.json settings-window-reopened.png manual-update-entry.png file-journey.png; do
    cp "$SMOKE_OUTPUT/$evidence" "$DEV_DMG_VERIFICATION_DIR/journeys/$evidence"
done
cat "$REPORT"
