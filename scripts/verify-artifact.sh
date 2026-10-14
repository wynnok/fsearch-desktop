#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
select_architecture "${1:?Expected architecture}" "${2:-debug}"
ARTIFACTS="$PROJECT_ROOT/.build/artifacts/$ARCHITECTURE/$CONFIGURATION"
APP="$ARTIFACTS/FsearchSample.app"
EXECUTABLE="$APP/Contents/MacOS/FsearchSample"
mkdir -p "$ARTIFACTS"
REPORT="$ARTIFACTS/artifact-check.txt"

check_architecture() {
    local path="$1"
    local architectures
    architectures="$(lipo -archs "$path")"
    printf '%s: %s\n' "$path" "$architectures"
    [[ "$architectures" == "$ARCHITECTURE" ]] || { echo "Unexpected architecture: $path" >&2; return 1; }
}

check_deployment_target() {
    # Rust stdlib may target an older OS; every object must support macOS 13.
    otool -l "$1" | awk '
        /cmd LC_BUILD_VERSION/ { build = 1; legacy = 0 }
        /cmd LC_VERSION_MIN_MACOSX/ { legacy = 1; build = 0 }
        /cmd LC_/ && !/cmd LC_BUILD_VERSION|cmd LC_VERSION_MIN_MACOSX/ { build = 0; legacy = 0 }
        (build && $1 == "minos") || (legacy && $1 == "version") {
            split($2, version, ".")
            count++
            if (version[1] > 13 || (version[1] == 13 && version[2] > 0)) {
                print "Unsupported minimum OS: " $2 > "/dev/stderr"
                failed = 1
            }
        }
        END { if (!count) { print "No deployment target found" > "/dev/stderr"; exit 1 }; exit failed }
    '
}

{
    check_architecture "$RUST_ARCHIVE"
    check_architecture "$EXECUTABLE"
    check_deployment_target "$RUST_ARCHIVE"
    check_deployment_target "$EXECUTABLE"
    printf 'Deployment targets: all archive objects and executable <= macOS 13.0\n'
    plutil -lint "$APP/Contents/Info.plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == 13.0 ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist")" == AppIcon ]]
    [[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || { echo 'Missing application icon resource' >&2; exit 1; }
    codesign --verify "$APP"
    # Rust is statically embedded; all remaining dylibs must be OS supplied.
    otool -L "$EXECUTABLE"
    while IFS= read -r dependency; do
        case "$dependency" in
            /System/Library/*|/usr/lib/*) ;;
            *) echo "Unexpected non-system dynamic dependency: $dependency" >&2; exit 1 ;;
        esac
    done < <(otool -L "$EXECUTABLE" | awk 'NR > 1 {print $1}')
    # Also inspect any future embedded executable/dylib, not only the app entry.
    while IFS= read -r path; do
        if file "$path" | rg -q 'Mach-O'; then
            check_architecture "$path"
            check_deployment_target "$path"
        fi
    done < <(find "$APP/Contents" -type f)
    printf 'Artifact validation: passed (build/link evidence only)\n'
} > "$REPORT"
cat "$REPORT"
