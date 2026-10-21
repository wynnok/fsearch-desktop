#!/bin/bash
# Shared development DMG constants and helpers. Source from project entry points.
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/build-environment.sh"
fi

DEV_DMG_APP_NAME="FsearchDesktop"
DEV_DMG_PACKAGE_STATUS="development-unnotarized"
DEV_DMG_DEFAULT_VERSION="0.2.0"
DEV_DMG_ROOT="$PROJECT_ROOT/.build/dev-dmg"
DEV_DMG_OUTPUT_DIR="$DEV_DMG_ROOT/output"
DEV_DMG_VERIFICATION_DIR="$DEV_DMG_ROOT/verification"
DEV_DMG_ARTIFACT_PREFIX="Fsearch-Desktop"
DEV_DMG_SMOKE_PID=""

dev_dmg_stop_smoke() {
    if [[ -n "$DEV_DMG_SMOKE_PID" ]]; then
        kill -TERM "$DEV_DMG_SMOKE_PID" >/dev/null 2>&1 || true
        for _ in {1..3}; do
            kill -0 "$DEV_DMG_SMOKE_PID" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$DEV_DMG_SMOKE_PID" 2>/dev/null; then
            kill -KILL "$DEV_DMG_SMOKE_PID" >/dev/null 2>&1 || true
        fi
        wait "$DEV_DMG_SMOKE_PID" >/dev/null 2>&1 || true
        DEV_DMG_SMOKE_PID=""
    fi
}

dev_dmg_run_command() {
    local log="$1" result=0
    shift
    "$@" > "$log" 2>&1 &
    DEV_DMG_SMOKE_PID=$!
    for _ in {1..90}; do
        kill -0 "$DEV_DMG_SMOKE_PID" 2>/dev/null || break
        sleep 2
    done
    if kill -0 "$DEV_DMG_SMOKE_PID" 2>/dev/null; then
        echo 'Installed application smoke timed out.' >&2
        local sample_pid="$DEV_DMG_SMOKE_PID"
        if [[ -f "$log.pid" ]]; then
            sample_pid="$(cat "$log.pid")"
        fi
        sample "$sample_pid" 1 1 -file "$log.sample.txt" >/dev/null 2>&1 || true
        dev_dmg_stop_smoke
        return 1
    fi
    wait "$DEV_DMG_SMOKE_PID" || result=$?
    DEV_DMG_SMOKE_PID=""
    return "$result"
}

dev_dmg_run_smoke() {
    local launcher="$DEV_DMG_ROOT/installed-smoke-launcher"
    mkdir -p "$DEV_DMG_ROOT"
    xcrun swiftc -parse-as-library -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" \
        "$PROJECT_ROOT/scripts/launch-installed-smoke.swift" -o "$launcher" || return 1
    dev_dmg_run_command "$4" "$launcher" "$1" "$2" "$3" "$4"
}

dev_dmg_upstream_version() {
    sed -n 's/^const UPSTREAM_VERSION: &str = "\(.*\)";$/\1/p' "$PROJECT_ROOT/bridge/src/lib.rs"
}

dev_dmg_runner_image() {
    printf '%s / %s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}"
}

dev_dmg_rust_pin() {
    printf '%s\n' "${FSEARCH_DEV_RUST_VERSION:-not set}"
}

dev_dmg_toolchain_pin_note() {
    if [[ -n "${FSEARCH_DEV_RUST_VERSION:-}" ]]; then
        printf 'Reproducibility note: Rust requested pin %s; Xcode and runner image are recorded but not fully pinned by this project.\n' \
            "$FSEARCH_DEV_RUST_VERSION"
    else
        printf 'Reproducibility note: Rust requested pin not set; Xcode and runner image are recorded but full reproducibility is not verified.\n'
    fi
}

