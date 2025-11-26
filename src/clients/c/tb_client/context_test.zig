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

    // Submit first lookup WITHOUT waiting for completion.
    // This increases the chance of having multiple in-flight/pending packets
    // when eviction is triggered, reproducing the data race crash.
    const ids = [_]u128{0};
    var ctx1 = SyncClient.RequestCtx{};
    ctx1.packet = .{
        .operation = @intFromEnum(tb_client.Operation.lookup_transfers),
        .user_data = &ctx1,
        .data = @constCast(std.mem.sliceAsBytes(&ids).ptr),
        .data_size = @intCast(ids.len * @sizeOf(u128)),
        .user_tag = 0,
        .status = .ok,
    };
    state.client.submit(&ctx1.packet) catch {}; // Fire and forget

    // Immediately trigger eviction - this races with the submission above
    // and with other threads' submissions.
    sync.trigger_eviction_for_testing() catch {};

    // Submit more lookups that should fail with ClientEvicted.
    switch (sync.lookup_transfers(&.{0})) {
        .ok => {
            std.debug.print("thread: second lookup succeeded, expected ClientEvicted\n", .{});
            state.err = error.ExpectedEvicted;
        },
        .err => |status| {
            if (status != .client_evicted and status != .client_shutdown) {
                std.debug.print("thread: second lookup got {}, expected client_evicted\n", .{status});
                state.err = error.UnexpectedStatus;
            }
        },
    }

    switch (sync.lookup_transfers(&.{0})) {
        .ok => {
            std.debug.print("thread: third lookup succeeded, expected ClientEvicted\n", .{});
            state.err = error.ExpectedEvicted;
        },
        .err => |status| {
            if (status != .client_evicted and status != .client_shutdown) {
                std.debug.print("thread: third lookup got {}, expected client_evicted\n", .{status});
                state.err = error.UnexpectedStatus;
            }
        },
    }

    // Wait for first request to complete (it may have succeeded or been cancelled).
    ctx1.wait();
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
    const tries = 1000;
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
