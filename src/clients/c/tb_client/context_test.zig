// Integration test for context.zig eviction handling.
// Tests the thread coordination between user threads and IO thread during eviction.
// This duplicates the Rust client_eviction_crash test.

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const tb_client = @import("../tb_client.zig");
const TmpTigerBeetle = @import("../../../testing/tmp_tigerbeetle.zig");

const tigerbeetle_exe: []const u8 = @import("test_options").tigerbeetle_exe;

/// Synchronous blocking wrapper around tb_client for expressive tests.
const SyncClient = struct {
    client: *tb_client.ClientInterface,

    const Result = union(enum) {
        ok,
        err: tb_client.PacketStatus,
    };

    /// Blocking lookup_transfers call.
    pub fn lookup_transfers(self: *SyncClient, ids: []const u128) Result {
        var ctx = RequestCtx{};
        ctx.packet = .{
            .operation = @intFromEnum(tb_client.Operation.lookup_transfers),
            .user_data = &ctx,
            .data = @constCast(std.mem.sliceAsBytes(ids).ptr),
            .data_size = @intCast(ids.len * @sizeOf(u128)),
            .user_tag = 0,
            .status = .ok,
        };

        self.client.submit(&ctx.packet) catch |err| {
            assert(err == error.ClientInvalid);
            return .{ .err = .client_shutdown };
        };

        ctx.wait();

        return switch (ctx.status.?) {
            .ok => .ok,
            else => |status| .{ .err = status },
        };
    }

    pub fn trigger_eviction_for_testing(self: *SyncClient) !void {
        return self.client.trigger_eviction_for_testing();
    }

    pub fn deinit(self: *SyncClient) !void {
        return self.client.deinit();
    }

    const RequestCtx = struct {
        packet: tb_client.Packet = undefined,
        status: ?tb_client.PacketStatus = null,
        mutex: std.Thread.Mutex = .{},
        cond: std.Thread.Condition = .{},
        done: bool = false,

        pub fn wait(self: *RequestCtx) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            while (!self.done)
                self.cond.wait(&self.mutex);
        }

        pub fn on_complete(
            _: usize,
            packet: *tb_client.Packet,
            _: u64,
            _: ?[*]const u8,
            _: u32,
        ) callconv(.c) void {
            const self: *RequestCtx = @ptrCast(@alignCast(packet.*.user_data.?));
            self.mutex.lock();
            defer self.mutex.unlock();
            self.status = packet.*.status;
            self.done = true;
            self.cond.signal();
        }
    };
};

/// Barrier for thread synchronization.
const Barrier = struct {
    counter: std.atomic.Value(usize),
    target: usize,

    pub fn wait(self: *Barrier) void {
        _ = self.counter.fetchAdd(1, .monotonic);
        while (self.counter.load(.acquire) < self.target) {
            std.atomic.spinLoopHint();
        }
    }
};

/// Per-thread state.
const ThreadState = struct {
    client: *tb_client.ClientInterface,
    barrier: *Barrier,
    err: ?anyerror = null,
};

fn thread_fn(state: *ThreadState) void {
    var sync = SyncClient{ .client = state.client };

    // Wait for all threads to be ready.
    state.barrier.wait();

    // First lookup should succeed (empty result).
    switch (sync.lookup_transfers(&.{0})) {
        .ok => {},
        .err => |status| {
            std.debug.print("thread: first lookup failed with {}\n", .{status});
            state.err = error.UnexpectedStatus;
            return;
        },
    }

    // Trigger eviction (all threads do this, it's idempotent).
    sync.trigger_eviction_for_testing() catch |err| {
        std.debug.print("thread: trigger_eviction failed with {}\n", .{err});
        state.err = err;
        return;
    };

    // Subsequent lookups should fail with ClientEvicted.
    switch (sync.lookup_transfers(&.{0})) {
        .ok => {
            std.debug.print("thread: second lookup succeeded, expected ClientEvicted\n", .{});
            state.err = error.ExpectedEvicted;
            return;
        },
        .err => |status| {
            if (status != .client_evicted and status != .client_shutdown) {
                std.debug.print("thread: second lookup got {}, expected client_evicted\n", .{status});
                state.err = error.UnexpectedStatus;
                return;
            }
        },
    }

    switch (sync.lookup_transfers(&.{0})) {
        .ok => {
            std.debug.print("thread: third lookup succeeded, expected ClientEvicted\n", .{});
            state.err = error.ExpectedEvicted;
            return;
        },
        .err => |status| {
            if (status != .client_evicted and status != .client_shutdown) {
                std.debug.print("thread: third lookup got {}, expected client_evicted\n", .{status});
                state.err = error.UnexpectedStatus;
                return;
            }
        },
    }
}

