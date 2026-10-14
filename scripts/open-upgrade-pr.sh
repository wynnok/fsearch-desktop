#!/bin/bash
# T24: commit the prepared upgrade candidate and open (or reuse) its pull
# request. The same candidate branch is refreshed with fast-forward commits;
# a failing candidate is kept as a draft. git and gh are
# overridable so the decision path can be exercised without network access.
set -euo pipefail
GIT="${FSEARCH_UPGRADE_GIT:-git}"
GH="${FSEARCH_UPGRADE_GH:-gh}"

BRANCH=""
BASE=""
TITLE=""
BODY=""
MESSAGE=""
DRAFT=0
usage() {
    cat >&2 <<'EOF'
Usage: scripts/open-upgrade-pr.sh --branch NAME --base BRANCH --title TEXT \
    --body-file PATH --message TEXT [--draft]
EOF
    exit 2
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch) [[ $# -ge 2 ]] || usage; BRANCH="$2"; shift 2 ;;
        --base) [[ $# -ge 2 ]] || usage; BASE="$2"; shift 2 ;;
        --title) [[ $# -ge 2 ]] || usage; TITLE="$2"; shift 2 ;;
        --body-file) [[ $# -ge 2 ]] || usage; BODY="$2"; shift 2 ;;
        --message) [[ $# -ge 2 ]] || usage; MESSAGE="$2"; shift 2 ;;
        --draft) DRAFT=1; shift ;;
        *) usage ;;
    esac
done
[[ -n "$BRANCH" && -n "$BASE" && -n "$TITLE" && -n "$MESSAGE" && -f "$BODY" ]] || usage

PIN_FILES=(bridge/Cargo.toml bridge/Cargo.lock bridge/src/lib.rs)
# Refuse to include unrelated staged changes in the candidate commit.
"$GIT" diff --cached --quiet -- . ':!bridge/Cargo.toml' ':!bridge/Cargo.lock' ':!bridge/src/lib.rs'
mkdir -p .build/upgrade-pr
CANDIDATE="$(mktemp -d "$PWD/.build/upgrade-pr/run.XXXXXX")"
for file in "${PIN_FILES[@]}"; do cp "$file" "$CANDIDATE/$(basename "$file")"; done
restored=0
cleanup() {
    if [[ "$restored" == 0 ]]; then
        for file in "${PIN_FILES[@]}"; do cp "$CANDIDATE/$(basename "$file")" "$file"; done
    fi
    rm -rf "$CANDIDATE"
}
trap cleanup EXIT

# A failed remote lookup must fail the job, rather than look like a new branch.
remote="$("$GIT" ls-remote --heads origin "refs/heads/$BRANCH")"
CHECKED_BASE="$("$GIT" rev-parse HEAD)"
"$GIT" restore --source=HEAD --staged --worktree -- "${PIN_FILES[@]}"
if [[ -n "$remote" ]]; then
    "$GIT" fetch origin "refs/heads/$BRANCH"
    if "$GIT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
        "$GIT" checkout "$BRANCH"
        "$GIT" merge --ff-only FETCH_HEAD
    else
        "$GIT" checkout -b "$BRANCH" FETCH_HEAD
    fi
    # Include compatibility fixes from the exact baseline checked by prepare.
    # Conflicts in pin files are resolved by the saved, checked candidate below.
    if ! "$GIT" merge --no-commit --no-ff "$CHECKED_BASE"; then
        for file in $("$GIT" diff --name-only --diff-filter=U); do
            case "$file" in
                bridge/Cargo.toml|bridge/Cargo.lock|bridge/src/lib.rs) ;;
                *) echo 'Candidate merge has unrelated conflicts; do not mark PR ready.' >&2; exit 1 ;;
            esac
        done
    fi
else
    "$GIT" checkout -b "$BRANCH"
fi
for file in "${PIN_FILES[@]}"; do cp "$CANDIDATE/$(basename "$file")" "$file"; done
restored=1
"$GIT" add "${PIN_FILES[@]}"
# Never attach a passing report to a tree with untested non-pin changes.
"$GIT" diff --quiet "$CHECKED_BASE" -- . ':!bridge/Cargo.toml' ':!bridge/Cargo.lock' ':!bridge/src/lib.rs'
changed=0
if ! "$GIT" diff --cached --quiet || "$GIT" rev-parse --verify -q MERGE_HEAD >/dev/null; then
    "$GIT" config user.name 'github-actions[bot]'
    "$GIT" config user.email '41898282+github-actions[bot]@users.noreply.github.com'
    "$GIT" commit -m "$MESSAGE"
    changed=1
fi
if [[ "$changed" == 1 || -z "$remote" ]]; then
    "$GIT" push -u origin "HEAD:refs/heads/$BRANCH"
fi

existing="$("$GH" pr list --head "$BRANCH" --state open --json number,isDraft --jq '.[0] // empty')"
if [[ -n "$existing" ]]; then
    number="$(jq -er '.number' <<< "$existing")"
    is_draft="$(jq -r '.isDraft' <<< "$existing")"
    "$GH" pr edit "$number" --title "$TITLE" --body-file "$BODY"
    if [[ "$DRAFT" == 0 && "$is_draft" == true ]]; then
        "$GH" pr ready "$number"
    elif [[ "$DRAFT" == 1 && "$is_draft" == false ]]; then
        "$GH" pr ready "$number" --undo
    fi
    printf 'Reusing existing upgrade pull request #%s for %s.\n' "$number" "$BRANCH"
    exit 0
fi

create_args=(--base "$BASE" --head "$BRANCH" --title "$TITLE" --body-file "$BODY")
if [[ "$DRAFT" == 1 ]]; then
    create_args+=(--draft)
fi
"$GH" pr create "${create_args[@]}"