dev_dmg_generate_third_party_notices() {
    local output="$1"
    local work_root="$DEV_DMG_ROOT/notices"
    local metadata="$work_root/cargo-metadata.json"
    local packages="$work_root/packages.tsv"
    local temporary="$work_root/THIRD-PARTY-NOTICES.tmp"
    local candidates="$work_root/license-files.txt"

    [[ -n "$output" ]] || { echo "Missing third-party notices output path" >&2; return 2; }
    mkdir -p "$work_root" "$(dirname "$output")"

    if [[ -n "${FSEARCH_DEV_CARGO_METADATA:-}" ]]; then
        [[ -f "$FSEARCH_DEV_CARGO_METADATA" ]] || {
            echo "Cargo metadata override does not exist: $FSEARCH_DEV_CARGO_METADATA" >&2
            return 1
        }
        cp "$FSEARCH_DEV_CARGO_METADATA" "$metadata"
    else
        cargo metadata --locked --format-version 1 \
            --manifest-path "$PROJECT_ROOT/bridge/Cargo.toml" > "$metadata"
    fi

    ruby -rjson - "$metadata" "$packages" <<'RUBY'
require "json"

metadata, output = ARGV
packages = JSON.parse(File.read(metadata)).fetch("packages")
third_party = packages.reject { |package| package["source"].nil? }
third_party.sort_by! { |package| [package.fetch("name"), package.fetch("version")] }

File.open(output, "w") do |file|
  third_party.each do |package|
    file.puts([
      package.fetch("name"),
      package.fetch("version"),
      package["license"] || "",
      package["source"] || "",
      package.fetch("manifest_path"),
      package["license_file"] || ""
    ].join("\t"))
  end
end
RUBY

    [[ -s "$packages" ]] || { echo "Cargo metadata contains no third-party packages" >&2; return 1; }

    {
        printf 'Third-Party Notices\n'
        printf 'Generated from bridge/Cargo.lock through cargo metadata.\n'
        printf 'The package is a development verification build, not a stable release.\n\n'
    } > "$temporary"

    while IFS=$'\t' read -r name version license pkg_source manifest_path license_file; do
        local package_dir
        package_dir="$(dirname "$manifest_path")"
        [[ -d "$package_dir" ]] || {
            echo "Cannot locate source directory for $name $version: $package_dir" >&2
            return 1
        }
        [[ -n "$license" ]] || {
            echo "Missing license expression for $name $version" >&2
            return 1
        }

        : > "$candidates"
        if [[ -n "$license_file" ]]; then
            case "$license_file" in
                /*) printf '%s\n' "$license_file" > "$candidates" ;;
                *) printf '%s/%s\n' "$package_dir" "$license_file" > "$candidates" ;;
            esac
        else
            find "$package_dir" -maxdepth 4 -type f \
                \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'UNLICENSE*' -o -iname 'NOTICE*' \) \
                -print | LC_ALL=C sort > "$candidates"
        fi

        [[ -s "$candidates" ]] || {
            echo "Cannot locate license text for $name $version ($license)" >&2
            return 1
        }

        {
            printf '%s\n' "================================================================================"
            printf '%s %s\n' "$name" "$version"
            printf 'License: %s\n' "$license"
            printf 'Source: %s\n' "$pkg_source"
            printf 'License files:\n'
        } >> "$temporary"

        while IFS= read -r license_path; do
            [[ -f "$license_path" ]] || {
                echo "Missing declared license file for $name $version: $license_path" >&2
                return 1
            }
            case "$license_path" in
                "$package_dir"/*) printf '%s\n' "- ${license_path#"$package_dir/"}" >> "$temporary" ;;
                *) printf '%s\n' "- $license_path" >> "$temporary" ;;
            esac
        done < "$candidates"

        printf '\n' >> "$temporary"
        while IFS= read -r license_path; do
            case "$license_path" in
                "$package_dir"/*) license_label="${license_path#"$package_dir/"}" ;;
                *) license_label="$license_path" ;;
            esac
            printf '%s\n' "----- $license_label -----" >> "$temporary"
            cat "$license_path" >> "$temporary"
            [[ "$(tail -c 1 "$license_path" | wc -l | tr -d ' ')" == 0 ]] && printf '\n' >> "$temporary"
            printf '\n' >> "$temporary"
        done < "$candidates"
    done < "$packages"

    mv "$temporary" "$output"
}
