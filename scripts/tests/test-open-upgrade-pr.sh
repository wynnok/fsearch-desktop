#!/bin/bash
# Controlled checks for scripts/open-upgrade-pr.sh. git and gh are replaced by
# local fakes so branch reuse (dedup) and draft-on-failure can be exercised
# without a real remote.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT"
mkdir -p .build/upgrade-pr-tests
TEST_ROOT="$(mktemp -d "$PROJECT_ROOT/.build/upgrade-pr-tests/run.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

cat > "$TEST_ROOT/git" <<'SCRIPT'
#!/bin/bash
printf 'git %s\n' "$*" >> "$FSEARCH_TEST_LOG"
if [[ "$1" == ls-remote ]]; then
    if [[ "${FSEARCH_TEST_BRANCH_EXISTS:-0}" == 1 ]]; then echo 'abcdef refs/heads/upgrade/fsearch-v0.3.0-abcdefabcdef'; fi
    exit 0
fi
if [[ "$1" == show-ref ]]; then exit 1; fi
if [[ "$1" == rev-parse && "$*" == *MERGE_HEAD* ]]; then exit 1; fi
exit 0
SCRIPT
cat > "$TEST_ROOT/gh" <<'SCRIPT'
#!/bin/bash
printf 'gh %s\n' "$*" >> "$FSEARCH_TEST_LOG"
if [[ "$1" == pr && "$2" == list ]]; then
    if [[ "${FSEARCH_TEST_PR_EXISTS:-0}" == 1 ]]; then
        printf '{"number":7,"isDraft":%s}\n' "${FSEARCH_TEST_PR_DRAFT:-true}"
    fi
    exit 0
fi
if [[ "$1" == pr && "$2" == create ]]; then
    echo "https://github.com/wynnok/fsearch-desktop/pull/99"
    exit 0
fi
exit 0
SCRIPT
chmod +x "$TEST_ROOT/git" "$TEST_ROOT/gh"
printf '# candidate report\n' > "$TEST_ROOT/body.md"

run() {
    FSEARCH_UPGRADE_GIT="$TEST_ROOT/git" \
    FSEARCH_UPGRADE_GH="$TEST_ROOT/gh" \
    FSEARCH_TEST_LOG="$TEST_ROOT/log" \
        bash scripts/open-upgrade-pr.sh \
            --branch upgrade/fsearch-v0.3.0-abcdefabcdef \
            --base main \
            --title 'Upgrade embedded Fsearch to 0.3.0' \
            --body-file "$TEST_ROOT/body.md" \
            --message 'Upgrade embedded Fsearch to v0.3.0' "$@"
}

# 1. Fresh candidate: push a new branch (with -u) and open a normal PR.
: > "$TEST_ROOT/log"
FSEARCH_TEST_BRANCH_EXISTS=0 FSEARCH_TEST_PR_EXISTS=0 run > "$TEST_ROOT/new.out" 2>&1
grep -q 'git push -u origin HEAD:refs/heads/upgrade/fsearch-v0.3.0-abcdefabcdef' "$TEST_ROOT/log"
grep -q 'gh pr create ' "$TEST_ROOT/log"
grep -q -- '--draft' "$TEST_ROOT/log" && { echo 'Fresh PR was unexpectedly draft' >&2; exit 1; }
echo 'Fresh candidate PR: passed'

# 2. Duplicate: unchanged branch and open PR are reused, with a fresh report/state.
: > "$TEST_ROOT/log"
FSEARCH_TEST_BRANCH_EXISTS=1 FSEARCH_TEST_PR_EXISTS=1 run > "$TEST_ROOT/reuse.out" 2>&1
grep -q 'Reusing existing upgrade pull request #7' "$TEST_ROOT/reuse.out"
grep -q 'gh pr edit 7 ' "$TEST_ROOT/log"
grep -q 'gh pr ready 7' "$TEST_ROOT/log"
grep -q 'git push' "$TEST_ROOT/log" && { echo 'Duplicate candidate unexpectedly pushed' >&2; exit 1; }
grep -q 'gh pr create' "$TEST_ROOT/log" && { echo 'Duplicate candidate unexpectedly created a PR' >&2; exit 1; }
echo 'Duplicate candidate reuse: passed'

# 3. Failing candidate: a draft PR is opened instead of a mergeable one.
: > "$TEST_ROOT/log"
FSEARCH_TEST_BRANCH_EXISTS=0 FSEARCH_TEST_PR_EXISTS=0 run --draft > "$TEST_ROOT/draft.out" 2>&1
grep -q 'gh pr create ' "$TEST_ROOT/log"
grep -q -- '--draft' "$TEST_ROOT/log"
echo 'Failing candidate draft PR: passed'

