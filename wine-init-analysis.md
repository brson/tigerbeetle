# TigerBeetle Rust Client Windows/Wine Crash Analysis

## Summary

Successfully reproduced and debugged the TigerBeetle Rust client crash on Windows/Wine.

## The Crash

- **Test**: `multithread` test crashes when running 16 threads making concurrent requests
- **Error**: `thread panic: reached unreachable code`
- **Location**: `src/clients/c/tb_client/signal.zig:146`
- **Command**: `just test-rust-win-loop`

## Root Cause

The bug is in the Signal state machine's `on_event` callback (signal.zig:129-151):

```zig
fn on_event(completion: *IO.Completion) void {
    const self: *Signal = @fieldParentPtr("completion", completion);
    const listening: bool = self.listening.load(.acquire);
    const state = self.event_state.cmpxchgStrong(
        .notified,
        if (listening) .running else .shutdown,
        .release,
        .acquire,
    ) orelse {
        if (listening) {
            (self.on_signal_fn)(self);
            self.wait();
        }
        return;
    };

    switch (state) {
        .running => unreachable, // Multiple racing calls to on_signal(). <-- CRASH HERE
        .waiting => unreachable, // on_signal() called without transitioning to a waking state.
        .notified => unreachable, // Not possible due to CAS semantics.
        .shutdown => unreachable, // Shutdown is a final state.
    }
}
```

The code expects to CAS from `.notified` to `.running`/`.shutdown`. When the CAS fails and the state is `.running`, it hits the unreachable at line 146, which means there are **multiple racing calls to the I/O event completion callback** - something the state machine considers impossible.

## Why This Happens

This appears to be a race condition in the Windows I/O completion implementation or timing that manifests under Wine with high thread concurrency. The state machine assumptions about atomicity or event ordering may not hold under Windows I/O completion semantics.

## Reproduction

### Setup

1. Build the client library with debug symbols:
   ```bash
   ./zig/zig build clients:c -Dtarget=x86_64-windows -Drelease=false
   ```

2. Copy library to Rust client assets:
   ```bash
   cp -f src/clients/c/lib/x86_64-windows/* src/clients/rust/assets/lib/x86_64-windows/
   ```

3. Create mingw-compatible symlink:
   ```bash
   cd src/clients/rust/assets/lib/x86_64-windows
   ln -sf tb_client.lib libtb_client.a
   ```

### Running the Test

The crash is intermittent but usually reproduces on the first run:

```bash
just test-rust-win-loop
```

### Crash Output

```
thread 340 panic: reached unreachable code
Unable to dump stack trace: InvalidDebugDirectory
wine: Unhandled exception 0x80000003 in thread 154 at address 00000001400C515E
```

## Files Involved

- Crash location: `src/clients/c/tb_client/signal.zig:146`
- Failing test: `src/clients/rust/tests/tests.rs:515` (multithread test)
- State machine: `src/clients/c/tb_client/signal.zig`

## Potential Fix

The fix would need to handle the `.running` state case properly instead of treating it as unreachable, likely by detecting and handling concurrent event completions gracefully. This could involve:

1. Adding proper handling for the `.running` case in the error path
2. Investigating whether Windows I/O completion can actually deliver multiple concurrent completions
3. Adding synchronization to prevent concurrent execution of `on_event` for the same Signal instance
4. Reviewing the state transitions to ensure they're correct for Windows I/O semantics

## Test Case

The failing test spawns 16 threads that all make concurrent requests through a shared client:

```rust
#[test]
fn multithread() -> anyhow::Result<()> {
    let client = test_client()?;
    let client = Arc::new(client);

    let num_threads = 16;
    let num_requests = 1_000;

    let barrier = Arc::new(Barrier::new(num_threads));

    let join_handles = std::iter::repeat(()).take(num_threads).map(|_| {
        let client = client.clone();
        let barrier = barrier.clone();
        std::thread::spawn(move || -> anyhow::Result<()> {
            barrier.wait();
            block_on(async {
                for _ in 0..num_requests {
                    let results = client
                        .create_accounts(&[tb::Account { /* ... */ }])
                        .await?;
                    assert_eq!(results.len(), 0);
                }
                Ok(())
            })
        })
    });
    // ... join threads ...
}
```
