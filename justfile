# TigerBeetle Wine Testing Justfile
#
# Build and run TigerBeetle tests for Windows using Wine

# Wine 64-bit executable path
wine64 := "/usr/lib/wine/wine64"

# Zig compiler path (can be overridden with ZIG env var)
ZIG := env_var_or_default("ZIG", "./zig/zig")

# Default recipe - show available commands
default:
    @just --list

# Build Windows test binaries
build-win:
    {{ZIG}} build test:unit:build -Dtarget=x86_64-windows

# Build native Linux test binaries
build:
    {{ZIG}} build test:unit:build

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
    {{ZIG}} build test:unit

# Run smoke tests (native Linux)
test-smoke:
    {{ZIG}} build test:unit -- smoke

# Clean build artifacts
clean:
    rm -rf zig-out .zig-cache

# Show Wine version
wine-version:
    {{wine64}} --version

# Configure Wine to not show GUI debugger on crashes
wine-disable-debugger:
    @echo "Disabling Wine GUI debugger..."
    {{wine64}} reg add 'HKEY_CURRENT_USER\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f
    {{wine64}} reg add 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug' /v Debugger /t REG_SZ /d 'false' /f
    @echo "Wine debugger disabled. Crashes will terminate immediately without GUI."

# Configure Wine to show GUI debugger on crashes
wine-enable-debugger:
    @echo "Enabling Wine GUI debugger..."
    {{wine64}} reg add 'HKEY_CURRENT_USER\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 1 /f
    {{wine64}} reg delete 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug' /v Debugger /f || true
    @echo "Wine debugger enabled. Crashes will show the visual debugger."

# Configure Wine to print automatic backtraces on crash (no GUI)
wine-enable-auto-backtrace:
    @echo "Enabling Wine automatic backtrace on crash..."
    {{wine64}} reg add 'HKEY_CURRENT_USER\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f
    {{wine64}} reg add 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug' /v Debugger /t REG_SZ /d 'winedbg --auto %ld %ld' /f
    {{wine64}} reg add 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug' /v Auto /t REG_SZ /d '1' /f
    @echo "Wine auto-backtrace enabled. Crashes will print backtrace to console."

# Configure Wine to disable automatic backtraces (same as wine-disable-debugger)
wine-disable-auto-backtrace:
    @echo "Disabling Wine automatic backtrace..."
    {{wine64}} reg add 'HKEY_CURRENT_USER\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f
    {{wine64}} reg add 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug' /v Debugger /t REG_SZ /d 'false' /f
    @echo "Wine auto-backtrace disabled. Crashes will terminate immediately."

# Configure Wine to generate crash dumps
wine-enable-dumps:
    @echo "Enabling Wine crash dumps..."
    {{wine64}} reg add 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps' /v DumpFolder /t REG_SZ /d 'Z:\tmp' /f
    {{wine64}} reg add 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps' /v DumpType /t REG_DWORD /d 2 /f
    {{wine64}} reg add 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps' /v DumpCount /t REG_DWORD /d 10 /f
    @echo "Wine crash dumps enabled. Dumps will be saved to /tmp"

# Configure Wine to not generate crash dumps
wine-disable-dumps:
    @echo "Disabling Wine crash dumps..."
    {{wine64}} reg delete 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps' /f || true
    @echo "Wine crash dumps disabled."

# Build TigerBeetle binary for Windows
build-tigerbeetle-win:
    {{ZIG}} build -Dtarget=x86_64-windows

# Run TigerBeetle under Wine (requires build-tigerbeetle-win first)
run-win *args:
    {{wine64}} zig-out/bin/tigerbeetle.exe {{args}}

# Build tb_client library for Windows
build-tb-client-win:
    bash -c '{{ZIG}} build clients:rust -Dtarget=x86_64-windows -Drelease=false 2>&1 | tee -a build-tb-client-win.log; exit ${PIPESTATUS[0]}'
    @# MinGW linker expects .a format, so create a copy of the .lib file
    cp src/clients/rust/assets/lib/x86_64-windows/tb_client.lib src/clients/rust/assets/lib/x86_64-windows/libtb_client.a

# Build Rust client for Windows
build-rust-win: build-tb-client-win
    cd src/clients/rust && cargo build --target x86_64-pc-windows-gnu --all

# Build Rust tests for Windows
build-rust-test-win: build-tb-client-win
    cd src/clients/rust && cargo test --target x86_64-pc-windows-gnu --no-run --all

# Run Rust tests under Wine (includes integration tests with external server)
test-rust-win: build-rust-test-win
    @# Run unit tests (don't need server)
    {{wine64}} src/clients/rust/target/x86_64-pc-windows-gnu/debug/deps/tigerbeetle-*.exe
    @# Run integration tests using external server on port 3001
    @# Start server first with: ./tigerbeetle start --addresses=127.0.0.1:3001 <dbfile>
    RUST_BACKTRACE=1 TIGERBEETLE_SERVER_PORT=3001 {{wine64}} src/clients/rust/target/x86_64-pc-windows-gnu/debug/deps/tests-*.exe --test-threads=1 concurrent_requests multithread

# Run Rust Wine tests in a loop until failure (for finding crashes)
test-rust-win-loop:
    #!/usr/bin/env bash
    i=0
    while just test-rust-win; do
        i=$((i+1))
        echo "=== Pass $i ==="
    done
    echo "Failed after $i passes"

# Run Rust multithread test under gdb for debugging crashes
test-rust-win-gdb: build-rust-test-win
    @echo "Running multithread test under gdb..."
    @echo "Wine will generate many signals - these are normal"
    RUST_BACKTRACE=1 TIGERBEETLE_SERVER_PORT=3001 gdb -batch \
        -ex 'handle SIGSEGV nostop noprint pass' \
        -ex 'handle SIGILL nostop noprint pass' \
        -ex 'handle SIGUSR1 nostop noprint pass' \
        -ex 'handle SIGUSR2 nostop noprint pass' \
        -ex 'set pagination off' \
        -ex 'run' \
        -ex 'echo \n=== BACKTRACE ===\n' \
        -ex 'thread apply all bt' \
        -ex 'echo \n=== REGISTERS ===\n' \
        -ex 'info registers' \
        -ex 'quit' \
        --args {{wine64}} src/clients/rust/target/x86_64-pc-windows-gnu/debug/deps/tests-*.exe --test-threads=1 multithread

# Record Rust multithread test under rr for replay debugging
test-rust-win-rr-record: build-rust-test-win
    @echo "Recording multithread test with rr..."
    @echo "Run 'just test-rust-win-rr-replay' after crash to debug the recording"
    RUST_BACKTRACE=1 TIGERBEETLE_SERVER_PORT=3001 rr record {{wine64}} src/clients/rust/target/x86_64-pc-windows-gnu/debug/deps/tests-*.exe --test-threads=1 multithread

# Replay the last rr recording with debugger
test-rust-win-rr-replay:
    @echo "Replaying last rr recording..."
    @echo "Use 'c' to continue to crash, then 'bt' for backtrace"
    rr replay

# Build Java client for Windows
build-java-win:
    {{ZIG}} build clients:java -Dtarget=x86_64-windows

# Run Java tests (uses Linux JVM, tests Java code + verifies Windows DLL builds)
test-java:
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 {{ZIG}} build ci -- java
