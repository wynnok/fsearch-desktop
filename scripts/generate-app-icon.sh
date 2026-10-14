#!/bin/bash
# Regenerate the packaged macOS application icon from the committed master artwork.
# Assembles the ICNS container directly so the build does not depend on the
# macOS `iconutil` helper, which is unreliable on some host/toolchain versions.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$PROJECT_ROOT/Resources/AppIcon-source.png}"
OUTPUT="${2:-$PROJECT_ROOT/Resources/AppIcon.icns}"

[[ -f "$SOURCE" ]] || { echo "Missing icon source: $SOURCE" >&2; exit 1; }
command -v sips >/dev/null 2>&1 || { echo 'sips is unavailable' >&2; exit 1; }
command -v xxd >/dev/null 2>&1 || { echo 'xxd is unavailable' >&2; exit 1; }

mkdir -p "$PROJECT_ROOT/.build"
WORK="$(mktemp -d "$PROJECT_ROOT/.build/app-icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Square master downscaled from whatever resolution the designer supplied.
MASTER="$WORK/master-1024.png"
sips -s format png "$SOURCE" --resampleHeightWidth 1024 1024 --out "$MASTER" >/dev/null

render() {
    local pixels="$1"
    sips -s format png "$MASTER" --resampleHeightWidth "$pixels" "$pixels" \
        --out "$WORK/$pixels.png" >/dev/null
}
for pixels in 16 32 64 128 256 512 1024; do render "$pixels"; done

BODY="$WORK/body"
: > "$BODY"
add_chunk() {
    local type="$1" file="$2"
    local size length
    size="$(stat -f%z "$file")"
    length=$((size + 8))
    printf '%s' "$type" >> "$BODY"
    printf '%08x' "$length" | xxd -r -p >> "$BODY"
    cat "$file" >> "$BODY"
}

# Standard ICNS PNG entries: icp4/5/6 are the 1x small sizes, ic07-ic10 the
# 1x ladder through 1024, and ic11-ic14 the @2x retinas.
add_chunk icp4 "$WORK/16.png"
add_chunk icp5 "$WORK/32.png"
add_chunk icp6 "$WORK/64.png"
add_chunk ic07 "$WORK/128.png"
add_chunk ic08 "$WORK/256.png"
add_chunk ic09 "$WORK/512.png"
add_chunk ic10 "$WORK/1024.png"
add_chunk ic11 "$WORK/32.png"
add_chunk ic12 "$WORK/64.png"
add_chunk ic13 "$WORK/256.png"
add_chunk ic14 "$WORK/512.png"

TOTAL=$((8 + $(stat -f%z "$BODY")))
mkdir -p "$(dirname "$OUTPUT")"
{
    printf 'icns'
    printf '%08x' "$TOTAL" | xxd -r -p
    cat "$BODY"
} > "$OUTPUT"
printf 'Wrote %s\n' "$OUTPUT"
