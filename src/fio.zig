const std = @import("std");
const os = std.os;
const assert = std.debug.assert;
const log = std.log.scoped(.io_benchmark);

const Time = @import("time.zig").Time;
const IO = @import("io.zig").IO;
const flags = @import("flags.zig");

const Config = struct {
    iodepth: u12 = 128,
    block_size: u64 = 256 * 1024,
    file_size: u64 = 1024 * 1024 * 1024,
    runtime_secs: u64 = 1,
};

const event_loop_delay_ns = 1_000_000;

const GlobalContext = struct {
    config: Config,
    io: *IO,
    next_block: u64 = 0,
    live_ios: u32 = 0,
    stop: bool = false,
    write_block: []u8,
    fd: os.fd_t,
    bytes_written: u64 = 0,
};

const CompletionContext = struct {
    global_context: *GlobalContext,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var arg_iterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();

    var config = flags.parse(&arg_iterator, Config);

    assert(config.iodepth * config.block_size <= config.file_size);

    // todo how does fio handle blocks to be written?
    var write_block = try allocator.alloc(u8, config.block_size);
    defer allocator.free(write_block);

    for (write_block) |*byte| {
        byte.* = 0xF0;
    }

    var io = try IO.init(config.iodepth * 2, 0);
    defer io.deinit();

    const dir = try IO.open_dir(".");
    const file = try IO.open_file(
        dir,
        "testfile",
        config.file_size,
        .create
    );

    var global_context = GlobalContext {
        .config = config,
        .io = &io,
        .write_block = write_block,
        .fd = file,
    };

    var contexts = try allocator.alloc(CompletionContext, config.iodepth);
    defer allocator.free(contexts);
    var completions = try allocator.alloc(IO.Completion, config.iodepth);
    defer allocator.free(completions);

    for (contexts, completions) |*context, *completion| {
        context.* = CompletionContext {
            .global_context = &global_context,
        };

        const offset = global_context.next_block * config.block_size % config.file_size;
        global_context.next_block += 1;
        global_context.live_ios += 1;
        io.write(
            *CompletionContext,
            context,
            callback,
            completion,
            file,
            write_block,
            offset,
        );
    }

    var time = Time {};
    const start_time_ns = time.monotonic();
    const end_time_ns = start_time_ns + config.runtime_secs * 1_000_000_000;

    while (true) {
        try io.run_for_ns(event_loop_delay_ns);

        var time_ns = time.monotonic();
        if (time_ns >= end_time_ns) {
            if (global_context.stop == false) {
                std.log.debug("stopping", .{});
            }
            global_context.stop = true;
            break;
        }
    }

    while (true) {
        try io.tick();
        if (global_context.live_ios == 0) {
            break;
        }
    }

    const end_time_actual = time.monotonic();
    const total_ns = end_time_actual - start_time_ns;
    const total_bytes_written = global_context.bytes_written;

    const total_ns_f: f64 = @floatFromInt(total_ns);
    const total_bytes_written_f: f64 = @floatFromInt(total_bytes_written);
    const total_s_f = total_ns_f / 1_000_000_000.0;
    const total_mbytes_written_f = total_bytes_written_f / (1024.0 * 1024.0);
    const mbytes_written_per_s = total_mbytes_written_f / total_s_f;

    std.log.info(
        "MiB/s {} MiB {}, ms {}",
        .{
            @as(u64, @intFromFloat(mbytes_written_per_s)),
            total_bytes_written / (1024 * 1024),
            total_ns / 1_000_000,
        }
    );
}

fn callback(
    context: *CompletionContext,
    completion: *IO.Completion,
    result: IO.WriteError!usize,
) void {
    if (result) |_| {
    } else |err| {
        std.log.err("error {}", .{ err });
    }

    var global_context = context.global_context;

    global_context.bytes_written += global_context.config.block_size;

    if (global_context.stop) {
        global_context.live_ios -= 1;
        return;
    }

    var io = global_context.io;
    const offset = global_context.next_block * global_context.config.block_size % global_context.config.file_size;
    global_context.next_block += 1;
    io.write(
        *CompletionContext,
        context,
        callback,
        completion,
        global_context.fd,
        global_context.write_block,
        offset,
    );
}
