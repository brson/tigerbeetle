// Integration test for context.zig eviction handling.
// Tests the thread coordination between user threads and IO thread during eviction.
// This duplicates the Rust client_eviction_crash test.

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const tb_client = @import("../tb_client.zig");
const TmpTigerBeetle = @import("../../../testing/tmp_tigerbeetle.zig");

const tigerbeetle_exe: []const u8 = @import("test_options").tigerbeetle_exe;

const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;

// Notifies the main thread when all pending requests are completed.
const Completion = struct {
    pending: usize,
    mutex: Mutex = .{},
    cond: Condition = .{},

    pub fn complete(self: *Completion) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        assert(self.pending > 0);
        self.pending -= 1;
        self.cond.signal();
    }

    pub fn wait_pending(self: *Completion) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.pending > 0)
            self.cond.wait(&self.mutex);
    }
};

// Request context for capturing callback status.
const RequestContext = struct {
    completion: *Completion,
    packet: tb_client.Packet,
    status: ?tb_client.PacketStatus = null,

    pub fn on_complete(
        _: usize,
        tb_packet: *tb_client.Packet,
        _: u64,
        _: ?[*]const u8,
        _: u32,
    ) callconv(.c) void {
        const self: *RequestContext = @ptrCast(@alignCast(tb_packet.*.user_data.?));
        self.status = tb_packet.*.status;
        self.completion.complete();
    }
};

// Barrier for thread synchronization.
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

// Per-thread state for concurrent submission test.
const ThreadState = struct {
    client: *tb_client.ClientInterface,
    barrier: *Barrier,
    completion: Completion,
    request: RequestContext,
};

fn thread_fn(state: *ThreadState) void {
    // Initialize request context.
    state.request = .{
        .completion = &state.completion,
        .packet = undefined,
        .status = null,
    };

    const packet = &state.request.packet;
    packet.operation = @intFromEnum(tb_client.Operation.lookup_transfers);
    packet.user_data = &state.request;
    packet.data = null;
    packet.data_size = 0;
    packet.user_tag = 0;
    packet.status = .ok;

    // Wait for all threads to be ready.
    state.barrier.wait();

    // Submit request after eviction was triggered.
    state.client.submit(packet) catch |err| {
        // If client already shut down, that's expected.
        assert(err == error.ClientInvalid);
        state.completion.complete();
        return;
    };

    // Wait for callback.
    state.completion.wait_pending();
}

test "context: eviction with concurrent submissions" {
    // 1. Start real server.
    var tmp_tb = try TmpTigerBeetle.init(testing.allocator, .{
        .development = true,
        .prebuilt = tigerbeetle_exe,
    });
    defer tmp_tb.deinit(testing.allocator);

    // 2. Connect real client.
    var client: tb_client.ClientInterface = undefined;
    try tb_client.init(
        testing.allocator,
        &client,
        0, // cluster_id
        tmp_tb.port_str,
        0, // context
        RequestContext.on_complete,
    );
    errdefer client.deinit() catch {};

    // 3. Baseline request - verify client works.
    {
        var completion = Completion{ .pending = 1 };
        var request = RequestContext{
            .completion = &completion,
            .packet = undefined,
            .status = null,
        };

        const packet = &request.packet;
        packet.operation = @intFromEnum(tb_client.Operation.lookup_transfers);
        packet.user_data = &request;
        packet.data = null;
        packet.data_size = 0;
        packet.user_tag = 0;
        packet.status = .ok;

        try client.submit(packet);
        completion.wait_pending();

        // Baseline lookup should succeed with ok status.
        try testing.expectEqual(tb_client.PacketStatus.ok, request.status.?);
    }

    // 4. Trigger eviction.
    try client.trigger_eviction_for_testing();

    // 5. Spawn threads with barrier synchronization.
    const num_threads = 8;
    var barrier = Barrier{ .counter = std.atomic.Value(usize).init(0), .target = num_threads };

    var thread_states: [num_threads]ThreadState = undefined;
    var threads: [num_threads]std.Thread = undefined;

    for (&thread_states, &threads) |*state, *t| {
        state.* = .{
            .client = &client,
            .barrier = &barrier,
            .completion = .{ .pending = 1 },
            .request = undefined,
        };
        t.* = try std.Thread.spawn(.{}, thread_fn, .{state});
    }

    // 6. Join all threads.
    for (threads) |t| {
        t.join();
    }

    // 7. Verify all requests returned ClientEvicted status.
    for (&thread_states) |*state| {
        if (state.request.status) |status| {
            try testing.expectEqual(tb_client.PacketStatus.client_evicted, status);
        }
        // If status is null, the submit returned ClientInvalid (also acceptable).
    }

    // 8. Cleanup.
    try client.deinit();
}
