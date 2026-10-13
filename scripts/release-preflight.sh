#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
[[ $# == 2 ]] || { echo 'Usage: release-preflight.sh <vMAJOR.MINOR.PATCH> <approval.json>' >&2; exit 2; }
TAG="$1"
APPROVAL="$2"
[[ -s "$APPROVAL" ]] || { echo 'Missing release approval; T27/T28 gates remain closed.' >&2; exit 1; }
COMMIT="$(git rev-parse HEAD)"
ruby -rjson - "$TAG" "$COMMIT" "$APPROVAL" <<'RUBY'
begin
  tag, commit, path = ARGV
  raise unless tag.match?(/\Av\d+\.\d+\.\d+\z/)
  record = JSON.parse(File.read(path))
  raise unless record['schemaVersion'] == 1 && record['tag'] == tag && record['sourceCommit'] == commit
  raise unless record['approved'] == true && record['defaultMode'] == 'engine'
  %w[t27 t28 intel macos13 tcc cleanInstall upstreamUpgrade ciDownload].each do |gate|
    evidence = record.fetch('gates').fetch(gate)
    raise unless evidence['result'] == 'passed' && evidence['sourceCommit'] == commit
    raise unless evidence['url'].is_a?(String) && evidence['url'].match?(/\Ahttps:\/\/github\.com\/wynnok\/fsearch-desktop\/(?:actions\/runs\/\d+|issues\/\d+|pull\/\d+)(?:[#\/].*)?\z/)
  end
rescue StandardError
  warn 'Release approval invalid, stale, or incomplete; no build/sign/publish is authorized.'
  exit 1
end
puts 'Release preflight: approved for this exact tag/commit; maintainer evidence attestation required.'
RUBY
