#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
source "$PROJECT_ROOT/scripts/dev-dmg-common.sh"

ARCHITECTURE="${1:-}"
case "$ARCHITECTURE" in
    arm64|x86_64) ;;
    *) echo "Usage: package-arch-dmg.sh {arm64|x86_64}" >&2; exit 2 ;;
esac

APP_VERSION="${FSEARCH_DEV_VERSION:-$DEV_DMG_DEFAULT_VERSION}"
case "$APP_VERSION" in
    *[!0-9A-Za-z._-]*) echo "FSEARCH_DEV_VERSION contains unsupported characters" >&2; exit 2 ;;
esac

SOURCE_APP="$DEV_DMG_ROOT/package/$DEV_DMG_APP_NAME.app"
SOURCE_ROOT="$DEV_DMG_ROOT/package/dmg-root"
SOURCE_MANIFEST="$DEV_DMG_OUTPUT_DIR/build-manifest.txt"
SOURCE_NOTICES="$DEV_DMG_OUTPUT_DIR/THIRD-PARTY-NOTICES.txt"
SOURCE_SUMS="$DEV_DMG_OUTPUT_DIR/SHA256SUMS"
[[ -d "$SOURCE_APP" ]] || { echo "Missing universal package app: $SOURCE_APP" >&2; exit 1; }
[[ -d "$SOURCE_ROOT" ]] || { echo "Missing universal DMG root: $SOURCE_ROOT" >&2; exit 1; }
[[ -f "$SOURCE_MANIFEST" ]] || { echo "Missing universal build manifest: $SOURCE_MANIFEST" >&2; exit 1; }
[[ -f "$SOURCE_NOTICES" ]] || { echo "Missing third-party notices: $SOURCE_NOTICES" >&2; exit 1; }
[[ -f "$SOURCE_SUMS" ]] || { echo "Missing universal SHA256SUMS: $SOURCE_SUMS" >&2; exit 1; }

case "$ARCHITECTURE" in
    arm64) ARCH_LABEL="arm64"; OTHER_ARCHITECTURE="x86_64" ;;
    x86_64) ARCH_LABEL="Intel"; OTHER_ARCHITECTURE="arm64" ;;
esac

BUILD_COMMIT="$(git rev-parse HEAD)"
BUILD_SHORT_COMMIT="$(git rev-parse --short=12 HEAD)"
VARIANT_APP_NAME="$DEV_DMG_APP_NAME $ARCH_LABEL"
VARIANT_DMG_NAME="${DEV_DMG_ARTIFACT_PREFIX}-${APP_VERSION}-dev-${BUILD_SHORT_COMMIT}-${ARCHITECTURE}.dmg"
VARIANT_DIR="$DEV_DMG_ROOT/arch-$ARCHITECTURE"
VARIANT_APP="$VARIANT_DIR/$VARIANT_APP_NAME.app"
VARIANT_ROOT="$VARIANT_DIR/dmg-root"
VARIANT_MOUNT="$VARIANT_DIR/mount"
VARIANT_DMG="$DEV_DMG_OUTPUT_DIR/$VARIANT_DMG_NAME"
VARIANT_MANIFEST="$DEV_DMG_OUTPUT_DIR/build-manifest-$ARCHITECTURE.txt"
VARIANT_REPORT="$DEV_DMG_VERIFICATION_DIR/verification-report-$ARCHITECTURE.txt"
MOUNTED=0

