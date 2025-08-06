const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

const log = std.log.scoped(.run);

pub fn main(allocator: std.mem.Allocator) !void {
    if (builtin.os.tag != .linux) {
        log.err("The `run` command to set up namespaces is only supported on Linux.", .{});
        return error.NotSupported;
    }

    var args_passthrough = try std.process.argsWithAllocator(allocator);
    defer args_passthrough.deinit();

    var vortex_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const vortex_path = try std.fs.selfExePath(&vortex_path_buffer);

    var argv: std.ArrayListUnmanaged([]const u8) = .{};
    defer argv.deinit(allocator);

    // Skip first two arguments ('vortex run').
    _ = args_passthrough.next();
    _ = args_passthrough.next();

    // Add the `vortex supervisor` command and passthrough args.
    try argv.append(allocator, vortex_path);
    try argv.append(allocator, "supervisor");

    while (args_passthrough.next()) |arg| {
        try argv.append(allocator, arg);
    }

    // Tell the supervisor to set up loopback networking.
    try argv.append(allocator, "--configure-namespace");

    // Create namespaces using syscalls instead of external unshare command
    try create_namespaces_and_run(allocator, argv.items);
}

// Implementation of `unshare`, equivalent to
//
//     unshare --net --pid --map-root-user --fork
fn create_namespaces_and_run(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    // Get current uid/gid before creating namespaces so we can map them to root later
    const uid = linux.getuid();
    const gid = linux.getgid();

    // Create user namespace first (required for --map-root-user)
    const unshare_result = std.os.linux.unshare(linux.CLONE.NEWUSER);
    if (unshare_result != 0) {
        log.err("Failed to create user namespace: {}", .{unshare_result});
        return error.UnshareFailure;
    }

    // Disable setgroups (required for unprivileged uid/gid mapping)
    try write_to_file("/proc/self/setgroups", "deny");

    // Map current user to root (uid 0) in the new namespace.
    // This will allow the child supervisor's `--configure-namespace`
    // flag to set up networking with `ip link`.
    var uid_map_buf: [64]u8 = undefined;
    const uid_map = try std.fmt.bufPrint(&uid_map_buf, "0 {d} 1", .{uid});
    try write_to_file("/proc/self/uid_map", uid_map);

    var gid_map_buf: [64]u8 = undefined;
    const gid_map = try std.fmt.bufPrint(&gid_map_buf, "0 {d} 1", .{gid});
    try write_to_file("/proc/self/gid_map", gid_map);

    // Create network and PID namespaces
    const unshare_net_pid_result = std.os.linux.unshare(linux.CLONE.NEWNET | linux.CLONE.NEWPID);
    if (unshare_net_pid_result != 0) {
        log.err("Failed to create net/pid namespaces: {}", .{unshare_net_pid_result});
        return error.UnshareFailure;
    }

    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    
    try child.spawn();
    const result = try child.wait();
    std.process.exit(@intFromEnum(result));
}

fn write_to_file(path: []const u8, content: []const u8) !void {
    const file = std.fs.openFileAbsolute(path, .{ .mode = .write_only }) catch |err| {
        log.err("Failed to open {s}: {}", .{ path, err });
        return err;
    };
    defer file.close();

    _ = file.writeAll(content) catch |err| {
        log.err("Failed to write to {s}: {}", .{ path, err });
        return err;
    };
}
