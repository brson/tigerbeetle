# TigerBeetle Windows/Wine Crash Debug Notes

## Current Status

Successfully reproduced the crash and identified the trigger conditions. The crash location is narrowed down but **do not have a definitive backtrace yet**.

**Quick Reproduction**:
```bash
RUST_BACKTRACE=1 TIGERBEETLE_SERVER_PORT=3001 /usr/lib/wine/wine64 \
  src/clients/rust/target/x86_64-pc-windows-gnu/debug/deps/tests-*.exe \
  --test-threads=1 concurrent_requests multithread
```

## What We Know For Sure

### 1. Reproduction is Reliable
- Command: `just test-rust-win-loop`
- **Updated finding**: Crash is NOT specific to multithread test
- Crash observed in: `close` test, `multithread` test (both when run after other tests)
- Tests pass when run in isolation, crash when run as part of full suite
- Crash appears to be triggered by accumulated state from running multiple tests

**Original hypothesis** (concurrent_requests → multithread):
- `concurrent_requests` alone: PASS
- `multithread` alone: PASS
- `concurrent_requests` + `multithread`: Sometimes crashes

**Observation from full test run**:
- Running all 22 tests crashes more reliably than just 2 tests
- Crash location varies (seen in `close`, `multithread`)
- Suggests state accumulation or resource exhaustion pattern

### 2. What These Tests Do

**concurrent_requests** (tests.rs:575):
- Creates single client instance
- Issues 10 account creation requests without awaiting (creates pending futures)
- Then awaits all 10 responses
- Tests concurrent pending requests on single thread

**multithread** (tests.rs:515):
- Creates single client wrapped in Arc (shared across threads)
- Spawns 16 threads
- Each thread makes 1000 sequential account creation requests
- Uses barrier to synchronize thread start
- Tests multithreaded concurrent requests

**Why This Matters**:
The crash occurs when multithreaded concurrency (`multithread`) is added to a client that previously handled concurrent pending operations (`concurrent_requests`). This suggests:
- `concurrent_requests` leaves the client or I/O system in a state with lingering operations or state
- `multithread` then exercises that state from multiple threads simultaneously
- The combination triggers the race condition in the Signal state machine

### 3. Error Information
```
thread 340 panic: reached unreachable code
Unable to dump stack trace: InvalidDebugDirectory
wine: Unhandled exception 0x80000003 in thread 154 at address 00000001400C515E
```

### 4. Build Setup That Works
```bash
# Build with debug symbols
./zig/zig build clients:c -Dtarget=x86_64-windows -Drelease=false

# Copy to Rust client (produces 11MB lib vs 1MB release)
cp -f src/clients/c/lib/x86_64-windows/* src/clients/rust/assets/lib/x86_64-windows/

# Create mingw-compatible symlink
cd src/clients/rust/assets/lib/x86_64-windows
ln -sf tb_client.lib libtb_client.a
```

## Analysis

### ~~Likely Crash Location~~ DISPROVEN: signal.zig:146-149

**UPDATE (Oct 31)**: Hypothesis about signal.zig:146 has been **DISPROVEN** through debug logging.

**Original hypothesis** (now disproven):
- Crash at `src/clients/c/tb_client/signal.zig:146-149`
- Based on error message "reached unreachable code" and high thread concurrency
- Found these unreachable statements about race conditions:

```zig
fn on_event(completion: *IO.Completion) void {
    // ... CAS from .notified to .running/.shutdown ...
    const state = self.event_state.cmpxchgStrong(
        .notified,
        if (listening) .running else .shutdown,
        .release,
        .acquire,
    ) orelse {
        // Success path
        if (listening) {
            (self.on_signal_fn)(self);
            self.wait();
        }
        return;
    };

    // Error path - CAS failed, state is NOT .notified
    switch (state) {
        .running => unreachable,   // Line 146 - "Multiple racing calls to on_signal()"
        .waiting => unreachable,   // Line 147 - "on_signal() called without transitioning"
        .notified => unreachable,  // Line 148 - "Not possible due to CAS semantics"
        .shutdown => unreachable,  // Line 149 - "Shutdown is a final state"
    }
}
```

**Why we tested this location**:
- Comment says "Multiple racing calls to on_signal()"
- Matched our multithread test scenario
- State machine assumes only one thread can execute `on_event` at a time
- Windows I/O completion might violate this assumption

**How it was disproven**:
1. Added `std.debug.print()` statements before each unreachable at lines 146-149
2. Added debug print at function entry: `std.debug.print("=== on_event CALLED ===\n", .{})`
3. Verified debug prints work (function entry prints appear in output)
4. Crash still occurs but **none of the unreachable-specific debug prints appear**
5. Conclusion: The crash is NOT in signal.zig:146-149 or lines 118/125

This definitively proves the crash is elsewhere in the codebase.

### Actual Crash Location: UNKNOWN

The crash is at some other `unreachable` statement in the tb_client codebase. Other files with unreachable:
- `src/clients/c/tb_client/context.zig` - Multiple unreachable statements
- `src/clients/c/tb_client/packet.zig:131` - In `assert_phase()` for `.complete` phase
- `src/clients/c/tb_client_exports.zig:275` - In logging code
- `src/clients/c/test.zig` - Test code (unlikely)