test "context: eviction with concurrent submissions" {
    // Start real server (kept alive across all iterations).
    var tmp_tb = try TmpTigerBeetle.init(testing.allocator, .{
        .development = true,
        .prebuilt = tigerbeetle_exe,
    });
    defer tmp_tb.deinit(testing.allocator);

    // The crash is easier to reproduce with more iterations.
    // Client registration is slow, so we keep this small for CI.
    const tries = 3;
    const num_threads = 8;

    for (0..tries) |i| {
        std.debug.print("eviction crash try {}\n", .{i});

        // Connect new client each iteration.
        var client: tb_client.ClientInterface = undefined;
        try tb_client.init(
            testing.allocator,
            &client,
            0, // cluster_id
            tmp_tb.port_str,
            0, // context
            SyncClient.RequestCtx.on_complete,
        );
        errdefer client.deinit() catch {};

        // Spawn threads with barrier synchronization.
        var barrier = Barrier{ .counter = std.atomic.Value(usize).init(0), .target = num_threads };

        var thread_states: [num_threads]ThreadState = undefined;
        var threads: [num_threads]std.Thread = undefined;

        for (&thread_states, &threads) |*state, *t| {
            state.* = .{
                .client = &client,
                .barrier = &barrier,
            };
            t.* = try std.Thread.spawn(.{}, thread_fn, .{state});
        }

        // Join all threads.
        for (threads) |t| {
            t.join();
        }

        // Verify no thread errors.
        for (&thread_states) |*state| {
            if (state.err) |err| {
                return err;
            }
        }

        // Cleanup client before next iteration.
        try client.deinit();
    }
}

test "context: eviction single-thread" {
    var tmp_tb = try TmpTigerBeetle.init(testing.allocator, .{
        .development = true,
        .prebuilt = tigerbeetle_exe,
    });
    defer tmp_tb.deinit(testing.allocator);

    const tries = 10;

    for (0..tries) |i| {
        std.debug.print("eviction try {}\n", .{i});

        // Create client.
        var client: tb_client.ClientInterface = undefined;
        try tb_client.init(
            testing.allocator,
            &client,
            0,
            tmp_tb.port_str,
            0,
            SyncClient.RequestCtx.on_complete,
        );
        var sync = SyncClient{ .client = &client };

        // First lookup should succeed.
        switch (sync.lookup_transfers(&.{0})) {
            .ok => {},
            .err => |status| {
                std.debug.print("first lookup failed: {}\n", .{status});
                return error.UnexpectedStatus;
            },
        }

        // Trigger eviction.
        try sync.trigger_eviction_for_testing();

        // Subsequent lookups should fail with client_evicted.
        switch (sync.lookup_transfers(&.{0})) {
            .ok => {
                std.debug.print("second lookup succeeded, expected evicted\n", .{});
                return error.ExpectedEvicted;
            },
            .err => |status| {
                if (status != .client_evicted and status != .client_shutdown) {
                    std.debug.print("second lookup: {}, expected evicted\n", .{status});
                    return error.UnexpectedStatus;
                }
            },
        }

        switch (sync.lookup_transfers(&.{0})) {
            .ok => {
                std.debug.print("third lookup succeeded, expected evicted\n", .{});
                return error.ExpectedEvicted;
            },
            .err => |status| {
                if (status != .client_evicted and status != .client_shutdown) {
                    std.debug.print("third lookup: {}, expected evicted\n", .{status});
                    return error.UnexpectedStatus;
                }
            },
        }

        try sync.deinit();
    }
}

/// Aggressive race condition test.
/// Fires off many non-blocking requests to hit the race window between
/// eviction_reason being set and signal.stop() being called.
const RaceTestState = struct {
    completions: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
};

const RaceThreadState = struct {
    client: *tb_client.ClientInterface,
    barrier: *Barrier,
    test_state: *RaceTestState,
    err: std.atomic.Value(bool),
};

const RacePacketCtx = struct {
    completions: *std.atomic.Value(u32),
    packet: tb_client.Packet,
    id: u128,
};

