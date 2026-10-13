#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
export CARGO_HOME="$PROJECT_ROOT/.build/cargo-home"
export CARGO_TARGET_DIR="$PROJECT_ROOT/.build/rust"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/swift-module-cache"
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p "$CARGO_HOME" "$CARGO_TARGET_DIR" "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
SWIFT_OPTIONS=(--disable-sandbox --cache-path "$PROJECT_ROOT/.build/swiftpm-cache" --config-path "$PROJECT_ROOT/.build/swiftpm-config" --security-path "$PROJECT_ROOT/.build/swiftpm-security")

ACTION="${1:-build}"
if [[ $# -gt 0 ]]; then shift; fi
case "$ACTION" in
    resolve) cargo generate-lockfile --manifest-path bridge/Cargo.toml ;;
    build|check|test|run|ui-smoke)
        if [[ "$ACTION" == check ]]; then
            cargo check --locked --manifest-path bridge/Cargo.toml
        fi
        cargo build --locked --manifest-path bridge/Cargo.toml
        # SwiftPM cannot track a static library produced outside its build graph.
        if [[ ! -e .build/swift-linked-rust || .build/rust/debug/libfsearch_bridge.a -nt .build/swift-linked-rust ]]; then
            touch Sources/FsearchService/FsearchService.swift
        fi
        case "$ACTION" in
            build|check) swift build "${SWIFT_OPTIONS[@]}" ;;
            test) swift test "${SWIFT_OPTIONS[@]}" "$@" ;;
            run) swift run "${SWIFT_OPTIONS[@]}" FsearchSample "$PROJECT_ROOT/fixtures/sample" "$@" ;;
            ui-smoke) swift run "${SWIFT_OPTIONS[@]}" FsearchSample "$PROJECT_ROOT/fixtures/sample" --smoke "$PROJECT_ROOT/.build/native-smoke" ;;
        esac
        touch .build/swift-linked-rust
        ;;
    *) echo "Usage: bash scripts/dev.sh {resolve|build|check|test|run|ui-smoke}" >&2; exit 2 ;;
esac