: > "$TEST_ROOT/log"
FSEARCH_TEST_BRANCH_EXISTS=1 FSEARCH_TEST_PR_EXISTS=1 FSEARCH_TEST_PR_DRAFT=false \
    run --draft > "$TEST_ROOT/redraft.out" 2>&1
grep -q 'gh pr ready 7 --undo' "$TEST_ROOT/log"
echo 'A newly failing candidate returns an existing ready PR to draft: passed'

# Exercise retry against a real local remote: the first draft has an old lock,
# the retry repairs it on the same branch without rewriting remote history.
GIT_BIN="$(command -v git)"
"$GIT_BIN" init --bare -q "$TEST_ROOT/remote.git"
"$GIT_BIN" init -q -b main "$TEST_ROOT/retry"
(
    cd "$TEST_ROOT/retry"
    "$GIT_BIN" config user.name 'Upgrade test'
    "$GIT_BIN" config user.email 'upgrade@example.com'
    mkdir -p bridge/src
    printf 'old pin\n' > bridge/Cargo.toml
    printf 'old lock\n' > bridge/Cargo.lock
    printf 'old version\n' > bridge/src/lib.rs
    "$GIT_BIN" add bridge/Cargo.toml bridge/Cargo.lock bridge/src/lib.rs
    "$GIT_BIN" commit -qm 'Initial pin'
    "$GIT_BIN" remote add origin "$TEST_ROOT/remote.git"
    "$GIT_BIN" push -q -u origin main
    retry() {
        FSEARCH_UPGRADE_GIT="$GIT_BIN" FSEARCH_UPGRADE_GH="$TEST_ROOT/gh" \
        FSEARCH_TEST_LOG="$TEST_ROOT/retry.log" FSEARCH_TEST_PR_EXISTS="$1" \
            bash "$PROJECT_ROOT/scripts/open-upgrade-pr.sh" \
                --branch upgrade/fsearch-v0.3.0-abcdefabcdef --base main \
                --title 'Upgrade retry' --body-file "$TEST_ROOT/body.md" \
                --message 'Upgrade retry' "${@:2}"
    }
    printf 'candidate pin\n' > bridge/Cargo.toml
    printf 'candidate version\n' > bridge/src/lib.rs
    retry 0 --draft > "$TEST_ROOT/first-retry.out" 2>&1
    FIRST="$($GIT_BIN rev-parse HEAD)"
    "$GIT_BIN" checkout -q main
    mkdir -p Sources
    printf 'compatibility fix checked on main\n' > Sources/compat.swift
    "$GIT_BIN" add Sources/compat.swift
    "$GIT_BIN" commit -qm 'Fix compatibility on main'
    printf 'candidate pin\n' > bridge/Cargo.toml
    printf 'candidate version\n' > bridge/src/lib.rs
    printf 'candidate lock\n' > bridge/Cargo.lock
    : > "$TEST_ROOT/retry.log"
    retry 1 > "$TEST_ROOT/second-retry.out" 2>&1
    REMOTE="$($GIT_BIN --git-dir="$TEST_ROOT/remote.git" rev-parse refs/heads/upgrade/fsearch-v0.3.0-abcdefabcdef)"
    [[ "$($GIT_BIN --git-dir="$TEST_ROOT/remote.git" show "$REMOTE:bridge/Cargo.lock")" == 'candidate lock' ]] \
        || { echo 'Retry did not update the remote lock' >&2; exit 1; }
    [[ "$($GIT_BIN --git-dir="$TEST_ROOT/remote.git" show "$REMOTE:Sources/compat.swift")" == 'compatibility fix checked on main' ]] \
        || { echo 'Retry lost the checked compatibility fix' >&2; exit 1; }
    "$GIT_BIN" merge-base --is-ancestor "$FIRST" "$REMOTE"
    grep -q 'gh pr edit 7 ' "$TEST_ROOT/retry.log"
    grep -q 'gh pr ready 7' "$TEST_ROOT/retry.log"
    retry 1 > "$TEST_ROOT/unchanged-retry.out" 2>&1
    [[ "$($GIT_BIN rev-parse HEAD)" == "$REMOTE" ]]
)
echo 'Failed draft retry repairs remote lock and refreshes PR without rewriting history: passed'

echo 'Controlled open-upgrade-pr scenarios: passed'
