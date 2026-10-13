#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PLUTIL=/usr/bin/plutil
CODESIGN=/usr/bin/codesign
MARKER_NAME=.fsearch-permission-workspace
EVIDENCE_DIR="${FSEARCH_PERMISSION_EVIDENCE_DIR:-$PROJECT_ROOT/.build/permission-evidence}"
PREFLIGHT="$EVIDENCE_DIR/preflight.json"
APP="${FSEARCH_PERMISSION_APP:-}"
WORKSPACE="${FSEARCH_PERMISSION_WORKSPACE:-}"
CONFIG="${FSEARCH_PERMISSION_CONFIG:-}"
PHASES=(skip grant recheck restart revoke)

mkdir -p "$EVIDENCE_DIR"

usage() {
    echo "Usage: bash scripts/permission-validation.sh {preflight|probe <phase>|report}" >&2
    exit 2
}

now() {
    /bin/date -u +"%Y-%m-%dT%H:%M:%SZ"
}

set_json_string() {
    local key="$1"
    local value="$2"
    local file="$3"
    "$PLUTIL" -insert "$key" -string "$value" "$file"
}

set_json_bool() {
    local key="$1"
    local value="$2"
    local file="$3"
    "$PLUTIL" -insert "$key" -bool "$value" "$file"
}

finish_json() {
    "$PLUTIL" -convert json -r "$1"
}

json_value() {
    local key="$1"
    local file="$2"
    "$PLUTIL" -extract "$key" raw -o - "$file" 2>/dev/null || true
}

