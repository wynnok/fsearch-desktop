#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
source "$PROJECT_ROOT/scripts/dev-dmg-common.sh"
APP="${1:?Usage: desktop-validation.sh <FsearchDesktop.app>}"
[[ -x "$APP/Contents/MacOS/FsearchSample" ]]
[[ "$(plutil -extract CFBundleName raw -o - "$APP/Contents/Info.plist")" == FsearchDesktop ]]
[[ "$(plutil -extract CFBundleDisplayName raw -o - "$APP/Contents/Info.plist")" == FsearchDesktop ]]
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")" == dev.fsearch.desktop ]]
OUTPUT="$PROJECT_ROOT/.build/desktop-evidence"
mkdir -p "$OUTPUT"
WORKSPACE="$(mktemp -d "$OUTPUT/run.XXXXXX")"
cleanup() { dev_dmg_stop_smoke; rm -rf "$WORKSPACE"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$WORKSPACE/fixtures"
printf 'desktop-content-proof\n' > "$WORKSPACE/fixtures/desktop-proof.txt"
dev_dmg_run_command "$OUTPUT/desktop.log" arch "-$(uname -m)" "$APP/Contents/MacOS/FsearchSample" --desktop-smoke "$WORKSPACE"
grep -q 'Desktop startup, name search, text content search, permission probe and live changes: passed' "$OUTPUT/desktop.log"
ruby -rjson - "$WORKSPACE/desktop-status.json" <<'RUBY'
status = JSON.parse(File.read(ARGV[0]))
raise 'Not a ready desktop Engine' unless status['mode'] == 'engine' && status['ready'] && status['owner']
%w[fullDiskAccess fullDiskAccessAtStartup].each do |key|
  raise "Missing permission probe: #{key}" unless [true, false].include?(status[key])
end
puts "Desktop engine permission probe: #{status['fullDiskAccess'] ? 'granted' : 'restricted'}"
RUBY
cp "$WORKSPACE/desktop-status.json" "$WORKSPACE/desktop-search.png" "$OUTPUT/"
echo 'Packaged desktop startup/name/content/live-change journey: passed'
