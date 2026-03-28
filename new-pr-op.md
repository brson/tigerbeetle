# Big changes and several important discoveries since last patch so I'll resummarize.

The reason this patch grew so much is because I found multiple new
logic bugs - almost every time somebody touches this code it introduces a bug,
myself included, no exaggeration - and decided to push the types
and code structure as far as I can to make future maintenance errors less likely.

This patch fixes multiple parallel-concurrent logic bugs in tb_client,
while fully restructuring context.zig using types to improve comprehension
and structurally prevent future errors. Thoroughly documented.

Most patches here are about introducing a state machine
that encapsulates the logical phases of tb_client's I/O usage,
and making it read more like straight-line code
that doesn't require difficult non-local reasoning to understand.

Many are about sorting out the semantics of the post-eviction shutdown sequence,
which has previously been subject to data races,
and which currently has awkward behavior.
I have captured and documented the current behavior,
and also provided a reverted commit that enables the behavior I think is preferable.

It fully removes the complex io cancel_all abstraction,
replacing it with explicit connection termination and completion waiting.

**It also enables the windows rust client CI.
If it continues to be green, the rust client should be ready to release.**

Note that this includes a big unfortunate change to the Rust API,
described below re the eviction sequence.

Most of the intermediate commits are created by Claude,
refactoring steps under my direction and design.
The final few commits are scrutinized and beautified to my expert human preference.




## The tb_client state machine

The io_thread function is rewritten as a state machine
with four phases: registering, running, disconnecting, settled.
Each phase carries only its own data in a tagged union,
so fields only exist during the phases that use them.
Phase-specific methods live in their variant namespaces,
structurally preventing access to wrong-phase state.

The flow reads top-down: running handles ticks and requests;
on eviction or stop signal, it cancels inflight/pending/submitted packets
and enters disconnecting; disconnecting waits for IO to settle
then deinits the client; settled waits for the stop signal then exits.

It's a big refactor so I've left the invdividual steps
to help in review, but for understanding the
overall code flow I suggest reading the full PR diff of context.zig.




## The eviction shutdown sequence

When the server evicts a client, it removes the session and replies
with an eviction message instead of the normal result.
On the client side, the eviction callback fires once during run_for_ns.
It nulls the context pointer (rejecting new submissions with ClientInvalid),
sets eviction_reason, and yields back to the main loop.
The main loop sees eviction_reason, enters the disconnecting phase
(which cancels inflight, pending, and submitted packets with the eviction error),
waits for connection IO to settle, deinits the client, then enters settled.
Since deinit checks the context pointer (already null),
it returns ClientInvalid without calling signal.stop().
The IO thread self-stops the signal in the settled phase and exits on its own.

The prior code had multiple concurrency bugs around eviction:

4. **Data races described in PR #3373:**
   After eviction, the IO thread writes and client threads read
   multiple values (eviction_reason, context pointer) without synchronization.
   The original fix in #3373 was to keep the IO thread running
   and short-circuiting packets with eviction errors instead of shutting down.
   Rafael's prior pr #3485 fixed all or most of these as well.
   Difficult to write tests for because of server-side eviction semantics
   not directly related to this patch.

2. **IO thread leak on eviction**
   After eviction, the context pointer is nulled by the eviction callback,
   so ClientInterface.deinit returns ClientInvalid
   without ever calling signal.stop().
   The IO thread spins in the settled phase forever.
   Fix: the settled phase self-stops the signal when evicted.
   Introduced by #3485.
   Difficult to verify because of timing and causality issues.

3. **Windows shutdown crash**
   The rust client test suite previously caused windows CI to crash.
   It no longer crashes.
   I don't know the reason, but I'm hopeful the strong typing here has
   sussed out some mis-sequenced I/O.


### Behavioral change from PR #3485

While reworking this PR I discovered that the prior PR #3485
I reviewed and approved introduced two changes to io_thread behavior:

Most critically, it changed the client such that
after the initial eviction, subsequent requests and the destructor
return ClientInvalid errors.
AIUI this was thought to be the behavior on main at the time
and the PR was only capturing it in test cases;
but that was not the case.
This change requires the Rust API to change to expose ClientInvalid.

It also introduced the IO thread leak described in bug #2 above:
after eviction the context pointer is null,
so deinit returns ClientInvalid before reaching vtable_deinit_fn,
which means thread.join() never runs.
The IO thread spins in the settled phase forever.
This didn't manifest because most language bindings ignore
the dtor result.

How each binding handles post-eviction deinit:

- **C**: tb_client_deinit returns TB_CLIENT_INVALID status. Caller decides.
- **Java**: zig-side client_deinit silently catches the error.
  On submit, ClientInvalid throws ClientClosedException to Java.
  But on deinit the error is swallowed, so thread leaks silently.
- **Go**: Close() discards the return status with `_`. Thread leaks silently.
- **C#/.NET**: NativeClient.Dispose() discards the return status. Thread leaks silently.
- **Node**: binding.deinit() called, status not checked. Thread leaks silently.
- **Python**: tb_client_deinit called via ctypes, return ignored. Thread leaks silently.
- **Rust**: close() spawns a thread that calls tb_client_deinit
  and returns Future<Result<(), ClientClosed>>. Post-eviction this
  resolves to Err(ClientClosed).


### The "don't early-shutdown" alternative (reverted)

The "tb_client: Don't early-shutdown on eviction" commit and its successor
are a paired commit/revert
demonstrating the eviction behavior I think is preferable:
after eviction, the IO thread keeps running
and subsequent submissions receive the eviction reason as their packet status,
rather than failing with ClientInvalid at the submit call site.

This is the behavior implied by the server,
which continually evicts,
and the behavior that is simplest to model and reason about.
It allows the Rust API to not expose the ClientInvalid state.


## cancel_all removal

The old shutdown path relied on io.cancel_all to force-complete pending IO.
This is a gnarly platform-specific operation
and was never implemented on Windows (the windows client crashed on shutdown).

This patch removes cancel_all entirely.
Instead, shutdown terminates exactly the open MessageBus connections
(via message_bus.terminate_all) then waits for IO to settle naturally.
This is simpler, portable, and correct.


## io.yield

Added `io.yield()` to linux, darwin, and windows IO.
Calling `yield()` inside an IO callback requests early return from `run_for_ns`,
returning control to the io_thread main loop
without waiting for the full tick timeout.

This exists so that state transitions can all be encoded directly
into the main event loop. Without it the state transitions would either:
be in the event loop but penalized by the run_for_ns tick latency,
hidden inside callbacks.

It itself comes with a footgun though:
After a callback calls `yield()`,
`run_for_ns` may dispatch additional callbacks before returning.
This means multiple callbacks within the same phase can fire
between the yield call and the actual return to the loop.
Yield only eliminates latency; it does not cut off observation of further events
within the same state machine phase.
It's documented.
