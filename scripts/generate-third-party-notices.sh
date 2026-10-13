#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/dev-dmg-common.sh"

OUTPUT="${1:-}"
[[ -n "$OUTPUT" ]] || {
    echo "Usage: bash scripts/generate-third-party-notices.sh <output-file>" >&2
    exit 2
}

dev_dmg_generate_third_party_notices "$OUTPUT"
printf 'Generated %s\n' "$OUTPUT"