require_permission_environment() {
    if [[ "${FSEARCH_PERMISSION_ENV:-}" != "dedicated" ]]; then
        echo "FSEARCH_PERMISSION_ENV=dedicated is required" >&2
        return 1
    fi
    if [[ -z "$WORKSPACE" || "$WORKSPACE" != /* || ! -d "$WORKSPACE" ]]; then
        echo "FSEARCH_PERMISSION_WORKSPACE must be an existing absolute directory" >&2
        return 1
    fi
    if [[ ! -f "$WORKSPACE/$MARKER_NAME" ]]; then
        echo "Permission workspace must contain $MARKER_NAME" >&2
        return 1
    fi
}

write_preflight() {
    local gate="$1"
    local reason="$2"
    local dedicated="$3"
    local marker="$4"
    local app_exists="$5"
    local codesign_verified="$6"
    local developer_id="$7"
    local authority="$8"
    local team_identifier="$9"

    "$PLUTIL" -create xml1 "$PREFLIGHT"
    set_json_string gate "$gate" "$PREFLIGHT"
    set_json_string timestamp "$(now)" "$PREFLIGHT"
    set_json_string reason "$reason" "$PREFLIGHT"
    set_json_bool dedicatedEnvironment "$dedicated" "$PREFLIGHT"
    set_json_string workspace "$WORKSPACE" "$PREFLIGHT"
    set_json_bool workspaceMarkerPresent "$marker" "$PREFLIGHT"
    set_json_string app "$APP" "$PREFLIGHT"
    set_json_bool appExists "$app_exists" "$PREFLIGHT"
    set_json_bool codesignVerified "$codesign_verified" "$PREFLIGHT"
    set_json_bool developerIDApplication "$developer_id" "$PREFLIGHT"
    set_json_string signingAuthority "$authority" "$PREFLIGHT"
    set_json_string teamIdentifier "$team_identifier" "$PREFLIGHT"
    finish_json "$PREFLIGHT"
}

preflight() {
    local reason=""
    local dedicated=false
    local marker=false
    local app_exists=false
    local codesign_verified=false
    local developer_id=false
    local authority=""
    local team_identifier=""

    if [[ "${FSEARCH_PERMISSION_ENV:-}" == "dedicated" ]]; then
        dedicated=true
    else
        reason="FSEARCH_PERMISSION_ENV=dedicated is required"
    fi
    if [[ -n "$WORKSPACE" && "$WORKSPACE" == /* && -d "$WORKSPACE" && -f "$WORKSPACE/$MARKER_NAME" ]]; then
        marker=true
    else
        reason="${reason:+$reason; }dedicated workspace marker is missing"
    fi
    if [[ -n "$APP" && "$APP" == /* && -d "$APP" && -x "$APP/Contents/MacOS/FsearchSample" ]]; then
        app_exists=true
        if "$CODESIGN" --verify --deep --strict "$APP" >/dev/null 2>&1; then
            codesign_verified=true
        else
            reason="${reason:+$reason; }codesign --verify failed"
        fi
        if "$CODESIGN" -dv --verbose=4 "$APP" > "$EVIDENCE_DIR/signature.txt" 2>&1; then
            authority="$(sed -n 's/^Authority=//p' "$EVIDENCE_DIR/signature.txt" | head -n 1)"
            team_identifier="$(sed -n 's/^TeamIdentifier=//p' "$EVIDENCE_DIR/signature.txt" | head -n 1)"
        fi
        if [[ "$authority" == "Developer ID Application:"* ]]; then
            developer_id=true
        else
            reason="${reason:+$reason; }actual .app is not Developer ID Application signed"
        fi
    else
        reason="${reason:+$reason; }FSEARCH_PERMISSION_APP must point to a signed .app"
    fi

    if [[ "$dedicated" == true && "$marker" == true && "$app_exists" == true \
          && "$codesign_verified" == true && "$developer_id" == true ]]; then
        write_preflight ready "" "$dedicated" "$marker" "$app_exists" "$codesign_verified" \
            "$developer_id" "$authority" "$team_identifier"
        echo "Permission validation preflight passed"
    else
        write_preflight unverified "$reason" "$dedicated" "$marker" "$app_exists" \
            "$codesign_verified" "$developer_id" "$authority" "$team_identifier"
        echo "Permission validation gate remains unverified: $reason" >&2
        return 1
    fi
}

probe() {
    local phase="${1:-}"
    local known_phase=false
    for candidate in "${PHASES[@]}"; do
        if [[ "$phase" == "$candidate" ]]; then known_phase=true; fi
    done
    if [[ "$known_phase" != true ]]; then usage; fi
    if [[ ! -f "$PREFLIGHT" || "$(json_value gate "$PREFLIGHT")" != "ready" ]]; then
        echo "Run a passing preflight before probing" >&2
        return 1
    fi
    require_permission_environment
    if [[ -z "$APP" || ! -x "$APP/Contents/MacOS/FsearchSample" ]]; then
        echo "FSEARCH_PERMISSION_APP does not contain a runnable FsearchSample" >&2
        return 1
    fi
    if [[ -z "$CONFIG" || "$CONFIG" != /* || ! -f "$CONFIG" ]]; then
        echo "FSEARCH_PERMISSION_CONFIG must be an existing absolute JSON file" >&2
        return 1
    fi

    local executable="$APP/Contents/MacOS/FsearchSample"
    local output="$EVIDENCE_DIR/$phase.probe.json"
    local execution="$EVIDENCE_DIR/$phase.execution.json"
    local command_display
    command_display="env FSEARCH_PERMISSION_ENV=dedicated FSEARCH_PERMISSION_WORKSPACE=$(printf '%q' "$WORKSPACE") $(printf '%q' "$executable") --permission-probe $(printf '%q' "$phase") $(printf '%q' "$CONFIG") $(printf '%q' "$output")"

    set +e
    env FSEARCH_PERMISSION_ENV=dedicated FSEARCH_PERMISSION_WORKSPACE="$WORKSPACE" \
        "$executable" --permission-probe "$phase" "$CONFIG" "$output"
    local exit_code=$?
    set -e

    "$PLUTIL" -create xml1 "$execution"
    set_json_string phase "$phase" "$execution"
    set_json_string timestamp "$(now)" "$execution"
    set_json_string command "$command_display" "$execution"
    set_json_string executable "$executable" "$execution"
    set_json_string config "$CONFIG" "$execution"
    set_json_string output "$output" "$execution"
    "$PLUTIL" -insert exitCode -integer "$exit_code" "$execution"
    finish_json "$execution"
    if [[ "$exit_code" -ne 0 ]]; then
        echo "Permission probe $phase failed with exit code $exit_code" >&2
        return "$exit_code"
    fi
    if [[ ! -f "$output" ]]; then
        echo "Permission probe $phase exited successfully without evidence" >&2
        return 1
    fi
    echo "Permission probe $phase completed"
}

report() {
    local reasons=""
    local phase_summary=""
    local all_passed=true
    if [[ ! -f "$PREFLIGHT" || "$(json_value gate "$PREFLIGHT")" != "ready" \
          || "$(json_value dedicatedEnvironment "$PREFLIGHT")" != "true" \
          || "$(json_value workspaceMarkerPresent "$PREFLIGHT")" != "true" \
          || "$(json_value codesignVerified "$PREFLIGHT")" != "true" \
          || "$(json_value developerIDApplication "$PREFLIGHT")" != "true" ]]; then
        all_passed=false
        reasons="signature or dedicated-environment preflight is not ready"
    fi
    for phase in "${PHASES[@]}"; do
        local evidence="$EVIDENCE_DIR/$phase.probe.json"
        local execution="$EVIDENCE_DIR/$phase.execution.json"
        local passed=false
        if [[ -f "$execution" && "$(json_value exitCode "$execution")" == "0" \
              && -f "$evidence" && "$(json_value phase "$evidence")" == "$phase" \
              && "$(json_value assessment.passed "$evidence")" == "true" \
              && "$(json_value iCloud.configured "$evidence")" == "true" \
              && "$(json_value iCloud.materialization "$evidence")" == "notMaterialized" ]]; then
            passed=true
        else
            all_passed=false
            reasons="${reasons:+$reasons; }$phase evidence is missing or failed"
        fi
        phase_summary="${phase_summary:+$phase_summary,}$phase=$([[ "$passed" == true ]] && echo passed || echo failed)"
    done

    local gate=unverified
    if [[ "$all_passed" == true ]]; then gate=verified; fi
    "$PLUTIL" -create xml1 "$EVIDENCE_DIR/report.json"
    set_json_string gate "$gate" "$EVIDENCE_DIR/report.json"
    set_json_string timestamp "$(now)" "$EVIDENCE_DIR/report.json"
    set_json_string reason "$reasons" "$EVIDENCE_DIR/report.json"
    set_json_string phases "$phase_summary" "$EVIDENCE_DIR/report.json"
    set_json_string iCloudEvidence "$([[ "$gate" == verified ]] && echo notMaterialized || echo unverified)" \
        "$EVIDENCE_DIR/report.json"
    set_json_string app "$(json_value app "$PREFLIGHT")" "$EVIDENCE_DIR/report.json"
    set_json_string signingAuthority "$(json_value signingAuthority "$PREFLIGHT")" "$EVIDENCE_DIR/report.json"
    set_json_string teamIdentifier "$(json_value teamIdentifier "$PREFLIGHT")" "$EVIDENCE_DIR/report.json"
    finish_json "$EVIDENCE_DIR/report.json"
    if [[ "$gate" != "verified" ]]; then
        echo "Permission validation gate remains unverified: $reasons" >&2
        return 1
    fi
    echo "Permission validation gate verified"
}

ACTION="${1:-}"
case "$ACTION" in
    preflight) preflight ;;
    probe) shift; probe "$@" ;;
    report) report ;;
    *) usage ;;
esac
