#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
source "$PROJECT_ROOT/scripts/dev-dmg-common.sh"
[[ $# == 2 && -f "$1" && "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo 'Usage: verify-signed-release.sh <downloaded.dmg> <version>' >&2; exit 2
}
DMG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
VERSION="$2"
DIRECTORY="$(dirname "$DMG")"
EXPECTED="$(awk -v name="$(basename "$DMG")" '$2 == name {print $1}' "$DIRECTORY/SHA256SUMS")"
ACTUAL="$(shasum -a 256 "$DMG" | awk '{print $1}')"
[[ -n "$EXPECTED" && "$ACTUAL" == "$EXPECTED" ]] || { echo 'Downloaded release hash mismatch.' >&2; exit 1; }
bash "$PROJECT_ROOT/scripts/release-preflight.sh" "v$VERSION" "$DIRECTORY/approval.json"
mkdir -p "$PROJECT_ROOT/.build/release-verification"
WORK="$(mktemp -d "$PROJECT_ROOT/.build/release-verification/run.XXXXXX")"
MOUNTED=0
cleanup() {
    dev_dmg_stop_smoke
    if [[ "$MOUNTED" == 1 ]]; then hdiutil detach "$WORK/mount" >/dev/null 2>&1 || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
REPORT="$PROJECT_ROOT/.build/release-verification/report.txt"
rm -f "$REPORT"
hdiutil verify "$DMG"
codesign --verify --strict "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"
mkdir -p "$WORK/mount" "$WORK/Applications" "$WORK/smoke"
hdiutil attach -readonly -nobrowse -mountpoint "$WORK/mount" "$DMG" >/dev/null
MOUNTED=1
APP="$WORK/mount/Fsearch Desktop.app"
PLIST="$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")" == dev.fsearch.desktop ]]
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" == "$VERSION" ]]
[[ "$(plutil -extract FsearchBuildCommit raw -o - "$PLIST")" == "$(git rev-parse HEAD)" ]]
[[ "$(plutil -extract FsearchPackageStatus raw -o - "$PLIST")" == release-candidate ]]
[[ "$(plutil -extract FsearchDevelopmentBuild raw -o - "$PLIST")" == false ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw -o - "$PLIST")" == 13.0 ]]
[[ "$(plutil -extract FsearchEngineVersion raw -o - "$PLIST")" == "$(dev_dmg_upstream_version)" ]]
while IFS= read -r -d '' executable; do
    if file "$executable" | grep -q 'Mach-O'; then
        [[ "$(lipo -archs "$executable" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')" == 'arm64 x86_64' ]]
    fi
done < <(find "$APP/Contents" -type f -print0)
cmp "$PROJECT_ROOT/LICENSE" "$APP/Contents/Resources/PROJECT-LICENSE.txt"
cmp "$PROJECT_ROOT/bridge/FSEARCH-LICENSE" "$APP/Contents/Resources/FSEARCH-LICENSE.txt"
cmp "$DIRECTORY/THIRD-PARTY-NOTICES.txt" "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"
codesign --verify --deep --strict "$APP"
DETAILS="$(codesign -dvvv "$APP" 2>&1)"
printf '%s\n' "$DETAILS" | grep -q '^Authority=Developer ID Application:'
printf '%s\n' "$DETAILS" | grep -q 'flags=.*runtime'
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"
INSTALLED="$WORK/Applications/Fsearch Desktop.app"
ditto "$APP" "$INSTALLED"
codesign --verify --deep --strict "$INSTALLED"
xcrun stapler validate "$INSTALLED"
spctl --assess --type execute "$INSTALLED"
dev_dmg_run_smoke "$INSTALLED/Contents/MacOS/FsearchSample" "$INSTALLED/Contents/Resources/sample" "$WORK/smoke" "$WORK/smoke.log"
grep -q 'Native search and file acceptance journeys: passed' "$WORK/smoke.log"
hdiutil detach "$WORK/mount" >/dev/null
MOUNTED=0
printf 'Downloaded signed release verification: PASSED\nVersion: %s\nCommit: %s\nSHA-256: %s\nHost: %s / %s\nGatekeeper, tickets, licenses, Universal slices and local installed journey passed.\nExternal hardware/TCC/clean-system evidence: approval.json, not inferred from this host.\n' \
    "$VERSION" "$(git rev-parse HEAD)" "$ACTUAL" "$(uname -m)" "$(sw_vers -productVersion)" > "$REPORT"
echo 'Downloaded signed release verified; eligible for publication only after all approval gates.'
