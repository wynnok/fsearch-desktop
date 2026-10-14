#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^v((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))-unsigned(\.(0|[1-9][0-9]*))?$ ]]; then
    echo 'Usage: unsigned-release-version.sh <vMAJOR.MINOR.PATCH-unsigned[.N]>' >&2
    exit 2
fi

printf '%s\n' "${BASH_REMATCH[1]}"
