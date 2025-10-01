#!/usr/bin/env bash
set -euo pipefail

# Script to run Signal unit tests with ThreadSanitizer (TSAN)
#
# The signal.zig file contains unit tests that exercise cross-thread signaling,
# which is exactly where TSAN has detected races.

cd "$(dirname "$0")"/../../../..

echo "Running Signal unit tests with ThreadSanitizer..."
echo ""

# Use zig build system with TSAN enabled
# Need to set both release and release_client_min
./zig/zig build test:unit \
    -Dconfig-release=0.0.1 \
    -Dconfig-release-client-min=0.0.1 \
    --verbose \
    -- --test-filter signal "$@"
