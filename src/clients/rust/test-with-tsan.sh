#!/usr/bin/env bash
set -euo pipefail

# Script to run Rust client tests with ThreadSanitizer (TSAN)
#
# ThreadSanitizer detects data races at runtime by instrumenting memory accesses.
# This requires both the Rust code and the linked tb_client library to be built with TSAN.
#
# Note: TSAN is an unstable feature requiring nightly Rust.

cd "$(dirname "$0")"

# Detect target triple
TARGET="x86_64-unknown-linux-gnu"

echo "Running Rust client tests with ThreadSanitizer..."
echo "Target: $TARGET"
echo ""
echo "Note: TSAN adds ~5-15x slowdown and may report false positives for"
echo "      unsupported synchronization primitives."
echo ""

# Export flags for both rustc and rustdoc
export RUSTFLAGS="-Zsanitizer=thread"
export RUSTDOCFLAGS="-Zsanitizer=thread"

# Run tests with nightly, rebuilding std with TSAN instrumentation
cargo +nightly test \
    -Zbuild-std \
    --target "$TARGET" \
    "$@" 2>&1
