#!/usr/bin/env bash
set -euo pipefail

# Script to run Rust client tests with Valgrind
#
# Valgrind detects memory errors, leaks, and threading issues at runtime
# without requiring special compilation flags.
#
# Note: Valgrind adds 10-50x slowdown but works with standard builds.

cd "$(dirname "$0")"

echo "Running Rust client tests with Valgrind..."
echo ""
echo "Note: Valgrind adds significant overhead (10-50x slowdown)."
echo ""

# Build tests in debug mode for better stack traces
cargo test --no-run

# Find the test binary
TEST_BINARY=$(cargo test --test tests --no-run --message-format=json 2>/dev/null | \
    jq -r 'select(.executable != null) | .executable' | \
    grep -v ' ' | head -1)

if [ -z "$TEST_BINARY" ]; then
    echo "Error: Could not find test binary"
    exit 1
fi

echo "Running: $TEST_BINARY"
echo ""

# Run with Valgrind memcheck
exec valgrind \
    --tool=memcheck \
    --leak-check=full \
    --show-leak-kinds=all \
    --track-origins=yes \
    --verbose \
    --error-exitcode=1 \
    "$TEST_BINARY" \
    "$@"