cleanup() {
    if [[ "$MOUNTED" == 1 ]]; then
        hdiutil detach "$VARIANT_MOUNT" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

rm -rf "$VARIANT_DIR"
mkdir -p "$VARIANT_DIR" "$DEV_DMG_VERIFICATION_DIR"
ditto "$SOURCE_APP" "$VARIANT_APP"

while IFS= read -r -d '' path; do
    if file "$path" | grep -q 'Mach-O'; then
        mode="$(stat -f '%Lp' "$path")"
        thin_path="$path.thin"
        lipo -thin "$ARCHITECTURE" "$path" -output "$thin_path"
        chmod "$mode" "$thin_path"
        mv "$thin_path" "$path"
    fi
done < <(find "$VARIANT_APP/Contents" -type f -print0)

rm -f "$VARIANT_APP/Contents/Resources/BUILD-RECORD-$OTHER_ARCHITECTURE.txt"

PLIST="$VARIANT_APP/Contents/Info.plist"
set_plist_string() {
    local key="$1" value="$2"
    if plutil -extract "$key" raw -o - "$PLIST" >/dev/null 2>&1; then
        plutil -replace "$key" -string "$value" "$PLIST"
    else
        plutil -insert "$key" -string "$value" "$PLIST"
    fi
}

set_plist_string CFBundleIdentifier "dev.fsearch.desktop.development.$ARCHITECTURE"
set_plist_string CFBundleName "$VARIANT_APP_NAME"
set_plist_string CFBundleDisplayName "$VARIANT_APP_NAME"
set_plist_string CFBundleShortVersionString "$APP_VERSION"
set_plist_string FsearchDevelopmentVersion "${APP_VERSION}-dev.${BUILD_SHORT_COMMIT}-${ARCHITECTURE}"
set_plist_string FsearchBuildCommit "$BUILD_COMMIT"
set_plist_string FsearchEngineVersion "$(dev_dmg_upstream_version)"
set_plist_string FsearchPackageStatus "$DEV_DMG_PACKAGE_STATUS"
set_plist_string FsearchArchitecture "$ARCHITECTURE"

if plutil -extract FsearchDevelopmentBuild raw -o - "$PLIST" >/dev/null 2>&1; then
    plutil -replace FsearchDevelopmentBuild -bool true "$PLIST"
else
    plutil -insert FsearchDevelopmentBuild -bool true "$PLIST"
fi
if plutil -extract FsearchNotarized raw -o - "$PLIST" >/dev/null 2>&1; then
    plutil -replace FsearchNotarized -bool false "$PLIST"
else
    plutil -insert FsearchNotarized -bool false "$PLIST"
fi

codesign --force --deep --sign - "$VARIANT_APP"
codesign --verify --deep --strict "$VARIANT_APP"

rm -rf "$VARIANT_ROOT" "$VARIANT_MOUNT"
mkdir -p "$VARIANT_ROOT/build-records" "$VARIANT_MOUNT"
ditto "$VARIANT_APP" "$VARIANT_ROOT/$VARIANT_APP_NAME.app"
cp "$SOURCE_ROOT/PROJECT-LICENSE.txt" "$VARIANT_ROOT/PROJECT-LICENSE.txt"
cp "$SOURCE_ROOT/FSEARCH-LICENSE.txt" "$VARIANT_ROOT/FSEARCH-LICENSE.txt"
cp "$SOURCE_NOTICES" "$VARIANT_ROOT/THIRD-PARTY-NOTICES.txt"
cp "$SOURCE_ROOT/build-records/$ARCHITECTURE.txt" "$VARIANT_ROOT/build-records/$ARCHITECTURE.txt"
ln -s /Applications "$VARIANT_ROOT/Applications"

awk -v arch="$ARCHITECTURE" '
    /^Architectures:/ { print "Architectures: " arch; next }
    { print }
    END { print "Architecture variant: " arch }
' "$SOURCE_MANIFEST" > "$VARIANT_ROOT/BUILD-MANIFEST.txt"
cp "$VARIANT_ROOT/BUILD-MANIFEST.txt" "$VARIANT_MANIFEST"

cat > "$VARIANT_ROOT/DEVELOPMENT-README.txt" <<EOF
Fsearch Desktop Development ($ARCH_LABEL)

This is an unsigned, unnotarized development verification package.
- Architecture: $ARCHITECTURE
- This DMG contains only the $ARCHITECTURE application slice.
- It is not Developer ID signed and not notarized.
- The package was built from commit $BUILD_COMMIT.
- Runtime smoke for this thinned variant was not run on this host.
- Use the Universal DMG when you need the fully smoke-verified application bundle.

Install by dragging "$VARIANT_APP_NAME.app" onto the Applications link in this disk image.
The package does not run a CLI installer, change privacy settings, install global tools,
or publish a stable release.
EOF

hdiutil create -quiet -volname "$VARIANT_APP_NAME" -srcfolder "$VARIANT_ROOT" -ov -format UDZO "$VARIANT_DMG"

grep -v "  $VARIANT_DMG_NAME$" "$SOURCE_SUMS" > "$SOURCE_SUMS.tmp" || true
mv "$SOURCE_SUMS.tmp" "$SOURCE_SUMS"
(cd "$DEV_DMG_OUTPUT_DIR" && shasum -a 256 "$VARIANT_DMG_NAME" >> SHA256SUMS)

EXPECTED_HASH="$(awk -v artifact="$VARIANT_DMG_NAME" '$2 == artifact {print $1}' "$SOURCE_SUMS")"
ACTUAL_HASH="$(shasum -a 256 "$VARIANT_DMG" | awk '{print $1}')"
[[ -n "$EXPECTED_HASH" && "$EXPECTED_HASH" == "$ACTUAL_HASH" ]] || {
    echo "Architecture DMG SHA-256 does not match SHA256SUMS" >&2
    exit 1
}

hdiutil verify "$VARIANT_DMG" >/dev/null
hdiutil attach -nobrowse -readonly -mountpoint "$VARIANT_MOUNT" "$VARIANT_DMG" >/dev/null
MOUNTED=1

MOUNTED_APP="$VARIANT_MOUNT/$VARIANT_APP_NAME.app"
MOUNTED_EXECUTABLE="$MOUNTED_APP/Contents/MacOS/FsearchSample"
[[ -d "$MOUNTED_APP" ]] || { echo "Architecture DMG is missing the app bundle" >&2; exit 1; }
[[ -x "$MOUNTED_EXECUTABLE" ]] || { echo "Architecture DMG is missing the executable" >&2; exit 1; }
[[ "$(lipo -archs "$MOUNTED_EXECUTABLE")" == "$ARCHITECTURE" ]] || {
    echo "Unexpected executable architecture: $(lipo -archs "$MOUNTED_EXECUTABLE")" >&2
    exit 1
}
while IFS= read -r -d '' path; do
    if file "$path" | grep -q 'Mach-O'; then
        [[ "$(lipo -archs "$path")" == "$ARCHITECTURE" ]] || {
            echo "Embedded Mach-O has unexpected architecture: $path ($(lipo -archs "$path"))" >&2
            exit 1
        }
    fi
done < <(find "$MOUNTED_APP/Contents" -type f -print0)

plutil -lint "$MOUNTED_APP/Contents/Info.plist" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :FsearchArchitecture' "$MOUNTED_APP/Contents/Info.plist")" == "$ARCHITECTURE" ]]
codesign --verify --deep --strict "$MOUNTED_APP"
CODESIGN_DETAILS="$(codesign -dvvv "$MOUNTED_APP" 2>&1)"
printf '%s\n' "$CODESIGN_DETAILS" | grep -q 'Signature=adhoc'

{
    printf 'Architecture DMG verification: PASSED\n'
    printf 'DMG: %s\n' "$VARIANT_DMG_NAME"
    printf 'Architecture: %s\n' "$ARCHITECTURE"
    printf 'Application version: %s\n' "$APP_VERSION"
    printf 'Build commit: %s\n' "$BUILD_COMMIT"
    printf 'SHA-256: %s\n' "$ACTUAL_HASH"
    printf 'Signature: ad-hoc only, not Developer ID signed, not notarized\n'
    printf 'Runtime smoke: not run for this thinned variant\n'
    printf 'Static validation: DMG checksum, architecture slices, plist, and code signature passed\n'
} > "$VARIANT_REPORT"

cat "$VARIANT_REPORT"
printf 'Created %s\n' "$VARIANT_DMG"
