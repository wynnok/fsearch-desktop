#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${FSEARCH_UPSTREAM_API_BASE:-https://api.github.com/repos/noahdunnagan/fsearch}"
REQUEST_TIMEOUT="${FSEARCH_UPSTREAM_REQUEST_TIMEOUT:-10}"
RELEASES_FILE=""
TAGS_FILE=""
OUTPUT_FILE=""
SUMMARY_FILE=""
RUN_URL=""

usage() {
    cat >&2 <<'EOF'
Usage: scripts/check-upstream-release.sh [options]

Options:
  --releases-file PATH    Read a controlled GitHub Releases JSON response.
  --tags-file PATH        Read a controlled GitHub Tags JSON response.
  --api-base URL          Override the GitHub API repository base URL.
  --request-timeout SEC   curl connect timeout for API requests (default: 10).
  --output PATH           Also write the JSON result to PATH.
  --summary PATH          Write a Markdown summary to PATH.
  --run-url URL           Include the CI run URL in the result.
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --releases-file)
            [[ $# -ge 2 ]] || usage
            RELEASES_FILE="$2"
            shift 2
            ;;
        --tags-file)
            [[ $# -ge 2 ]] || usage
            TAGS_FILE="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || usage
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --summary)
            [[ $# -ge 2 ]] || usage
            SUMMARY_FILE="$2"
            shift 2
            ;;
        --run-url)
            [[ $# -ge 2 ]] || usage
            RUN_URL="$2"
            shift 2
            ;;
        --api-base)
            [[ $# -ge 2 ]] || usage
            API_BASE="$2"
            shift 2
            ;;
        --request-timeout)
            [[ $# -ge 2 ]] || usage
            REQUEST_TIMEOUT="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done

[[ "$REQUEST_TIMEOUT" =~ ^[0-9]+$ ]] || usage

toml_commit="$(sed -n 's/^fsearch = .*rev = "\([0-9a-f]\{40\}\)".*$/\1/p' "$PROJECT_ROOT/bridge/Cargo.toml")"
lock_version="$(awk '
    /^\[\[package\]\]$/ { in_fsearch = 0 }
    /^name = "fsearch"$/ { in_fsearch = 1; next }
    in_fsearch && /^version = / {
        line = $0
        sub(/^version = "/, "", line)
        sub(/"$/, "", line)
        print line
        exit
    }
' "$PROJECT_ROOT/bridge/Cargo.lock")"
lock_source="$(awk '
    /^\[\[package\]\]$/ { in_fsearch = 0 }
    /^name = "fsearch"$/ { in_fsearch = 1; next }
    in_fsearch && /^source = "git\+/ { print; exit }
' "$PROJECT_ROOT/bridge/Cargo.lock")"
lock_commit="${lock_source##*rev=}"
lock_commit="${lock_commit%%#*}"

if [[ ! "$toml_commit" =~ ^[0-9a-f]{40}$ || ! "$lock_commit" =~ ^[0-9a-f]{40}$ || "$toml_commit" != "$lock_commit" ]]; then
    printf 'Current upstream pin is inconsistent between bridge/Cargo.toml and bridge/Cargo.lock\n' >&2
    exit 1
fi
[[ "$lock_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf 'Could not read the current Fsearch version from bridge/Cargo.lock\n' >&2
    exit 1
}

emit_outputs() {
    if [[ -n "$OUTPUT_FILE" ]]; then
        printf '%s\n' "$result" > "$OUTPUT_FILE"
    fi

    if [[ -n "$SUMMARY_FILE" ]]; then
        {
            case "$status" in
                current)
                    printf '## Upstream release check: current\n\n'
                    printf 'Current and latest formal release are both `v%s` (`%s`).\n' \
                        "$candidate_version" "$candidate_commit"
                    ;;
                update_available)
                    printf '## Upstream release check: update available\n\n'
                    printf 'Current: `v%s` (`%s`)\n\n' "$lock_version" "$lock_commit"
                    printf 'Candidate: `v%s` (`%s`)\n\n' "$candidate_version" "$candidate_commit"
                    printf 'Release: %s\n' "$candidate_release_url"
                    ;;
                error)
                    printf '## Upstream release check: error\n\n'
                    printf 'Current pin remains `v%s` (`%s`).\n\n' "$lock_version" "$lock_commit"
                    printf 'Error (%s): %s\n' "$error_kind" "$error_message"
                    ;;
            esac
            if [[ -n "$RUN_URL" ]]; then
                printf '\nCI run: %s\n' "$RUN_URL"
            fi
        } > "$SUMMARY_FILE"
    fi

    printf '%s\n' "$result"
}

emit_error() {
    error_kind="$1"
    error_message="$2"
    status="error"
    candidate_json="null"
    selection_json="null"
    error_json="$(jq -n --arg kind "$error_kind" --arg message "$error_message" \
        '{kind: $kind, message: $message}')"
    result="$(jq -n \
        --arg status "$status" \
        --arg current_version "$lock_version" \
        --arg current_commit "$lock_commit" \
        --argjson candidate "$candidate_json" \
        --argjson selection "$selection_json" \
        --argjson error "$error_json" \
        --arg run_url "$RUN_URL" \
        '{
            status: $status,
            current: {
                version: $current_version,
                commit: $current_commit
            },
            candidate: $candidate,
            selection: $selection,
            error: $error,
            run_url: (if $run_url == "" then null else $run_url end)
        }')"
    emit_outputs
    printf 'Upstream release check failed (%s): %s\n' "$error_kind" "$error_message" >&2
    exit 1
}

WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/fsearch-upstream-release-check.XXXXXX")"
trap 'rm -rf "$WORKSPACE"' EXIT

fetch_json() {
    local url="$1"
    local destination="$2"
    local curl_args=(
        --fail
        --silent
        --show-error
        --location
        --connect-timeout "$REQUEST_TIMEOUT"
        --max-time "$((REQUEST_TIMEOUT * 3))"
        --header "Accept: application/vnd.github+json"
        --header "X-GitHub-Api-Version: 2022-11-28"
    )
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        curl_args+=(--header "Authorization: Bearer $GITHUB_TOKEN")
    fi
    if ! curl "${curl_args[@]}" --output "$destination" "$url"; then
        emit_error network "GitHub API request failed; no candidate was selected"
    fi
}

api_base="${API_BASE%/}"
if [[ -z "$RELEASES_FILE" ]]; then
    RELEASES_FILE="$WORKSPACE/releases.json"
    fetch_json "$api_base/releases?per_page=100" "$RELEASES_FILE"
fi
if [[ -z "$TAGS_FILE" ]]; then
    TAGS_FILE="$WORKSPACE/tags.json"
    fetch_json "$api_base/tags?per_page=100" "$TAGS_FILE"
fi

jq -e 'type == "array"' "$RELEASES_FILE" > /dev/null 2>&1 \
    || emit_error api "GitHub Releases response was not a JSON array"
jq -e 'type == "array"' "$TAGS_FILE" > /dev/null 2>&1 \
    || emit_error api "GitHub Tags response was not a JSON array"
jq -e '
    all(.[];
        (type == "object") and
        ((.tag_name | type) == "string") and
        ((.draft | type) == "boolean") and
        ((.prerelease | type) == "boolean") and
        ((.html_url | type) == "string")
    )
' "$RELEASES_FILE" > /dev/null 2>&1 \
    || emit_error api "GitHub Releases response contained an invalid release object"
jq -e '
    all(.[];
        (type == "object") and
        ((.name | type) == "string") and
        ((.commit | type) == "object") and
        ((.commit.sha | type) == "string")
    )
' "$TAGS_FILE" > /dev/null 2>&1 \
    || emit_error api "GitHub Tags response contained an invalid tag object"

release_count="$(jq 'length' "$RELEASES_FILE")"
formal_release_count="$(jq '
    [
        .[]
        | select(.draft == false and .prerelease == false)
        | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    ]
    | length
' "$RELEASES_FILE")"
excluded_releases="$(jq -c '
    [
        .[]
        | {
            tag: .tag_name,
            reason: (
                if .draft then "draft"
                elif .prerelease then "prerelease"
                elif (.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$") | not) then "non-semver-tag"
                else null
                end
            )
          }
        | select(.reason != null)
    ]
' "$RELEASES_FILE")"

selected_release="$(jq -c '
    [
        .[]
        | select(.draft == false and .prerelease == false)
        | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
        | . + { version_parts: (.tag_name[1:] | split(".") | map(tonumber)) }
    ]
    | sort_by(.version_parts)
    | reverse
    | .[0] // empty
    | {
        version: (.tag_name[1:]),
        tag: .tag_name,
        releaseURL: .html_url
      }
' "$RELEASES_FILE")"

[[ -n "$selected_release" ]] || emit_error api "No formal vX.Y.Z upstream release found"

candidate_version="$(jq -r '.version' <<< "$selected_release")"
candidate_tag="$(jq -r '.tag' <<< "$selected_release")"
candidate_release_url="$(jq -r '.releaseURL' <<< "$selected_release")"
candidate_commit="$(jq -er --arg tag "$candidate_tag" '
    .[]
    | select(.name == $tag)
    | .commit.sha
    | select(test("^[0-9a-f]{40}$"))
' "$TAGS_FILE")" \
    || emit_error api "Selected release tag $candidate_tag was not resolved to a commit"

if [[ "$candidate_version" == "$lock_version" && "$candidate_commit" == "$lock_commit" ]]; then
    status="current"
else
    status="update_available"
fi

selection_json="$(jq -n \
    --arg policy "highest non-draft, non-prerelease vX.Y.Z release tag" \
    --argjson release_count "$release_count" \
    --argjson formal_release_count "$formal_release_count" \
    --arg selected_tag "$candidate_tag" \
    --argjson excluded_releases "$excluded_releases" \
    '{
        policy: $policy,
        release_count: $release_count,
        formal_release_count: $formal_release_count,
        selected_tag: $selected_tag,
        excluded_releases: $excluded_releases
    }')"
candidate_json="$(jq -n \
    --arg version "$candidate_version" \
    --arg tag "$candidate_tag" \
    --arg commit "$candidate_commit" \
    --arg release_url "$candidate_release_url" \
    '{
        version: $version,
        tag: $tag,
        commit: $commit,
        release_url: $release_url
    }')"
error_json="null"

result="$(jq -n \
    --arg status "$status" \
    --arg current_version "$lock_version" \
    --arg current_commit "$lock_commit" \
    --argjson candidate "$candidate_json" \
    --argjson selection "$selection_json" \
    --argjson error "$error_json" \
    --arg run_url "$RUN_URL" \
    '{
        status: $status,
        current: {
            version: $current_version,
            commit: $current_commit
        },
        candidate: $candidate,
        selection: $selection,
        error: $error,
        run_url: (if $run_url == "" then null else $run_url end)
    }')"

emit_outputs
