#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
source "$PROJECT_ROOT/scripts/dev-dmg-common.sh"
mkdir -p "$PROJECT_ROOT/.build/content-evidence"
WORKSPACE="$(mktemp -d "$PROJECT_ROOT/.build/content-evidence/run.XXXXXX")"
cleanup() { dev_dmg_stop_smoke; rm -rf "$WORKSPACE"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$WORKSPACE/fixtures"
printf 'excluded sentinel\n' > "$WORKSPACE/confinement-denied.txt"
printf '银河😀 first\r\n银河😀 second\r\n' > "$WORKSPACE/fixtures/first.txt"
printf 'unrelated\n' > "$WORKSPACE/fixtures/second.md"
printf '银河😀 unsupported\n' > "$WORKSPACE/fixtures/unsupported.pdf"
bash "$PROJECT_ROOT/scripts/dev.sh" check
LOG="$PROJECT_ROOT/.build/content-evidence/native.log"
dev_dmg_run_command "$LOG" arch "-$(uname -m)" "$PROJECT_ROOT/.build/debug/FsearchSample" --content-smoke "$WORKSPACE"
grep -q 'Native content grouping, Unicode/CRLF, open, Quick Look, no-match and diagnostic exclusion: passed' "$LOG"
mkdir -p "$PROJECT_ROOT/.build/content-evidence/native"
cp "$WORKSPACE/index/content-smoke/content-results.png" "$PROJECT_ROOT/.build/content-evidence/native/"
cp "$WORKSPACE/index/content-smoke/diagnostics.json" "$PROJECT_ROOT/.build/content-evidence/native/"
echo 'Confined real Engine native content journey: passed'
