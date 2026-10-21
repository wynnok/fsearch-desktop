#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
select_architecture "$(uname -m)"

ACTION="${1:-build}"
if [[ $# -gt 0 ]]; then shift; fi
case "$ACTION" in
    resolve) cargo generate-lockfile --manifest-path bridge/Cargo.toml ;;
    build|check|test|run|ui-smoke)
        if [[ "$ACTION" == check ]]; then
            cargo check --locked --manifest-path bridge/Cargo.toml --target "$RUST_TARGET"
        fi
        build_rust
        invalidate_swift_link .build/swift-linked-rust
        case "$ACTION" in
            build|check) swift build "${SWIFT_OPTIONS[@]}" ;;
            test) swift test "${SWIFT_OPTIONS[@]}" "$@" ;;
            run) swift run "${SWIFT_OPTIONS[@]}" FsearchSample "--sample-directory=$PROJECT_ROOT/fixtures/sample" "$@" ;;
            ui-smoke) swift run "${SWIFT_OPTIONS[@]}" FsearchSample "--sample-directory=$PROJECT_ROOT/fixtures/sample" --smoke "--smoke-output=$PROJECT_ROOT/.build/native-smoke" ;;
        esac
        touch .build/swift-linked-rust
        ;;
    *) echo "Usage: bash scripts/dev.sh {resolve|build|check|test|run|ui-smoke}" >&2; exit 2 ;;
esac
