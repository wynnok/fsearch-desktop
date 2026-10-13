#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"

CARGO_TOML="${FSEARCH_PIN_CARGO_TOML:-$PROJECT_ROOT/bridge/Cargo.toml}"
CARGO_LOCK="${FSEARCH_PIN_CARGO_LOCK:-$PROJECT_ROOT/bridge/Cargo.lock}"
UPSTREAM_SOURCE="${FSEARCH_PIN_LIBRARY:-$PROJECT_ROOT/bridge/src/lib.rs}"

for file in "$CARGO_TOML" "$CARGO_LOCK" "$UPSTREAM_SOURCE"; do
    [[ -f "$file" ]] || { echo "Missing upstream pin input: $file" >&2; exit 1; }
done

REPOSITORY="$(sed -n 's/^fsearch = { git = "\([^"]*\)".*rev = "\([^"]*\)".*$/\1/p' "$CARGO_TOML")"
REVISION="$(sed -n 's/^fsearch = { git = "\([^"]*\)".*rev = "\([^"]*\)".*$/\2/p' "$CARGO_TOML")"
[[ -n "$REPOSITORY" && -n "$REVISION" ]] || {
    echo "Cannot read the expected Fsearch git pin from $CARGO_TOML" >&2
    exit 1
}

LOCK_RECORD="$(awk '
    $0 == "[[package]]" { in_package = 0 }
    $0 == "name = \"fsearch\"" { in_package = 1 }
    in_package && /^version = / {
        value = $0
        sub(/^version = "/, "", value)
        sub(/"$/, "", value)
        version = value
    }
    in_package && /^source = / {
        value = $0
        sub(/^source = "/, "", value)
        sub(/"$/, "", value)
        source = value
    }
    END {
        if (version != "" && source != "") print version "\t" source
    }
' "$CARGO_LOCK")"
[[ -n "$LOCK_RECORD" ]] || { echo "Cannot find the fsearch package in $CARGO_LOCK" >&2; exit 1; }

IFS=$'\t' read -r LOCK_VERSION LOCK_SOURCE <<< "$LOCK_RECORD"
EXPECTED_SOURCE="git+${REPOSITORY}?rev=${REVISION}#${REVISION}"
[[ "$LOCK_SOURCE" == "$EXPECTED_SOURCE" ]] || {
    echo "Cargo.lock Fsearch source does not match bridge/Cargo.toml" >&2
    echo "expected: $EXPECTED_SOURCE" >&2
    echo "actual:   $LOCK_SOURCE" >&2
    exit 1
}

LIBRARY_VALUES="$(sed -n 's/^const UPSTREAM_VERSION: &str = "\([^ ]*\) \/ \([^"]*\)";$/\1\t\2/p' "$UPSTREAM_SOURCE")"
[[ -n "$LIBRARY_VALUES" ]] || {
    echo "Cannot read UPSTREAM_VERSION from $UPSTREAM_SOURCE" >&2
    exit 1
}
IFS=$'\t' read -r LIBRARY_VERSION LIBRARY_REVISION <<< "$LIBRARY_VALUES"
[[ "$LIBRARY_VERSION" == "$LOCK_VERSION" && "$LIBRARY_REVISION" == "$REVISION" ]] || {
    echo "Embedded UPSTREAM_VERSION does not match the locked Fsearch package" >&2
    echo "expected: $LOCK_VERSION / $REVISION" >&2
    echo "actual:   $LIBRARY_VERSION / $LIBRARY_REVISION" >&2
    exit 1
}

printf 'Fsearch pin verified: %s / %s (%s)\n' "$LOCK_VERSION" "$REVISION" "$REPOSITORY"
