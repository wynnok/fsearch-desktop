#!/bin/bash
# Shared project-local caches and architecture selection. Source from an entry point.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
export CARGO_HOME="$PROJECT_ROOT/.build/cargo-home"
export CARGO_TARGET_DIR="$PROJECT_ROOT/.build/rust"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/swift-module-cache"
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p "$CARGO_HOME" "$CARGO_TARGET_DIR" "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
if [[ -f "$PROJECT_ROOT/.build/rustup-home/toolchain-version" ]]; then
    export RUSTUP_HOME="$PROJECT_ROOT/.build/rustup-home"
    RUSTUP_TOOLCHAIN="$(cat "$RUSTUP_HOME/toolchain-version")"
    export RUSTUP_TOOLCHAIN
fi
SWIFT_OPTIONS=(--disable-sandbox --cache-path "$PROJECT_ROOT/.build/swiftpm-cache" --config-path "$PROJECT_ROOT/.build/swiftpm-config" --security-path "$PROJECT_ROOT/.build/swiftpm-security")

select_architecture() {
    ARCHITECTURE="$1"
    CONFIGURATION="${2:-debug}"
    case "$ARCHITECTURE" in
        arm64) RUST_TARGET=aarch64-apple-darwin; BASELINE_CPU=apple-a7 ;;
        x86_64) RUST_TARGET=x86_64-apple-darwin; BASELINE_CPU=x86-64 ;;
        *) echo "Expected arm64 or x86_64" >&2; return 2 ;;
    esac
    case "$CONFIGURATION" in debug|release) ;; *) echo "Expected debug or release" >&2; return 2 ;; esac
    # Override dependency target-cpu=native and inherited Rust flags.
    export RUSTFLAGS="-C target-cpu=$BASELINE_CPU"
    unset CARGO_ENCODED_RUSTFLAGS
    export FSEARCH_RUST_LIBRARY_DIR="$CARGO_TARGET_DIR/$RUST_TARGET/$CONFIGURATION"
    RUST_ARCHIVE="$FSEARCH_RUST_LIBRARY_DIR/libfsearch_bridge.a"
}

build_rust() {
    local options=(--locked --manifest-path "$PROJECT_ROOT/bridge/Cargo.toml" --target "$RUST_TARGET")
    if [[ "$CONFIGURATION" == release ]]; then options+=(--release); fi
    cargo build "${options[@]}"
}

invalidate_swift_link() {
    local marker="$1"
    # SwiftPM cannot track the external Rust archive in its build graph.
    if [[ ! -e "$marker" || "$RUST_ARCHIVE" -nt "$marker" ]]; then
        touch "$PROJECT_ROOT/Sources/FsearchService/FsearchService.swift"
    fi
}
