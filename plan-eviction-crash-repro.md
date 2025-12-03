we are still trying to reproduce a client eviction crash

we're adding context_test, trying to write a stress test that hits the crash

run

zig/zig build test:integration -Drelease -Dtest-streaming=true -- "eviction" 2>&1 | cat

to run the tests.

we have a previously-working test written in rust in the brson/tbclient-thread-back branch,
commit 6089206b46cf7ec689fa348cd36b49c1013db2c6

triggering the crash is non-deterministic and typically requires a stress loop.

you keep writing multithreaded eviction-then-shutdown context_test tests until you can reproduce the crash