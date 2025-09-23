//! TigerBeetle unshare debugging binary
//!
//! A minimal standalone binary to debug unshare functionality without
//! the complexity of the full TigerBeetle build system or other dependencies.
//! 
//! Supports --user, --pid, --fork flags, focusing on the --user --pid --fork case.

const std = @import("std");
const stdx = @import("stdx");
const builtin = @import("builtin");
const assert = std.debug.assert;

const unshare = stdx.unshare;

const help_text = 
    \\Usage: tbunshare [OPTIONS] <command..>
    \\
    \\A debugging binary for unshare functionality.
    \\
    \\Options:
    \\  --user        Create a user namespace
    \\  --pid         Create a PID namespace  
    \\  --fork        Fork after creating namespaces
    \\  --help        Show this help message
    \\
;


pub fn main() !void {
    if (builtin.os.tag != .linux) {
        std.log.err("tbunshare only works on Linux", .{});
        return;
    }
    
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (allocator.deinit()) {
        .ok => {},
        .leak => @panic("memory leak"),
    };
    const gpa = allocator.allocator();
    
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    
    var cliargs = try parse_args(gpa, &args);

    defer {
        while (cliargs.rest.pop()) |arg| {
            _ = gpa.free(arg);
        }
        _ = cliargs.rest.deinit(gpa);
    }

    if (cliargs.help) {
        std.debug.print("{s}", .{help_text});
        return;
    }

    assert(cliargs.user and cliargs.pid and cliargs.fork);
    assert(cliargs.rest.items.len > 0);
    
    try unshare.maybe_unshare_and_run(gpa, .{
        .pid = cliargs.pid,
        .network = false,
        .command = cliargs.rest.items,
    });
}

const CLIArgs = struct {
    user: bool = false,
    pid: bool = false,
    fork: bool = false,
    help: bool = false,
    rest: std.ArrayListUnmanaged([]const u8),
};

fn parse_args(
    gpa: std.mem.Allocator,
    args_iter: *std.process.ArgIterator,
) !CLIArgs {
    _ = args_iter.skip();

    var cliargs = CLIArgs {
        .user = false,
        .pid = false,
        .fork = false,
        .rest = std.ArrayListUnmanaged([]const u8).empty,
    };

    errdefer {
        // todo
    }

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--user")) {
            cliargs.user = true;
        } else if (std.mem.eql(u8, arg, "--pid")) {
            cliargs.pid = true;
        } else if (std.mem.eql(u8, arg, "--fork")) {
            cliargs.fork = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            cliargs.help = true;
        } else {
            const arg_clone = try gpa.dupe(u8, arg);
            cliargs.rest.append(gpa, arg_clone) catch |err| {
                gpa.free(arg_clone);
                return err;
            };
            break;
        }
    }

    while (args_iter.next()) |arg| {
        const arg_clone = try gpa.dupe(u8, arg);
        cliargs.rest.append(gpa, arg_clone) catch |err| {
            gpa.free(arg_clone);
            return err;
        };
    }

    return cliargs;
}
