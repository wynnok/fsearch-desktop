#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
select_architecture "$(uname -m)"
build_rust
invalidate_swift_link .build/swift-linked-rust
swift build "${SWIFT_OPTIONS[@]}"
BIN_PATH="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
mkdir -p "$PROJECT_ROOT/.build/engine-validation" "$PROJECT_ROOT/.build/engine-evidence"
WORKSPACE="$(mktemp -d "$PROJECT_ROOT/.build/engine-validation/run-XXXXXX")"
OUTPUT="$PROJECT_ROOT/.build/engine-evidence"
OWNER_PID=""
NATIVE_PID=""
cleanup() {
    if [[ -n "$OWNER_PID" ]]; then kill "$OWNER_PID" 2>/dev/null || true; wait "$OWNER_PID" 2>/dev/null || true; fi
    if [[ -n "$NATIVE_PID" ]]; then kill "$NATIVE_PID" 2>/dev/null || true; wait "$NATIVE_PID" 2>/dev/null || true; fi
    # Only this run's mktemp fixture/index is temporary; never a user/CLI index.
    rm -rf "$WORKSPACE"
}
trap cleanup EXIT
mkdir -p "$WORKSPACE/fixtures"
printf 'fixture\n' > "$WORKSPACE/fixtures/engine-proof.txt"
printf 'must be unreadable\n' > "$WORKSPACE/confinement-denied.txt"
"$BIN_PATH/FsearchEngineCheck" "$WORKSPACE" first > "$OUTPUT/first.log" 2>&1
"$BIN_PATH/FsearchEngineCheck" "$WORKSPACE" recover > "$OUTPUT/recover.log" 2>&1
"$BIN_PATH/FsearchEngineCheck" "$WORKSPACE" owner > "$OUTPUT/owner.log" 2>&1 &
OWNER_PID=$!
for ((i=0; i<200; i++)); do
    if [[ -f "$WORKSPACE/index/owner-ready" ]]; then break; fi
    kill -0 "$OWNER_PID"
    sleep 0.1
done
[[ -f "$WORKSPACE/index/owner-ready" ]]
"$BIN_PATH/FsearchEngineCheck" "$WORKSPACE" follower > "$OUTPUT/follower.log" 2>&1
kill "$OWNER_PID"
wait "$OWNER_PID" 2>/dev/null || true
OWNER_PID=""
"$BIN_PATH/FsearchSample" --engine-smoke "$WORKSPACE" > "$OUTPUT/native.log" 2>&1 &
NATIVE_PID=$!
for ((i=0; i<1200; i++)); do
    kill -0 "$NATIVE_PID" 2>/dev/null || break
    ps -axo pid=,ppid= | awk -v root="$NATIVE_PID" '
        { parent[$1] = $2 }
        END {
            for (pid in parent) {
                ancestor = pid
                while (ancestor > 1 && ancestor != root && ancestor in parent) ancestor = parent[ancestor]
                if (ancestor == root) print pid
            }
        }
    ' >> "$WORKSPACE/native-pids"
    sleep 0.1
done
if kill -0 "$NATIVE_PID" 2>/dev/null; then
    echo 'Native Engine/Command-Q validation did not finish within 120 seconds' >&2
    exit 1
fi
wait "$NATIVE_PID"
NATIVE_PID=""
grep -q 'Native Engine Command-Q dispatch' "$OUTPUT/native.log" || {
    echo 'Native smoke did not exercise Command-Q' >&2
    exit 1
}
while read -r pid; do
    if kill -0 "$pid" 2>/dev/null; then
        echo "Application process or descendant survived Command-Q: $pid" >&2
        exit 1
    fi
done < <(sort -nu "$WORKSPACE/native-pids")
"$BIN_PATH/FsearchEngineCheck" "$WORKSPACE" recover > "$OUTPUT/after-quit.log" 2>&1
printf 'Command-Q: application and descendants exited; index lock released and restart passed\n'
cp "$WORKSPACE/index/engine-query.png" "$WORKSPACE/index/engine-reopened.png" "$OUTPUT/"
cat "$OUTPUT/first.log" "$OUTPUT/recover.log" "$OUTPUT/follower.log" "$OUTPUT/native.log" "$OUTPUT/after-quit.log"
printf 'All confined Engine lifecycle checks passed; evidence: %s\n' "$OUTPUT"
