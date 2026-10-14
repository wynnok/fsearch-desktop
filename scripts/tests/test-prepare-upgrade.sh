#!/bin/bash
# Controlled T24 checks for scripts/prepare-upgrade.sh. Uses a temp root with
# the three pin files plus injectable lock-refresh and compatibility commands,
# so the detect -> change -> check -> report path is exercised without network,
# Swift, Cargo, or GitHub access.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT"
mkdir -p .build/upgrade-tests
TEST_ROOT="$(mktemp -d "$PROJECT_ROOT/.build/upgrade-tests/run.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

ORIG_VERSION=0.2.1
ORIG_COMMIT=88e63fdf850cf7749deae8198b187accd21f8ba5
NEW_VERSION=0.3.0
NEW_COMMIT=abcdefabcdefabcdefabcdefabcdefabcdefabcd

write_lock() {
    local directory="$1" version="$2" commit="$3"
    cat > "$directory/bridge/Cargo.lock" <<EOF
version = 4

[[package]]
name = "fsearch"
version = "$version"
source = "git+https://github.com/noahdunnagan/fsearch?rev=$commit#$commit"
dependencies = []
EOF
}

make_root() {
    local directory="$1"
    mkdir -p "$directory/bridge/src"
    cat > "$directory/bridge/Cargo.toml" <<EOF
[package]
name = "fsearch-bridge"
version = "0.1.0"

[dependencies]
fsearch = { git = "https://github.com/noahdunnagan/fsearch", rev = "$ORIG_COMMIT" }
EOF
    write_lock "$directory" "$ORIG_VERSION" "$ORIG_COMMIT"
    printf 'const UPSTREAM_VERSION: &str = "%s / %s";\n' "$ORIG_VERSION" "$ORIG_COMMIT" \
        > "$directory/bridge/src/lib.rs"
    cp "$PROJECT_ROOT/bridge/upstream-patches.json" "$directory/bridge/upstream-patches.json"
}

write_check_result() {
    local path="$1" status="$2" version="$3" commit="$4" tag="$5"
    local candidate='null' update=false
    if [[ "$status" == update_available ]]; then
        update=true
        candidate="$(jq -n --arg v "$version" --arg t "$tag" --arg c "$commit" \
            '{version: $v, tag: $t, commit: $c,
              release_url: ("https://github.com/noahdunnagan/fsearch/releases/tag/" + $t)}')"
    fi
    jq -n \
        --arg status "$status" \
        --argjson update "$update" \
        --arg cv "$ORIG_VERSION" \
        --arg cc "$ORIG_COMMIT" \
        --argjson candidate "$candidate" \
        '{status: $status, update_available: $update,
          current: {version: $cv, commit: $cc},
          candidate: $candidate, selection: null, error: null,
          run_url: "https://github.com/wynnok/fsearch-desktop/actions/runs/1"}' > "$path"
}

cat > "$TEST_ROOT/lock-refresh.sh" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
rev="$(sed -n 's/.*rev = "\([0-9a-f]\{40\}\)".*/\1/p' "$FSEARCH_PIN_CARGO_TOML")"
ver="$(sed -n 's/^const UPSTREAM_VERSION: &str = "\([^ ]*\) \/.*/\1/p' "$FSEARCH_PIN_LIBRARY")"
cat > "$FSEARCH_PIN_CARGO_LOCK" <<LOCK
version = 4

[[package]]
name = "fsearch"
version = "$ver"
source = "git+https://github.com/noahdunnagan/fsearch?rev=$rev#$rev"
dependencies = []
LOCK
SCRIPT
chmod +x "$TEST_ROOT/lock-refresh.sh"
printf '#!/bin/bash\nexit 0\n' > "$TEST_ROOT/compat-pass.sh"
printf '#!/bin/bash\necho "compat failure" >&2\nexit 1\n' > "$TEST_ROOT/compat-fail.sh"
chmod +x "$TEST_ROOT/compat-pass.sh" "$TEST_ROOT/compat-fail.sh"

prepare() {
    local root="$1" check="$2" compat="$3"
    FSEARCH_UPGRADE_ROOT="$root" \
    FSEARCH_UPGRADE_LOCK_COMMAND="$TEST_ROOT/lock-refresh.sh" \
    FSEARCH_UPGRADE_COMPAT_COMMAND="$compat" \
        bash scripts/prepare-upgrade.sh --check-result "$check" --output-dir "$root/.build/upgrade"
}

