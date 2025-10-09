# TigerBeetle Wine Testing Justfile
#
# Build and run TigerBeetle tests for Windows using Wine

# Wine 64-bit executable path
wine64 := "/usr/lib/wine/wine64"

# Default recipe - show available commands
default:
    @just --list

# Build Windows test binaries
build-win:
    ./zig/zig build test:unit:build -Dtarget=x86_64-windows

# Build native Linux test binaries
build:
    ./zig/zig build test:unit:build

# Run stdx tests under Wine
test-stdx-win: build-win
    {{wine64}} zig-out/bin/test-stdx.exe

# Run unit tests under Wine
test-unit-win: build-win
    {{wine64}} zig-out/bin/test-unit.exe

# Run all Windows tests under Wine
test-win: test-stdx-win test-unit-win

# Run native Linux tests
test:
    ./zig/zig build test:unit

# Run smoke tests (native Linux)
test-smoke:
    ./zig/zig build test:unit -- smoke

# Clean build artifacts
clean:
    rm -rf zig-out .zig-cache

# Show Wine version
wine-version:
    {{wine64}} --version

# Build TigerBeetle binary for Windows
build-tigerbeetle-win:
    ./zig/zig build -Dtarget=x86_64-windows

# Run TigerBeetle under Wine (requires build-tigerbeetle-win first)
run-win *args:
    {{wine64}} zig-out/bin/tigerbeetle.exe {{args}}

# Build Rust client for Windows
build-rust-win:
    cd src/clients/rust && cargo build --target x86_64-pc-windows-gnu --all

# Build Rust tests for Windows
build-rust-test-win:
    cd src/clients/rust && cargo test --target x86_64-pc-windows-gnu --no-run --all

# Run Rust tests under Wine (unit tests only, integration tests need tigerbeetle server)
test-rust-win: build-rust-test-win
    {{wine64}} src/clients/rust/target/x86_64-pc-windows-gnu/debug/deps/tigerbeetle-*.exe

# Build Java client for Windows
build-java-win:
    ./zig/zig build clients:java -Dtarget=x86_64-windows

# Run Java tests (uses Linux JVM, tests Java code + verifies Windows DLL builds)
test-java:
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 ./zig/zig build ci -- java
