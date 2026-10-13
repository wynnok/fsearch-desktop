#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"

DMG_INPUT="${1:-}"
[[ -n "$DMG_INPUT" ]] || { echo "Usage: bash scripts/verify-dev-dmg.sh <development.dmg>" >&2; exit 2; }
[[ -f "$DMG_INPUT" ]] || { echo "DMG does not exist: $DMG_INPUT" >&2; exit 2; }

DMG_PATH="$(cd "$(dirname "$DMG_INPUT")" && pwd)/$(basename "$DMG_INPUT")"
case "$DMG_PATH" in
    "$PROJECT_ROOT/.build/"*) ;;
    *) echo "DMG must be inside the project's .build directory" >&2; exit 2 ;;
esac

OUTPUT_DIR="$(dirname "$DMG_PATH")"
DMG_BASENAME="$(basename "$DMG_PATH")"
SHA256SUMS="$OUTPUT_DIR/SHA256SUMS"
MANIFEST="$OUTPUT_DIR/build-manifest.txt"
REPORT="$OUTPUT_DIR/verification-report.txt"
APP_NAME="Fsearch Desktop Development"
APP_RELATIVE_PATH="$APP_NAME.app"
VERIFY_ROOT="$PROJECT_ROOT/.build/dev-dmg"
mkdir -p "$VERIFY_ROOT"
TEMP_DIR="$(mktemp -d "$VERIFY_ROOT/verify.XXXXXX")"
MOUNT_POINT="$TEMP_DIR/mount"
INSTALL_ROOT="$TEMP_DIR/Applications"
INSTALLED_APP="$INSTALL_ROOT/$APP_RELATIVE_PATH"
INSTALLED_SAMPLE="$INSTALLED_APP/Contents/Resources/sample"
SMOKE_OUTPUT="$TEMP_DIR/smoke"
SMOKE_LOG="$TEMP_DIR/smoke.log"
MOUNTED=0

cleanup() {
    if [[ "$MOUNTED" == 1 ]]; then
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

[[ -f "$SHA256SUMS" ]] || { echo "Missing SHA256SUMS beside the DMG" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "Missing build-manifest.txt beside the DMG" >&2; exit 1; }
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
    "$MOUNT_POINT/build-records/arm64.txt" \
    "$MOUNT_POINT/build-records/x86_64.txt" \
    "$RESOURCES/PROJECT-LICENSE.txt" \
    "$RESOURCES/FSEARCH-LICENSE.txt" \
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
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == dev.fsearch.desktop.development ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")" == "$APP_NAME" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" == 13.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :FsearchPackageStatus' "$PLIST")" == development-unnotarized ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :FsearchDevelopmentBuild' "$PLIST")" == true ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :FsearchNotarized' "$PLIST")" == false ]]

PACKAGE_VERSION="$(awk '/^Application version:/ {print $3}' "$MANIFEST")"
[[ -n "$PACKAGE_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$PACKAGE_VERSION" ]]
grep -q '^Package status: development-unnotarized$' "$MANIFEST"
grep -q '^Architectures: arm64 x86_64$' "$MANIFEST"
grep -F -q "Engine: Fsearch $UPSTREAM_VERSION" "$MANIFEST"
grep -q '^Architecture: arm64$' "$MOUNT_POINT/build-records/arm64.txt"
grep -q '^Architecture: x86_64$' "$MOUNT_POINT/build-records/x86_64.txt"
cmp -s "$PROJECT_ROOT/LICENSE" "$MOUNT_POINT/PROJECT-LICENSE.txt"
cmp -s "$PROJECT_ROOT/bridge/FSEARCH-LICENSE" "$MOUNT_POINT/FSEARCH-LICENSE.txt"

codesign --verify --deep --strict "$APP"
CODESIGN_DETAILS="$(codesign -dvvv "$APP" 2>&1)"
printf '%s\n' "$CODESIGN_DETAILS" | grep -q 'Signature=adhoc'
if printf '%s\n' "$CODESIGN_DETAILS" | grep -q '^Authority='; then
    echo "Development package unexpectedly carries a signing Authority" >&2
    exit 1
fi

ditto "$APP" "$INSTALLED_APP"
codesign --verify --deep --strict "$INSTALLED_APP"
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
if ! arch "-$HOST_ARCHITECTURE" "$INSTALLED_APP/Contents/MacOS/FsearchSample" \
    "$INSTALLED_SAMPLE" --smoke "$SMOKE_OUTPUT" > "$SMOKE_LOG" 2>&1; then
    cat "$SMOKE_LOG" >&2
    echo "Installed application smoke failed" >&2
    exit 1
fi
cat "$SMOKE_LOG"
for file in page-final.png responsive-latest.png responsiveness.txt; do
    [[ -f "$SMOKE_OUTPUT/$file" ]] || { echo "Installed smoke did not produce $file" >&2; exit 1; }
done
grep -q 'Native smoke page-final: passed' "$SMOKE_LOG"
grep -q 'NATIVE_RESPONSIVENESS' "$SMOKE_LOG"

{
    printf 'Development DMG verification: PASSED\n'
    printf 'DMG: %s\n' "$DMG_BASENAME"
    printf 'SHA-256: %s\n' "$ACTUAL_HASH"
    printf 'Package status: development-unnotarized\n'
    printf 'Application architectures: %s\n' "$EXPECTED_ARCHITECTURES"
    printf 'Engine: %s\n' "$(awk '/^Engine:/ {sub(/^Engine: /, ""); print}' "$MANIFEST")"
    printf 'Install path: temporary copy from mounted DMG (system Applications was not modified)\n'
    printf 'Runtime host: %s %s\n' "$(sw_vers -productName)" "$(sw_vers -productVersion)"
    printf 'Runtime architecture evidence: %s\n' "$RUNTIME_CLASS"
    printf 'Runtime smoke: launch, implemented query suite, and exit passed\n'
    printf 'Notarization: not performed; ad-hoc development signature only\n'
    printf 'T06 Intel Mac and macOS 13 hardware gates: not evaluated\n'
} > "$REPORT"

cat "$REPORT"
