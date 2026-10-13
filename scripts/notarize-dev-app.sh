#!/bin/bash
# Uses an existing Developer ID identity and notarytool Keychain profile.
# No credential import, keychain mutation, tag creation or Release publication.
set +x
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
source "$PROJECT_ROOT/scripts/dev-dmg-common.sh"
[[ -n "${FSEARCH_SIGNING_IDENTITY:-}" && -n "${FSEARCH_NOTARY_PROFILE:-}" ]] || {
    echo 'Missing FSEARCH_SIGNING_IDENTITY or FSEARCH_NOTARY_PROFILE; T28 remains unverified.' >&2
    exit 2
}
[[ ( $# == 2 || ( $# == 4 && "$3" == --release-version ) ) && "$1" == --app && -d "$2" ]] || {
    echo 'Usage: bash scripts/notarize-dev-app.sh --app <verified development .app>' >&2; exit 2
}
INPUT_APP="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
RELEASE_VERSION="${4:-}"
mkdir -p "$PROJECT_ROOT/.build/signing"
RUN="$(mktemp -d "$PROJECT_ROOT/.build/signing/run.XXXXXX")"
chmod 700 "$RUN"
TEMP="$RUN/temporary"
mkdir -p "$TEMP"
STAGE=preflight
MOUNTED=0
SUCCESS=0
cleanup() {
    local result=$?
    dev_dmg_stop_smoke
    if [[ "$MOUNTED" == 1 ]]; then
        if ! hdiutil detach "$TEMP/mount" >/dev/null 2>&1; then
            SUCCESS=0; STAGE=detach; result=1
        fi
    fi
    if [[ "$SUCCESS" == 1 && "$result" == 0 ]]; then
        cp "$TEMP/validation-report.txt" "$RUN/validation-report.txt"
        printf 'Local signed-package validation: PASSED\nClean-system / Intel / macOS 13 validation: UNVERIFIED\n' > "$RUN/validation-status.txt"
    else
        rm -f "$RUN/SHA256SUMS"
        printf 'Validation: FAILED\nStage: %s\nT28 real signing and clean-system gates remain unverified.\n' "$STAGE" > "$RUN/validation-status.txt"
    fi
    # Raw tool responses can contain account information; retain only allowlisted summaries.
    rm -rf "$TEMP"
    printf 'Signing validation records: %s\n' "$RUN"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
run() {
    STAGE="$1"; shift
    if ! "$@" > "$TEMP/stdout" 2> "$TEMP/stderr"; then
        printf 'Signing validation failed at %s; raw credentials/tool output withheld.\n' "$STAGE" >&2
        return 1
    fi
}
fail() { echo "$1" >&2; exit 1; }

PLIST="$INPUT_APP/Contents/Info.plist"
[[ -f "$PLIST" && -x "$INPUT_APP/Contents/MacOS/FsearchSample" ]] || fail 'Incomplete development application.'
[[ "$(plutil -extract FsearchDevelopmentBuild raw -o - "$PLIST")" == true ]] || fail 'Expected a development application.'
[[ "$(plutil -extract FsearchPackageStatus raw -o - "$PLIST")" == development-unnotarized ]] || fail 'Expected the unnotarized development package.'
for resource in PROJECT-LICENSE.txt FSEARCH-LICENSE.txt THIRD-PARTY-NOTICES.txt BUILD-RECORD-arm64.txt BUILD-RECORD-x86_64.txt; do
    [[ -s "$INPUT_APP/Contents/Resources/$resource" ]] || fail 'Missing packaged license or build record.'
done
[[ -d "$INPUT_APP/Contents/Resources/sample" ]] || fail 'Missing controlled application sample.'
run source-signature codesign --verify --deep --strict "$INPUT_APP"
[[ "$(lipo -archs "$INPUT_APP/Contents/MacOS/FsearchSample" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')" == 'arm64 x86_64' ]] || fail 'Expected a Universal development application.'
# Keep identity values and keychain command output out of logs.
if [[ -n "${FSEARCH_SIGNING_KEYCHAIN:-}" ]]; then
    run signing-identity security find-identity -v -p codesigning "$FSEARCH_SIGNING_KEYCHAIN"
else
    run signing-identity security find-identity -v -p codesigning
fi
ruby - "$TEMP/stdout" "$FSEARCH_SIGNING_IDENTITY" <<'RUBY' || fail 'No matching valid Developer ID Application identity.'
rows = File.readlines(ARGV[0])
identity = ARGV[1]
exit(rows.any? { |row| row.include?('"Developer ID Application:') &&
  (row.include?('"' + identity + '"') || row.match?(/\b#{Regexp.escape(identity)}\b/) && identity.match?(/\A[0-9A-Fa-f]{40}\z/)) } ? 0 : 1)
RUBY

APP="$RUN/Fsearch Desktop Development.app"
if [[ -n "$RELEASE_VERSION" ]]; then
    [[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid release version.'
    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" == "$RELEASE_VERSION" ]] || fail 'Release version differs from the built application.'
    APP="$RUN/Fsearch Desktop.app"
fi
run copy-application ditto "$INPUT_APP" "$APP"
# Metadata is frozen before signing; this remains a development validation artifact.
run package-metadata plutil -replace FsearchPackageStatus -string development-signing-validation "$APP/Contents/Info.plist"
run remove-notary-claim plutil -remove FsearchNotarized "$APP/Contents/Info.plist"
if [[ -n "$RELEASE_VERSION" ]]; then
    run release-status plutil -replace FsearchPackageStatus -string release-candidate "$APP/Contents/Info.plist"
    run release-mode plutil -replace FsearchDevelopmentBuild -bool false "$APP/Contents/Info.plist"
    run release-identifier plutil -replace CFBundleIdentifier -string dev.fsearch.desktop "$APP/Contents/Info.plist"
    run release-name plutil -replace CFBundleName -string 'Fsearch Desktop' "$APP/Contents/Info.plist"
    run release-display-name plutil -replace CFBundleDisplayName -string 'Fsearch Desktop' "$APP/Contents/Info.plist"
fi
sign_code() {
    local stage="$1" target="$2" runtime="$3"
    set -- --force --sign "$FSEARCH_SIGNING_IDENTITY" --timestamp
    if [[ "$runtime" == runtime ]]; then set -- "$@" --options runtime; fi
    if [[ -n "${FSEARCH_SIGNING_KEYCHAIN:-}" ]]; then set -- "$@" --keychain "$FSEARCH_SIGNING_KEYCHAIN"; fi
    run "$stage" codesign "$@" "$target"
}
# The final validation report carries authoritative Accepted/staple evidence.
while IFS= read -r -d '' component; do
    if file "$component" | grep -q 'Mach-O'; then
        [[ "$(lipo -archs "$component" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')" == 'arm64 x86_64' ]] || fail 'Non-universal embedded executable.'
        sign_code sign-component "$component" runtime
    fi
done < <(find "$APP/Contents" -type f -print0)
while IFS= read -r -d '' component; do
    sign_code sign-bundle "$component" runtime
done < <(find "$APP/Contents" -depth -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.bundle' \) -print0)
sign_code sign-application "$APP" runtime
run verify-application codesign --verify --deep --strict "$APP"
run signature-details codesign -dvvv "$APP"
grep -q '^Authority=Developer ID Application:' "$TEMP/stderr" || fail 'Missing Developer ID authority.'
grep -q 'flags=.*runtime' "$TEMP/stderr" || fail 'Missing hardened runtime.'
grep -q '^Timestamp=' "$TEMP/stderr" || fail 'Missing secure timestamp.'

notarize() {
    local label="$1" artifact="$2" tool_result
    set -- notarytool submit "$artifact" --keychain-profile "$FSEARCH_NOTARY_PROFILE" --wait --timeout 15m --output-format json
    if [[ -n "${FSEARCH_SIGNING_KEYCHAIN:-}" ]]; then set -- "$@" --keychain "$FSEARCH_SIGNING_KEYCHAIN"; fi
    if run "submit-$label" xcrun "$@"; then
        tool_result=0
    else
        tool_result=1
    fi
    STAGE="notary-status-$label"
    ruby -rjson - "$TEMP/stdout" "$RUN/$label-notarization.json" > "$TEMP/parser-stdout" 2> "$TEMP/parser-stderr" <<'RUBY' || fail 'Notarization response was not Accepted; inspect the safe summary.'
begin
  raw = JSON.parse(File.read(ARGV[0]))
  raw = {} unless raw.is_a?(Hash)
rescue JSON::ParserError
  raw = {}
end
id = raw['id'].to_s
status = raw['status'].to_s
id = 'unknown' unless id.match?(/\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/)
status = 'unknown' unless %w[Accepted Invalid Rejected In\ Progress].include?(status)
File.write(ARGV[1], JSON.pretty_generate({'id' => id, 'status' => status}) + "\n")
exit(status == 'Accepted' && id != 'unknown' ? 0 : 1)
RUBY
    [[ "$tool_result" == 0 ]] || fail 'Notarization tool failed; no success is inferred from its output.'
}
run archive-application ditto -c -k --keepParent "$APP" "$TEMP/application.zip"
notarize app "$TEMP/application.zip"
run staple-application xcrun stapler staple "$APP"
run validate-application-ticket xcrun stapler validate "$APP"
run assess-application spctl --assess --type execute "$APP"
mkdir -p "$TEMP/dmg-root"
run copy-signed-application ditto "$APP" "$TEMP/dmg-root/$(basename "$APP")"
ln -s /Applications "$TEMP/dmg-root/Applications"
if [[ -n "$RELEASE_VERSION" ]]; then
    printf 'Fsearch Desktop %s release candidate. Final acceptance is recorded alongside the DMG.\n' "$RELEASE_VERSION" > "$TEMP/dmg-root/VALIDATION-README.txt"
else
    printf 'Signed development validation artifact. Not a stable release or alpha acceptance.\n' > "$TEMP/dmg-root/VALIDATION-README.txt"
fi
DMG="$RUN/Fsearch-Desktop-signing-validation.dmg"
run create-dmg hdiutil create -quiet -volname 'Fsearch Signing Validation' -srcfolder "$TEMP/dmg-root" -format UDZO "$DMG"
sign_code sign-dmg "$DMG" dmg
notarize dmg "$DMG"
run staple-dmg xcrun stapler staple "$DMG"
run validate-dmg-ticket xcrun stapler validate "$DMG"
run verify-dmg-signature codesign --verify --strict "$DMG"
run assess-dmg spctl --assess --type open --context context:primary-signature "$DMG"
run verify-dmg hdiutil verify "$DMG"
mkdir -p "$TEMP/mount" "$TEMP/Applications"
run mount-dmg hdiutil attach -readonly -nobrowse -mountpoint "$TEMP/mount" "$DMG"
MOUNTED=1
INSTALLED="$TEMP/Applications/$(basename "$APP")"
run install-application ditto "$TEMP/mount/$(basename "$APP")" "$INSTALLED"
run verify-installed codesign --verify --deep --strict "$INSTALLED"
run validate-installed-ticket xcrun stapler validate "$INSTALLED"
run assess-installed spctl --assess --type execute "$INSTALLED"
mkdir -p "$TEMP/smoke"
STAGE=installed-smoke
dev_dmg_run_smoke "$INSTALLED/Contents/MacOS/FsearchSample" "$INSTALLED/Contents/Resources/sample" "$TEMP/smoke" "$TEMP/stdout" || fail 'Installed application smoke failed.'
grep -q 'Native search and file acceptance journeys: passed' "$TEMP/stdout" || fail 'Installed acceptance journey evidence is missing.'
grep '^Native ' "$TEMP/stdout" > "$RUN/smoke-summary.txt"
run unmount-dmg hdiutil detach "$TEMP/mount"
MOUNTED=0
(cd "$RUN" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS)
{
    printf 'Host: %s / %s\n' "$(uname -m)" "$(sw_vers -productVersion)"
    printf 'Application version: %s\n' "$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
    printf 'Build commit: %s\n' "$(plutil -extract FsearchBuildCommit raw -o - "$APP/Contents/Info.plist")"
    printf 'Engine: %s\n' "$(plutil -extract FsearchEngineVersion raw -o - "$APP/Contents/Info.plist")"
    printf 'App and DMG notarization: Accepted; both tickets stapled and validated\n'
    printf 'Installed local application: codesign, stapler, spctl and controlled journey passed\n'
    printf 'Clean-system, Intel hardware and macOS 13 validation: UNVERIFIED\n'
    printf 'No tag or Release was published.\n'
} > "$TEMP/validation-report.txt"
STAGE=complete
SUCCESS=1
