#!/bin/bash
# CI-only credentials live in a project-local temporary keychain; never log them.
set +x
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
for key in FSEARCH_CERTIFICATE_BASE64 FSEARCH_CERTIFICATE_PASSWORD FSEARCH_NOTARY_KEY_BASE64 FSEARCH_NOTARY_KEY_ID FSEARCH_NOTARY_ISSUER FSEARCH_SIGNING_IDENTITY; do
    [[ -n "${!key:-}" ]] || { echo "Missing signing configuration: $key" >&2; exit 2; }
done
[[ "${GITHUB_ACTIONS:-}" == true && $# == 2 ]] || { echo 'CI signing requires GitHub Actions and app/version arguments.' >&2; exit 2; }
APP="$1"
VERSION="$2"
mkdir -p "$PROJECT_ROOT/.build/signing-ci" "$PROJECT_ROOT/.build/release-output"
WORK="$(mktemp -d "$PROJECT_ROOT/.build/signing-ci/run.XXXXXX")"
chmod 700 "$WORK"
KEYCHAIN="$WORK/signing.keychain-db"
CREATED=0
cleanup() {
    if [[ "$CREATED" == 1 ]]; then security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
secure() { if ! "$@" > "$WORK/tool-output" 2>&1; then echo 'CI signing setup failed; raw credential output withheld.' >&2; exit 1; fi; }
secure ruby -rbase64 - "$WORK" <<'RUBY'
File.write(File.join(ARGV[0], 'certificate.p12'), Base64.strict_decode64(ENV.fetch('FSEARCH_CERTIFICATE_BASE64')), perm: 0600)
File.write(File.join(ARGV[0], 'notary.p8'), Base64.strict_decode64(ENV.fetch('FSEARCH_NOTARY_KEY_BASE64')), perm: 0600)
RUBY
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
secure security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
CREATED=1
secure security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
secure security import "$WORK/certificate.p12" -k "$KEYCHAIN" -P "$FSEARCH_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
secure security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
secure xcrun notarytool store-credentials release-notary --key "$WORK/notary.p8" --key-id "$FSEARCH_NOTARY_KEY_ID" --issuer "$FSEARCH_NOTARY_ISSUER" --keychain "$KEYCHAIN"
export FSEARCH_SIGNING_KEYCHAIN="$KEYCHAIN" FSEARCH_NOTARY_PROFILE=release-notary
bash "$PROJECT_ROOT/scripts/notarize-dev-app.sh" --app "$APP" --release-version "$VERSION" > "$WORK/validation.log" 2>&1 || { echo 'Real signing/notarization failed; no release assets prepared.' >&2; exit 1; }
RESULT="$(sed -n 's/^Signing validation records: //p' "$WORK/validation.log")"
[[ "$RESULT" == "$PROJECT_ROOT/.build/signing/run."* && -f "$RESULT/validation-report.txt" ]] || { echo 'Missing real signing evidence.' >&2; exit 1; }
grep -q '^Local signed-package validation: PASSED$' "$RESULT/validation-status.txt"
OUTPUT="$PROJECT_ROOT/.build/release-output"
DMG="Fsearch-Desktop-$VERSION-universal.dmg"
cp "$RESULT/Fsearch-Desktop-signing-validation.dmg" "$OUTPUT/$DMG"
cp "$RESULT/validation-report.txt" "$OUTPUT/"
cp "$RESULT/app-notarization.json" "$RESULT/dmg-notarization.json" "$OUTPUT/"
cp "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt" "$OUTPUT/"
(cd "$OUTPUT" && shasum -a 256 "$DMG" > SHA256SUMS)
echo 'Real signed/notarized assets prepared; publication is a separate gated job.'
