run-zig:
    zig/zig build -Drelease
    zig/zig build test:integration -Dtest-streaming=true -Drelease -- eviction 2>&1 | cat

run-rust:
    zig/zig build clients:rust -Drelease
    (cd src/clients/rust && cargo test --release -- eviction --nocapture)
    