# 1. No update: no dependency change and a no-op report.
ROOT="$TEST_ROOT/no-update"
make_root "$ROOT"
write_check_result "$TEST_ROOT/no-update.json" current "$ORIG_VERSION" "$ORIG_COMMIT" "v$ORIG_VERSION"
BEFORE="$(shasum -a 256 "$ROOT/bridge/Cargo.toml" "$ROOT/bridge/Cargo.lock" "$ROOT/bridge/src/lib.rs")"
prepare "$ROOT" "$TEST_ROOT/no-update.json" "$TEST_ROOT/compat-pass.sh" > "$TEST_ROOT/no-update.log" 2>&1
grep -q 'Outcome: no-op' "$ROOT/.build/upgrade/report.md"
[[ "$(shasum -a 256 "$ROOT/bridge/Cargo.toml" "$ROOT/bridge/Cargo.lock" "$ROOT/bridge/src/lib.rs")" == "$BEFORE" ]]
echo 'No-update no-op: passed'

# 2. New candidate: pin files change, checks pass, report is pr-ready.
ROOT="$TEST_ROOT/candidate"
make_root "$ROOT"
write_check_result "$TEST_ROOT/candidate.json" update_available "$NEW_VERSION" "$NEW_COMMIT" "v$NEW_VERSION"
prepare "$ROOT" "$TEST_ROOT/candidate.json" "$TEST_ROOT/compat-pass.sh" > "$TEST_ROOT/candidate.log" 2>&1
grep -q "rev = \"$NEW_COMMIT\"" "$ROOT/bridge/Cargo.toml"
grep -q "UPSTREAM_VERSION: &str = \"$NEW_VERSION / $NEW_COMMIT\"" "$ROOT/bridge/src/lib.rs"
grep -q "rev=$NEW_COMMIT#$NEW_COMMIT" "$ROOT/bridge/Cargo.lock"
grep -q 'Outcome: pr-ready' "$ROOT/.build/upgrade/report.md"
grep -q "Branch (dedup key): \`upgrade/fsearch-v$NEW_VERSION-${NEW_COMMIT:0:12}\`" "$ROOT/.build/upgrade/report.md"
[[ "$(jq -r '.outcome' "$ROOT/.build/upgrade/result.json")" == pr-ready ]]
[[ "$(jq -r '.branch' "$ROOT/.build/upgrade/result.json")" == "upgrade/fsearch-v$NEW_VERSION-${NEW_COMMIT:0:12}" ]]
echo 'Candidate upgrade: passed'

# 3. Duplicate: a second run for the same candidate is idempotent and reuses the branch key.
BEFORE="$(shasum -a 256 "$ROOT/bridge/Cargo.toml" "$ROOT/bridge/Cargo.lock" "$ROOT/bridge/src/lib.rs")"
prepare "$ROOT" "$TEST_ROOT/candidate.json" "$TEST_ROOT/compat-pass.sh" > "$TEST_ROOT/duplicate.log" 2>&1
[[ "$(shasum -a 256 "$ROOT/bridge/Cargo.toml" "$ROOT/bridge/Cargo.lock" "$ROOT/bridge/src/lib.rs")" == "$BEFORE" ]]
grep -q "Branch (dedup key): \`upgrade/fsearch-v$NEW_VERSION-${NEW_COMMIT:0:12}\`" "$ROOT/.build/upgrade/report.md"
echo 'Duplicate candidate: passed'

# 4. Network/API error: retained pin, no-op report, no change.
ROOT="$TEST_ROOT/error"
make_root "$ROOT"
write_check_result "$TEST_ROOT/error.json" error "$ORIG_VERSION" "$ORIG_COMMIT" "v$ORIG_VERSION"
BEFORE="$(shasum -a 256 "$ROOT/bridge/Cargo.toml" "$ROOT/bridge/Cargo.lock" "$ROOT/bridge/src/lib.rs")"
prepare "$ROOT" "$TEST_ROOT/error.json" "$TEST_ROOT/compat-pass.sh" > "$TEST_ROOT/error.log" 2>&1
grep -q 'Outcome: no-op' "$ROOT/.build/upgrade/report.md"
[[ "$(shasum -a 256 "$ROOT/bridge/Cargo.toml" "$ROOT/bridge/Cargo.lock" "$ROOT/bridge/src/lib.rs")" == "$BEFORE" ]]
echo 'Network/API error retention: passed'

# 5. Compatibility failure: candidate retained, diagnostics kept, no PR-ready outcome.
ROOT="$TEST_ROOT/compat-fail"
make_root "$ROOT"
if prepare "$ROOT" "$TEST_ROOT/candidate.json" "$TEST_ROOT/compat-fail.sh" > "$TEST_ROOT/compat-fail.log" 2>&1; then
    echo 'Compatibility failure unexpectedly succeeded' >&2; exit 1
fi
grep -q "rev = \"$NEW_COMMIT\"" "$ROOT/bridge/Cargo.toml"
grep -q 'Outcome: failed' "$ROOT/.build/upgrade/report.md"
[[ "$(jq -r '.outcome' "$ROOT/.build/upgrade/result.json")" == failed ]]
[[ -s "$ROOT/.build/upgrade/logs/compat.log" ]]
echo 'Compatibility failure retention: passed'

echo 'Controlled prepare-upgrade scenarios: passed'
