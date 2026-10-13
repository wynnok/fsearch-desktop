#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT"
mkdir -p .build/signing-tests
TEST_ROOT="$(mktemp -d "$PROJECT_ROOT/.build/signing-tests/run.XXXXXX")"
TEST_RUNS=()
cleanup() {
    for directory in "${TEST_RUNS[@]:-}"; do
        if [[ -n "$directory" ]]; then rm -rf "$directory"; fi
    done
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT
if FSEARCH_SIGNING_IDENTITY= FSEARCH_NOTARY_PROFILE= bash scripts/notarize-dev-app.sh > "$TEST_ROOT/missing.log" 2>&1; then
    echo 'Missing credentials unexpectedly passed' >&2; exit 1
fi
grep -q 'Missing FSEARCH_SIGNING_IDENTITY or FSEARCH_NOTARY_PROFILE' "$TEST_ROOT/missing.log"
echo 'Missing signing credentials: passed'

APP="$TEST_ROOT/Controlled.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/sample" "$TEST_ROOT/bin"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>FsearchDevelopmentBuild</key><true/>
<key>FsearchPackageStatus</key><string>development-unnotarized</string>
<key>FsearchNotarized</key><false/>
</dict></plist>
PLIST
printf '#!/bin/bash\nexit 0\n' > "$APP/Contents/MacOS/FsearchSample"
chmod +x "$APP/Contents/MacOS/FsearchSample"
for resource in PROJECT-LICENSE.txt FSEARCH-LICENSE.txt THIRD-PARTY-NOTICES.txt BUILD-RECORD-arm64.txt BUILD-RECORD-x86_64.txt; do
    echo 'Controlled fixture, not a real package' > "$APP/Contents/Resources/$resource"
done

# Exercise the shared command runner against a real process that ignores TERM.
source "$PROJECT_ROOT/scripts/dev-dmg-common.sh"
mkfifo "$TEST_ROOT/wait-pipe"
exec 3<> "$TEST_ROOT/wait-pipe"
(
    trap '' TERM
    printf 'ready' > "$TEST_ROOT/ready"
    while :; do read -r -t 60 ignored <&3 || true; done
) &
DEV_DMG_SMOKE_PID=$!
child="$DEV_DMG_SMOKE_PID"
for _ in {1..100}; do [[ -f "$TEST_ROOT/ready" ]] && break; sleep 0.01; done
(
    read -r -t 8 ignored <&3 || true
    kill -KILL "$child" 2>/dev/null || true
) &
watchdog=$!
started=$SECONDS
dev_dmg_stop_smoke
elapsed=$((SECONDS - started))
kill -TERM "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null || true
exec 3>&-
[[ "$elapsed" -lt 6 ]] || { echo 'Smoke termination exceeded its bounded cleanup window' >&2; exit 1; }
! kill -0 "$child" 2>/dev/null
echo 'TERM-resistant process cleanup: passed'
cat > "$TEST_ROOT/bin/driver" <<'MOCK'
#!/bin/bash
set -euo pipefail
tool="$(basename "$0")"
printf '%s %s\n' "$tool" "${1:-}" >> "$MOCK_TRACE"
case "$tool" in
    security) printf '1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Developer ID Application: Controlled Fixture"\n' ;;
    file) echo 'Mach-O universal binary' ;;
    lipo) echo 'arm64 x86_64' ;;
    codesign)
        if [[ "$MOCK_CASE" == sign-failure && "$1" == --force ]]; then echo 'private-sentinel' >&2; exit 1; fi
        if [[ "$1" == -dvvv ]]; then
            printf 'Authority=Developer ID Application: Controlled Fixture\nflags=0x10000(runtime)\nTimestamp=controlled\n' >&2
        fi
        ;;
    xcrun)
        if [[ "$1" == notarytool ]]; then
            case "$MOCK_CASE" in
                network-failure) echo 'private-sentinel' >&2; exit 1 ;;
                malformed-response) echo 'private-sentinel not json'; exit 0 ;;
                rejected) status=Invalid ;;
                *) status=Accepted ;;
            esac
            printf '{"id":"11111111-2222-3333-4444-555555555555","status":"%s","message":"private-sentinel"}\n' "$status"
        elif [[ "$MOCK_CASE" == staple-failure ]]; then echo 'private-sentinel' >&2; exit 1
        fi
        ;;
    spctl) echo 'private-sentinel' >&2; exit 1 ;;
esac
MOCK
chmod +x "$TEST_ROOT/bin/driver"
for command in security file lipo codesign xcrun spctl; do ln -s driver "$TEST_ROOT/bin/$command"; done
SOURCE_HASH="$(shasum -a 256 "$APP/Contents/Info.plist")"
for scenario in sign-failure network-failure malformed-response rejected staple-failure gatekeeper-failure; do
    log="$TEST_ROOT/$scenario.log"
    trace="$TEST_ROOT/$scenario.trace"
    if PATH="$TEST_ROOT/bin:$PATH" MOCK_CASE="$scenario" MOCK_TRACE="$trace" \
        FSEARCH_SIGNING_IDENTITY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA FSEARCH_NOTARY_PROFILE=controlled-profile \
        bash scripts/notarize-dev-app.sh --app "$APP" > "$log" 2>&1; then
        echo "Controlled failure unexpectedly passed: $scenario" >&2; exit 1
    fi
    directory="$(sed -n 's/^Signing validation records: //p' "$log")"
    [[ "$directory" == "$PROJECT_ROOT/.build/signing/run."* && -d "$directory" ]]
    TEST_RUNS+=("$directory")
    grep -q 'Validation: FAILED' "$directory/validation-status.txt"
    [[ ! -e "$directory/validation-report.txt" && ! -e "$directory/temporary" && ! -e "$directory/SHA256SUMS" ]]
    if rg -q 'private-sentinel' "$log" "$directory"; then echo 'Raw tool output leaked' >&2; exit 1; fi
    [[ "$(shasum -a 256 "$APP/Contents/Info.plist")" == "$SOURCE_HASH" ]]
    if [[ "$scenario" == rejected ]]; then
        grep -q '"status": "Invalid"' "$directory/app-notarization.json"
        ! grep -q '^spctl' "$trace"
    fi
    echo "Controlled $scenario: passed"
done