**Most likely candidates**:
1. **context.zig** - Client context state management, high complexity
2. **packet.zig:131** - Packet phase assertions, related to request lifecycle

The crash address `0x00000001400C515E` could help identify the exact location if mapped against symbols.

## What We Don't Have

### No Clean Backtrace
Attempted to get backtrace with debug symbols but failed:
- Built with `-Drelease=false` (11MB lib with DWARF symbols)
- Wine debugger loads modules but reports `InvalidDebugDirectory`
- DWARF-4 format in PE binary not fully compatible with Wine's debugger
- Crash address `0x00000001400C515E` present but no symbol resolution

### Crash Address Analysis Not Done
- Have crash address: `0x00000001400C515E`
- Could potentially map this against debug symbols manually
- Would need to examine PE/DWARF sections or use other tools

## Next Steps to Find Crash Location

### 1. Systematic Debug Logging (In Progress)
Add `std.debug.print()` statements before ALL unreachable statements in tb_client:

**Completed**:
- ✓ signal.zig:146-149 (disproven)
- ✓ signal.zig:118, 125 (disproven)
- ✓ packet.zig:131 (added but not yet triggered)

**TODO**:
- [ ] context.zig - All unreachable statements (likely location)
- [ ] tb_client_exports.zig:275

Example pattern:
```zig
.some_case => {
    std.debug.print("=== CRASH_FILE_LINE: description ===\n", .{});
    unreachable;
},
```

### 2. Try Alternative Debug Approaches
- Run on actual Windows with WinDbg
- Use `winedbg --gdb` to attach gdb
- Check if Zig can emit CodeView debug info instead of DWARF
- Use Wine's crash dumps with offline analysis

### 3. Map Crash Address (Manual Analysis)
- Extract symbol information from debug lib using objdump/llvm tools
- Disassemble the region around `0x00000001400C515E`
- Map crash address to source location
- This would give definitive answer without trial-and-error logging

## Debug Logging Experiments (Oct 31)

### Methodology
1. Added `std.debug.print()` before suspected unreachable statements
2. Rebuilt library: `rm -rf .zig-cache zig-out && ./zig/zig build clients:c -Dtarget=x86_64-windows`
3. Copied to Rust: `cp -f ./src/clients/c/lib/x86_64-windows/* ./src/clients/rust/assets/lib/x86_64-windows/`
4. Rebuilt Rust tests: `cargo clean --target x86_64-pc-windows-gnu && cargo test --no-run --all`
5. Ran tests and observed output

### Results
**What works**: Debug prints successfully appear in Wine output (verified with function entry logging)

**What we tested**:
- signal.zig:146-149 (on_event CAS failure branches) - NOT the crash location
- signal.zig:118, 125 (wait() swap failure branches) - NOT the crash location
- packet.zig:131 (assert_phase .complete) - Added logging but not yet triggered

**Key finding**: The panic message "reached unreachable code" appears but our custom debug prints do NOT, proving the crash is elsewhere.

### Current state of code
- signal.zig has debug print at entry to `on_event()` function
- signal.zig:146-149 replaced unreachable with @panic + debug prints (but never triggered)
- signal.zig:118, 125 replaced unreachable with @panic + debug prints (but never triggered)
- packet.zig:131 has debug print added (not yet triggered in crash)

## Test Case Details

The failing test: `src/clients/rust/tests/tests.rs:515`

```rust
#[test]
fn multithread() -> anyhow::Result<()> {
    let client = test_client()?;
    let client = Arc::new(client);

    let num_threads = 16;
    let num_requests = 1_000;

    let barrier = Arc::new(Barrier::new(num_threads));

    // All 16 threads start simultaneously and hammer the client
    let join_handles = std::iter::repeat(()).take(num_threads).map(|_| {
        let client = client.clone();
        let barrier = barrier.clone();
        std::thread::spawn(move || -> anyhow::Result<()> {
            barrier.wait();  // Synchronize start
            block_on(async {
                for _ in 0..num_requests {
                    let results = client
                        .create_accounts(&[tb::Account {
                            id: tb::id(),
                            ledger: TEST_LEDGER,
                            code: TEST_CODE,
                            flags: tb::AccountFlags::History,
                            ..Default::default()
                        }])
                        .await?;
                    assert_eq!(results.len(), 0);
                }
                Ok(())
            })
        })
    });
    // ... collect and join ...
}
```

## Files of Interest

- `src/clients/c/tb_client/signal.zig` - Cross-thread signaling (likely crash site)
- `src/clients/c/tb_client/context.zig` - Client context with Signal usage
- `src/clients/rust/tests/tests.rs:515` - Failing test
- `src/clients/rust/build.rs` - Build script (had to work around library linking issues)

## Build Issues Encountered

1. **Missing library assets**: Had to manually copy from `src/clients/c/lib/` to `src/clients/rust/assets/lib/`
2. **Mingw linker compatibility**: Windows `.lib` file not recognized by mingw, needed symlink as `libtb_client.a`
3. **Debug symbols format**: DWARF-4 in PE binary causes Wine debugger issues

## Environment

- Platform: Linux (Fedora)
- Wine version: 9.0
- Cross-compilation: x86_64-pc-windows-gnu via mingw
- Zig version: 0.14.1
- Test server: Native Linux TigerBeetle, connected from Wine test client
