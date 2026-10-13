#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$PROJECT_ROOT/scripts/check-upstream-release.sh"
FIXTURES="$PROJECT_ROOT/scripts/tests/fixtures"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/fsearch-upstream-check-tests.XXXXXX")"
trap 'rm -rf "$WORKSPACE"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

if [[ ! -f "$CHECK" ]]; then
    fail "missing $CHECK"
fi

test_no_update() {
    local output="$WORKSPACE/no-update.json"
    bash "$CHECK" \
        --releases-file "$FIXTURES/releases-current.json" \
        --tags-file "$FIXTURES/tags-current.json" > "$output"

    jq -e '
        .status == "current" and
        .current.version == "0.2.1" and
        .current.commit == "88e63fdf850cf7749deae8198b187accd21f8ba5" and
        .candidate.version == "0.2.1" and
        .candidate.commit == "88e63fdf850cf7749deae8198b187accd21f8ba5" and
        .candidate.tag == "v0.2.1"
    ' "$output" > /dev/null || fail "no-update result did not preserve the current formal release"
}

test_new_candidate() {
    local output="$WORKSPACE/new-candidate.json"
    bash "$CHECK" \
        --releases-file "$FIXTURES/releases-new.json" \
        --tags-file "$FIXTURES/tags-new.json" > "$output"

    jq -e '
        .status == "update_available" and
        .current.version == "0.2.1" and
        .candidate.version == "0.3.0" and
        .candidate.tag == "v0.3.0" and
        .candidate.commit == "1111111111111111111111111111111111111111" and
        .candidate.release_url == "https://github.com/noahdunnagan/fsearch/releases/tag/v0.3.0"
    ' "$output" > /dev/null || fail "new candidate did not select the highest formal release"
}

test_filters_non_formal_releases() {
    local output="$WORKSPACE/prerelease-filter.json"
    bash "$CHECK" \
        --releases-file "$FIXTURES/releases-prerelease.json" \
        --tags-file "$FIXTURES/tags-prerelease.json" > "$output"

    jq -e '
        .status == "update_available" and
        .candidate.version == "0.3.0" and
        .candidate.tag == "v0.3.0" and
        .candidate.commit == "1111111111111111111111111111111111111111"
    ' "$output" > /dev/null || fail "draft, prerelease, or rolling main was selected"
}

test_repeated_run_is_stable() {
    local first="$WORKSPACE/repeated-first.json"
    local second="$WORKSPACE/repeated-second.json"
    local options=(
        --releases-file "$FIXTURES/releases-new.json"
        --tags-file "$FIXTURES/tags-new.json"
    )

    bash "$CHECK" "${options[@]}" > "$first"
    bash "$CHECK" "${options[@]}" > "$second"

    cmp -s "$first" "$second" || fail "repeated run produced different results"
}

run_expected_error() {
    local kind="$1"
    shift
    local output="$WORKSPACE/error-$kind.json"

    set +e
    bash "$CHECK" --output "$output" "$@" > /dev/null 2> "$WORKSPACE/error-$kind.stderr"
    local status=$?
    set -e

    [[ "$status" -eq 1 ]] || fail "$kind failure returned status $status instead of 1"
    jq -e --arg kind "$kind" '
        .status == "error" and
        .current.version == "0.2.1" and
        .current.commit == "88e63fdf850cf7749deae8198b187accd21f8ba5" and
        .candidate == null and
        .error.kind == $kind and
        (.error.message | length) > 0
    ' "$output" > /dev/null || fail "$kind failure did not preserve the current pin"
}

test_network_failure() {
    run_expected_error network \
        --api-base "http://127.0.0.1:1" \
        --request-timeout 1
}

test_api_failure() {
    run_expected_error api \
        --releases-file "$FIXTURES/releases-invalid.json" \
        --tags-file "$FIXTURES/tags-current.json"
}

test_traceable_outputs() {
    local output="$WORKSPACE/traceable.json"
    local summary="$WORKSPACE/traceable.md"
    local run_url="https://github.com/wynnok/fsearch-desktop/actions/runs/123"

    bash "$CHECK" \
        --releases-file "$FIXTURES/releases-prerelease.json" \
        --tags-file "$FIXTURES/tags-prerelease.json" \
        --output "$output" \
        --summary "$summary" \
        --run-url "$run_url" > /dev/null

    jq -e --arg run_url "$run_url" '
        .run_url == $run_url and
        .selection.policy == "highest non-draft, non-prerelease vX.Y.Z release tag" and
        .selection.excluded_releases == [
            {tag: "v0.5.0", reason: "draft"},
            {tag: "v0.4.0", reason: "prerelease"},
            {tag: "main", reason: "non-semver-tag"}
        ]
    ' "$output" > /dev/null || fail "traceable output omitted selection evidence"
    grep -Fq "CI run: $run_url" "$summary" || fail "summary omitted the CI run URL"
}

test_no_update
test_new_candidate
test_filters_non_formal_releases
test_repeated_run_is_stable
test_network_failure
test_api_failure
test_traceable_outputs

printf 'PASS: upstream release check controlled tests\n'