fn race_thread_fn(state: *RaceThreadState) void {
    // Pre-allocate packets for rapid-fire submission.
    const num_packets = 32;
    var completions = std.atomic.Value(u32).init(0);
    var contexts: [num_packets]RacePacketCtx = undefined;
    for (&contexts, 0..) |*ctx, i| {
        ctx.* = .{
            .completions = &completions,
            .packet = undefined,
            .id = i,
        };
        ctx.packet = .{
            .operation = @intFromEnum(tb_client.Operation.lookup_transfers),
            .user_data = ctx,
            .data = @ptrCast(&ctx.id),
            .data_size = @sizeOf(u128),
            .user_tag = 0,
            .status = .ok,
        };
    }

    // Wait for all threads.
    state.barrier.wait();

    // Trigger eviction - all threads do this, it's idempotent.
    state.client.trigger_eviction_for_testing() catch |err| {
        std.debug.print("trigger_eviction failed: {}\n", .{err});
        state.err.store(true, .release);
        return;
    };

    // Immediately fire off many requests without waiting.
    // The goal is to hit the race window between eviction_reason being set
    // and signal.stop() being called.
    var submitted: u32 = 0;
    for (&contexts) |*ctx| {
        state.client.submit(&ctx.packet) catch {
            // ClientInvalid is expected after shutdown - count as completed.
            _ = completions.fetchAdd(1, .monotonic);
            continue;
        };
        submitted += 1;
    }

    // Wait for all submitted packets to complete before returning.
    // This ensures stack-allocated contexts remain valid.
    while (completions.load(.acquire) < num_packets) {
        std.atomic.spinLoopHint();
    }

    // Report completions to parent.
    _ = state.test_state.completions.fetchAdd(num_packets, .release);
}

fn race_completion_callback(
    _: usize,
    packet: *tb_client.Packet,
    _: u64,
    _: ?[*]const u8,
    _: u32,
) callconv(.c) void {
    const ctx: *RacePacketCtx = @ptrCast(@alignCast(packet.user_data));
    _ = ctx.completions.fetchAdd(1, .monotonic);
}

test "context: eviction race stress" {
    var tmp_tb = try TmpTigerBeetle.init(testing.allocator, .{
        .development = true,
        .prebuilt = tigerbeetle_exe,
    });
    defer tmp_tb.deinit(testing.allocator);

    // Many iterations to increase chance of hitting the race.
    // The race window between eviction_reason being set and signal.stop() is very narrow.
    const tries = 1000;
    const num_threads = 2;

    for (0..tries) |i| {
        std.debug.print("race stress try {}\n", .{i});

        var test_state = RaceTestState{};

        var client: tb_client.ClientInterface = undefined;
        try tb_client.init(
            testing.allocator,
            &client,
            0,
            tmp_tb.port_str,
            0,
            race_completion_callback,
        );

        // Do one successful request first to ensure client is registered.
        {
            var init_completions = std.atomic.Value(u32).init(0);
            var init_ctx = RacePacketCtx{
                .completions = &init_completions,
                .packet = undefined,
                .id = 0,
            };
            init_ctx.packet = .{
                .operation = @intFromEnum(tb_client.Operation.lookup_transfers),
                .user_data = &init_ctx,
                .data = @ptrCast(&init_ctx.id),
                .data_size = @sizeOf(u128),
                .user_tag = 0,
                .status = .ok,
            };

            client.submit(&init_ctx.packet) catch |err| {
                std.debug.print("initial submit failed: {}\n", .{err});
                return error.InitFailed;
            };

            // Wait for completion.
            while (init_completions.load(.acquire) < 1) {
                std.atomic.spinLoopHint();
            }
        }

        var barrier = Barrier{ .counter = std.atomic.Value(usize).init(0), .target = num_threads };

        var thread_states: [num_threads]RaceThreadState = undefined;
        var threads: [num_threads]std.Thread = undefined;

        for (&thread_states, &threads) |*state, *t| {
            state.* = .{
                .client = &client,
                .barrier = &barrier,
                .test_state = &test_state,
                .err = std.atomic.Value(bool).init(false),
            };
            t.* = try std.Thread.spawn(.{}, race_thread_fn, .{state});
        }

        for (threads) |t| {
            t.join();
        }

        // Check for thread errors.
        for (&thread_states) |*state| {
            if (state.err.load(.acquire)) {
                return error.ThreadError;
            }
        }

        try client.deinit();
    }
}
