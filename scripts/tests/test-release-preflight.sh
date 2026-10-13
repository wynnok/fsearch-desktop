#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p .build/release-tests
WORK="$(mktemp -d "$ROOT/.build/release-tests/run.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
if bash scripts/release-preflight.sh v0.2.0 "$WORK/missing.json" > "$WORK/missing.log" 2>&1; then
    echo 'Release without approval unexpectedly passed' >&2; exit 1
fi
grep -q 'Missing release approval' "$WORK/missing.log"
echo 'Missing release approval: blocked'
if FSEARCH_CERTIFICATE_BASE64= bash scripts/sign-release-ci.sh > "$WORK/credentials.log" 2>&1; then
    echo 'CI signing without credentials passed' >&2; exit 1
fi
grep -q 'Missing signing configuration: FSEARCH_CERTIFICATE_BASE64' "$WORK/credentials.log"
echo 'Missing CI credentials: blocked before keychain creation'
printf 'controlled corrupt artifact' > "$WORK/Fsearch-Desktop-0.2.0-universal.dmg"
printf '%064d  Fsearch-Desktop-0.2.0-universal.dmg\n' 0 > "$WORK/SHA256SUMS"
if bash scripts/verify-signed-release.sh "$WORK/Fsearch-Desktop-0.2.0-universal.dmg" 0.2.0 > "$WORK/hash.log" 2>&1; then
    echo 'Corrupt downloaded release passed' >&2; exit 1
fi
grep -q 'Downloaded release hash mismatch' "$WORK/hash.log"
echo 'Downloaded hash mismatch: blocked before installation'
COMMIT="$(git rev-parse HEAD)"
ruby -rjson - "$COMMIT" "$WORK/approved.json" <<'RUBY'
commit, file = ARGV
gates = %w[t27 t28 intel macos13 tcc cleanInstall upstreamUpgrade ciDownload].to_h do |name|
  [name, {'result'=>'passed', 'sourceCommit'=>commit, 'url'=>'https://github.com/wynnok/fsearch-desktop/issues/41'}]
end
File.write(file, JSON.generate({'schemaVersion'=>1, 'tag'=>'v0.2.0', 'sourceCommit'=>commit,
  'approved'=>true, 'defaultMode'=>'engine', 'gates'=>gates}))
RUBY
# Controlled attestation proves validation only; it is never used to publish.
bash scripts/release-preflight.sh v0.2.0 "$WORK/approved.json"
for field in tag sourceCommit approved defaultMode intel; do
    ruby -rjson - "$WORK/approved.json" "$WORK/invalid.json" "$field" <<'RUBY'
record = JSON.parse(File.read(ARGV[0]))
field = ARGV[2]
field == 'intel' ? record['gates'].delete('intel') : record[field] = nil
File.write(ARGV[1], JSON.generate(record))
RUBY
    if bash scripts/release-preflight.sh v0.2.0 "$WORK/invalid.json" > "$WORK/invalid.log" 2>&1; then
        echo "Invalid $field approval passed" >&2; exit 1
    fi
    echo "Invalid $field approval: blocked"
done
