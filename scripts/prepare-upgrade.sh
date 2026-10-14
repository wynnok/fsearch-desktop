#!/bin/bash
# T24: turn an "update_available" upstream check into a reviewable upgrade
# candidate. Updates the dependency pin, lock record and embedded version,
# reuses the verified check/build entry points, evaluates temporary patches and
# writes an audit report. It never merges, tags, or publishes anything.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/build-environment.sh"
ROOT="${FSEARCH_UPGRADE_ROOT:-$PROJECT_ROOT}"
CARGO_TOML="${FSEARCH_PIN_CARGO_TOML:-$ROOT/bridge/Cargo.toml}"
CARGO_LOCK="${FSEARCH_PIN_CARGO_LOCK:-$ROOT/bridge/Cargo.lock}"
LIBRARY="${FSEARCH_PIN_LIBRARY:-$ROOT/bridge/src/lib.rs}"
PATCHES="${FSEARCH_UPGRADE_PATCHES:-$ROOT/bridge/upstream-patches.json}"

CHECK_RESULT=""
OUTPUT_DIR=""
usage() {
    cat >&2 <<'EOF'
Usage: scripts/prepare-upgrade.sh --check-result PATH [--output-dir DIR]

Reads a scripts/check-upstream-release.sh JSON result. On update_available it
rewrites the upstream pin, refreshes the lock, runs the pin check and
compatibility entry points, evaluates temporary patches and writes report.md.
EOF
    exit 2
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-result) [[ $# -ge 2 ]] || usage; CHECK_RESULT="$2"; shift 2 ;;
        --output-dir) [[ $# -ge 2 ]] || usage; OUTPUT_DIR="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[[ -n "$CHECK_RESULT" && -f "$CHECK_RESULT" ]] || usage
command -v jq >/dev/null 2>&1 || { echo 'jq is unavailable' >&2; exit 1; }
for file in "$CARGO_TOML" "$CARGO_LOCK" "$LIBRARY" "$PATCHES"; do
    [[ -f "$file" ]] || { echo "Missing upgrade input: $file" >&2; exit 1; }
done

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/.build/upgrade}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/report.md"
RESULT_JSON="$OUTPUT_DIR/result.json"
export FSEARCH_PIN_CARGO_TOML="$CARGO_TOML"
export FSEARCH_PIN_CARGO_LOCK="$CARGO_LOCK"
export FSEARCH_PIN_LIBRARY="$LIBRARY"

status="$(jq -r '.status // empty' "$CHECK_RESULT")"
[[ -n "$status" ]] || { echo 'Upstream check result is missing status' >&2; exit 1; }
current_version="$(jq -r '.current.version // empty' "$CHECK_RESULT")"
current_commit="$(jq -r '.current.commit // empty' "$CHECK_RESULT")"

write_noop_report() {
    {
        printf '# Upstream upgrade candidate\n\n'
        printf 'Outcome: no-op\n\n'
        printf 'The upstream check status is `%s`; no dependency change is proposed.\n\n' "$status"
        printf -- '- Current pin: `%s` (`%s`)\n' "${current_version:-unknown}" "${current_commit:-unknown}"
        if [[ "$status" == error ]]; then
            printf '\nThe check reported an error; the current pin is retained and the job is retried on the next run.\n'
        fi
    } > "$REPORT"
    jq -n \
        --arg outcome no-op \
        --arg status "$status" \
        --arg cv "${current_version:-unknown}" \
        --arg cc "${current_commit:-unknown}" \
        '{outcome: $outcome, status: $status, branch: null,
          current: {version: $cv, commit: $cc}, candidate: null}' > "$RESULT_JSON"
    cat "$REPORT"
}

if [[ "$status" != update_available ]]; then
    write_noop_report
    exit 0
fi

candidate_version="$(jq -r '.candidate.version // empty' "$CHECK_RESULT")"
candidate_tag="$(jq -r '.candidate.tag // empty' "$CHECK_RESULT")"
candidate_commit="$(jq -r '.candidate.commit // empty' "$CHECK_RESULT")"
candidate_release="$(jq -r '.candidate.release_url // empty' "$CHECK_RESULT")"
[[ "$candidate_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid candidate version: $candidate_version" >&2; exit 1; }
[[ "$candidate_tag" == "v$candidate_version" ]] || { echo "Candidate tag does not match version: $candidate_tag" >&2; exit 1; }
[[ "$candidate_commit" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid candidate commit: $candidate_commit" >&2; exit 1; }

BRANCH="upgrade/fsearch-v${candidate_version}-${candidate_commit:0:12}"
LOG_DIR="$OUTPUT_DIR/logs"
mkdir -p "$LOG_DIR"

patch_count="$(jq '.patches | length' "$PATCHES")"
if [[ "$patch_count" -gt 0 ]]; then
    for index in $(seq 0 $((patch_count - 1))); do
        jq -e --argjson i "$index" \
            '.patches[$i] | (.source | type == "string" and length > 0) and
             (.removeWhen | type == "string" and length > 0) and
             (.tests | type == "array" and length > 0)' \
            "$PATCHES" >/dev/null 2>&1 \
            || { echo "Temporary patch #$index is missing source, tests or removeWhen" >&2; exit 1; }
    done
fi

# Rewrite the pinned dependency, lock record and embedded upstream version.
perl -0pi -e 's/(fsearch = \{ git = "[^"]*", rev = ")[0-9a-f]{40}(")/${1}'"$candidate_commit"'${2}/' "$CARGO_TOML"
perl -0pi -e 's/const UPSTREAM_VERSION: &str = "[^"]*";/const UPSTREAM_VERSION: &str = "'"$candidate_version"' \/ '"$candidate_commit"'";/' "$LIBRARY"

pin_status=failed
build_status=not-run
regression_status=not-run
lock_status=failed

if [[ -n "${FSEARCH_UPGRADE_LOCK_COMMAND:-}" ]]; then
    "$FSEARCH_UPGRADE_LOCK_COMMAND" > "$LOG_DIR/lock-refresh.log" 2>&1 && lock_status=passed
else
    cargo update --manifest-path "$CARGO_TOML" -p fsearch > "$LOG_DIR/lock-refresh.log" 2>&1 && lock_status=passed
fi

if [[ "$lock_status" == passed ]]; then
    if bash "$PROJECT_ROOT/scripts/check-upstream-pin.sh" > "$LOG_DIR/pin-check.log" 2>&1; then
        pin_status=passed
    fi
fi

if [[ "$pin_status" == passed ]]; then
    if [[ -n "${FSEARCH_UPGRADE_COMPAT_COMMAND:-}" ]]; then
        "$FSEARCH_UPGRADE_COMPAT_COMMAND" > "$LOG_DIR/compat.log" 2>&1 \
            && { build_status=passed; regression_status=passed; }
    else
        if { bash "$PROJECT_ROOT/scripts/dev.sh" check \
            && bash "$PROJECT_ROOT/scripts/architecture.sh" build all release; } \
            > "$LOG_DIR/build.log" 2>&1; then
            build_status=passed
        fi
        if bash "$PROJECT_ROOT/scripts/dev.sh" test > "$LOG_DIR/regression.log" 2>&1; then
            regression_status=passed
        fi
    fi
fi

if [[ "$lock_status" == passed && "$pin_status" == passed \
    && "$build_status" == passed && "$regression_status" == passed ]]; then
    outcome=pr-ready
else
    outcome=failed
fi

render_patch() {
    local index="$1"
    jq -r --argjson i "$index" '
        .patches[$i] |
        "- `\(.source)`: tests \(.tests | join(", ")); remove when \(.removeWhen)"
    ' "$PATCHES"
}

{
    printf '# Upstream upgrade candidate\n\n'
    printf 'Outcome: %s\n\n' "$outcome"
    printf 'Branch (dedup key): `%s`\n\n' "$BRANCH"
    printf '## Candidate\n\n'
    printf -- '- Version: `%s` (`%s`)\n' "$candidate_version" "$candidate_tag"
    printf -- '- Commit: `%s`\n' "$candidate_commit"
    printf -- '- Release: %s\n' "${candidate_release:-unknown}"
    printf '\n## Dependency and lock\n\n'
    printf -- '- Updated `bridge/Cargo.toml`, `bridge/Cargo.lock` and the embedded `UPSTREAM_VERSION` to the candidate commit.\n'
    printf -- '- Lock refresh: %s (`logs/lock-refresh.log`)\n' "$lock_status"
    printf -- '- Pin verification: %s (`logs/pin-check.log`)\n' "$pin_status"
    printf '\n## Compatibility checks\n\n'
    printf -- '- Host build and link (`scripts/dev.sh check`): %s (`logs/build.log`)\n' "$build_status"
    printf -- '- Two-architecture build and link (`scripts/architecture.sh build all release`): %s (`logs/build.log`)\n' "$build_status"
    printf -- '- Query and snapshot regression (`scripts/dev.sh test`): %s (`logs/regression.log`)\n' "$regression_status"
    printf -- '- Index recovery compatibility: not verified by this job; recorded for maintainer review.\n'
    printf -- '- Engine resource change: not measured by this job; reuse the M1 resource evidence recorded per release.\n'
    printf '\n## Temporary patches\n\n'
    if [[ "$patch_count" -eq 0 ]]; then
        printf 'No temporary patches are registered; none are fabricated. `bridge/upstream-patches.json` is the source of truth.\n'
    else
        printf 'Evaluated %s registered temporary patch(es):\n\n' "$patch_count"
        for index in $(seq 0 $((patch_count - 1))); do render_patch "$index"; done
    fi
    printf '\n## Unverified items\n\n'
    printf -- '- Index format recovery against a real user index.\n'
    printf -- '- Real TCC / permission and resource behaviour on supported hardware.\n'
    printf -- '- Intel and macOS 13 hardware.\n'
    printf '\n## Decision\n\n'
    if [[ "$outcome" == pr-ready ]]; then
        printf 'Checks passed. A pull request may be opened for maintainer review; nothing is merged, tagged or released automatically.\n'
    else
        printf 'Checks failed. A draft pull request is opened so the candidate and logs remain reviewable; nothing is merged, tagged or released automatically.\n'
    fi
} > "$REPORT"

jq -n \
    --arg outcome "$outcome" \
    --arg status update_available \
    --arg branch "$BRANCH" \
    --arg version "$candidate_version" \
    --arg tag "$candidate_tag" \
    --arg commit "$candidate_commit" \
    --arg lock "$lock_status" \
    --arg pin "$pin_status" \
    --arg build "$build_status" \
    --arg regression "$regression_status" \
    '{outcome: $outcome, status: $status, branch: $branch,
      candidate: {version: $version, tag: $tag, commit: $commit},
      checks: {lockRefresh: $lock, pin: $pin, build: $build, regression: $regression}}' \
    > "$RESULT_JSON"

cat "$REPORT"
[[ "$outcome" == pr-ready ]]
