//! Some tools for working with Linux `unshare` and namespaces.
//!
//! We use user, pid, and network namespaces for two purposes:
//!
//! - Processes namespaces enable all processes in the namespace
//!   to be killed when the namespace's init process is.
//! - Network namespaces allow us to create an isolated loopback network.
//!
//! This code uses the Linux `unshare` syscall to create new
//! namespaces.
//!
//! The main tool here is `maybe_unshare_and_relaunch`, which provides
//! a pattern for forking a new process that is an init process in
//! its own process namespace.

const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const log = std.log.scoped(.unshare);
const assert = std.debug.assert;

/// Relaunch this process with new namespaces.
///
/// If the current process is already running with the namespaces configured as
/// requested then this function does nothing. Otherwise it configures the
/// namespaces and with them spawns a new process with the same arguments as
/// the current process, waits for it, then exits the process directly (not
/// returning from this function).
///
/// This should generally be called immediately from `main`.
///
/// If the `pid` option is provided then the spawned process will be the init
/// process in a new pid namespace. When it is terminated all subprocesses
/// transitively will also be terminated.
///
/// If the `network` option is provided then the spawned process and its
/// subprocesses will have loopback network access only.
pub fn maybe_unshare_and_relaunch(
    gpa: std.mem.Allocator,
    options: struct {
        pid: bool,
        network: bool,
    },
) !void {
    const args_ours = std.os.argv;

    // We get a fresh path to the exe instead of using the original
    // first argument so that the exe path will be correct even if
    // this process's cwd has changed relative to the original exe.
    var exe_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&exe_path_buffer);

    // Convert arguments to execve format: [*:null]const ?[*:0]const u8
    const argv_execve = try gpa.allocSentinel(?[*:0]const u8, args_ours.len, null);
    // Handle partial initialization failure yuck is there a better way?
    for (0..args_ours.len) |arg_index| {
        argv_execve[arg_index] = null;
    }
    defer {
        for (0..args_ours.len) |arg_index| {
            const arg = argv_execve[arg_index] orelse {
                continue;
            };
            gpa.free(std.mem.span(arg));
        }
        gpa.free(argv_execve);
    }

    // First argument is the exe path (null-terminated)
    argv_execve[0] = try gpa.dupeZ(u8, exe_path);

    // Convert remaining arguments to null-terminated strings
    for (1..args_ours.len) |arg_index| {
        const arg_span = std.mem.span(args_ours[arg_index]);
        argv_execve[arg_index] = try gpa.dupeZ(u8, arg_span);
    }

    // todo don't use env_map if it can be avoided
    var env_map = try std.process.getEnvMap(gpa);
    defer env_map.deinit();

    try env_map.put("TB_UNSHARED", "1");

    // Convert environment to execve format: [*:null]const ?[*:0]const u8
    const envp_execve = try std.process.createEnvironFromMap(gpa, &env_map, .{});
    defer {
        for (envp_execve) |maybe_env| {
            if (maybe_env) |env| {
                gpa.free(std.mem.span(env));
            }
        }
        gpa.free(envp_execve);
    }

    // Convert exe_path to null-terminated format
    const exe_path_z = try gpa.dupeZ(u8, exe_path);
    defer gpa.free(exe_path_z);

    return maybe_unshare_and_run_primitive(gpa, .{
        .pid = options.pid,
        .network = options.network,
        .exe_path = exe_path_z.ptr,
        .argv = @ptrCast(argv_execve.ptr),
        .envp = @ptrCast(envp_execve.ptr),
    });
}

pub fn maybe_unshare_and_run(
    gpa: std.mem.Allocator,
    options: struct {
        pid: bool,
        network: bool,
        command: []const []const u8,
    },
) !void {
    assert(options.command.len > 0);

    const exe_path_z = try gpa.dupeZ(u8, options.command[0]);
    defer gpa.free(exe_path_z);

    // Convert arguments to execve format: [*:null]const ?[*:0]const u8.
    const argv_execve = try gpa.allocSentinel(?[*:0]const u8, options.command.len, null);
    // Handle partial initialization failure yuck is there a better way?
    for (0..options.command.len) |arg_index| {
        argv_execve[arg_index] = null;
    }
    defer {
        for (0..options.command.len) |arg_index| {
            const arg = argv_execve[arg_index] orelse {
                continue;
            };
            gpa.free(std.mem.span(arg));
        }
        gpa.free(argv_execve);
    }

    // Convert arguments to null-terminated strings.
    for (options.command, 0..) |arg, arg_index| {
        argv_execve[arg_index] = try gpa.dupeZ(u8, arg);
    }

    // Add TB_UNSHARED to the environment.
    var env_map = try std.process.getEnvMap(gpa);
    defer env_map.deinit();

    try env_map.put("TB_UNSHARED", "1");

    // Convert environment to execve format: [*:null]const ?[*:0]const u8.
    const envp_execve = try std.process.createEnvironFromMap(gpa, &env_map, .{});
    defer {
        for (envp_execve) |maybe_env| {
            if (maybe_env) |env| {
                gpa.free(std.mem.span(env));
            }
        }
        gpa.free(envp_execve);
    }

    return maybe_unshare_and_run_primitive(gpa, .{
        .pid = options.pid,
        .network = options.network,
        .exe_path = exe_path_z.ptr,
        .argv = @ptrCast(argv_execve.ptr),
        .envp = @ptrCast(envp_execve.ptr),
    });
}

pub fn maybe_unshare_and_run_primitive(
    gpa: std.mem.Allocator,
    options: struct {
        pid: bool,
        network: bool,
        exe_path: [*:0]const u8,
        argv: [*:null]const ?[*:0]const u8,
        envp: [*:null]const ?[*:0]const u8,
    },
) !void {
    comptime assert(builtin.os.tag == .linux);

    {
        log.debug("pid: {}", .{options.pid});
        log.debug("network: {}", .{options.network});
        log.debug("exe_path: {s}", .{options.exe_path});
        for (std.mem.span(options.argv), 0..) |arg, arg_index| {
            log.debug("argv[{}]: {s}", .{ arg_index, arg.? });
        }
    }

    const should_unshare_and_fork = std.posix.getenv("TB_UNSHARED") == null;

    if (should_unshare_and_fork) {
        var action_new_mask: linux.sigset_t = linux.empty_sigset;
        linux.sigaddset(&action_new_mask, linux.SIG.CHLD);
        const action_new: linux.Sigaction = .{
            .handler = .{ .handler = linux.SIG.DFL },
            .mask = action_new_mask,
            .flags = linux.SA.RESTART,
            .restorer = null,
        };
        var action_old: linux.Sigaction = undefined;
        const sigaction_result = linux.sigaction(linux.SIG.CHLD, &action_new, &action_old);
        const sigaction_errno = std.os.linux.E.init(sigaction_result);
        if (sigaction_errno != .SUCCESS) {
            log.err("Failed to call sigaction: {}", .{sigaction_errno});
            return error.UnshareFailure;
        }

        defer {
            @panic("todo");
        }

        try linux_unshare(.{
            .pid = options.pid,
            .network = options.network,
        });
        if (options.network) {
            try linux_ip_link_loopback();
        }
        try fork_and_exit(gpa, .{
            .exe_path = options.exe_path,
            .argv = options.argv,
            .envp = options.envp,
        });
    }
}

/// Implementation of `unshare` somewhat like
///
/// ```
/// unshare --user --net --pid
/// ```
///
/// We're trying to accomplish two main things:
///
/// - creating a new pid namespace so that all subprocesses
///   are automatically terminated when pid 1 (the forked
///   vortex supervisor) is terminated.
/// - creating a network sandbox
///
/// Note that on recent Ubuntu's this only works if AppArmour
/// rules have been relaxed:
///
/// ```
/// sudo sysctl -w kernel.apparmor_restrict_unprivileged_unconfined=0
/// sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
/// ```
pub fn linux_unshare(options: struct {
    pid: bool,
    network: bool,
}) !void {
    comptime assert(builtin.os.tag == .linux);

    // Create user namespace first.
    const unshare_user_result = std.os.linux.unshare(linux.CLONE.NEWUSER);
    const unshare_user_errno = std.os.linux.E.init(unshare_user_result);
    if (unshare_user_errno != .SUCCESS) {
        log.err("Failed to create user namespace: {}", .{unshare_user_errno});
        return error.UnshareFailure;
    }

    // Create PID namespace.
    if (options.pid) {
        const unshare_pid_result = std.os.linux.unshare(linux.CLONE.NEWPID);
        const unshare_pid_errno = std.os.linux.E.init(unshare_pid_result);
        if (unshare_pid_errno != .SUCCESS) {
            log.err("Failed to create pid namespace: {}", .{unshare_pid_errno});
            return error.UnshareFailure;
        }
    }

    // Create network namespace.
    if (options.network) {
        const unshare_net_result = std.os.linux.unshare(linux.CLONE.NEWNET);
        const unshare_net_errno = std.os.linux.E.init(unshare_net_result);
        if (unshare_net_errno != .SUCCESS) {
            log.err("Failed to create net namespace: {}", .{unshare_net_errno});
            return error.UnshareFailure;
        }
    }
}

/// Implementation of `ip link` equivalent to
///
/// ```
/// ip link set up dev lo
/// ```
///
/// This brings up the loopback device so that networking
/// over 127.0.0.1 works.
pub fn linux_ip_link_loopback() !void {
    comptime assert(builtin.os.tag == .linux);

    // Open a netlink socket with the NETLINK.ROUTE protocol.
    const sock = std.posix.socket(
        linux.AF.NETLINK,
        std.posix.SOCK.RAW,
        linux.NETLINK.ROUTE,
    ) catch |err| {
        log.err("failed to create netlink socket: {}", .{err});
        return error.IpLink;
    };
    defer std.posix.close(sock);

    const addr = linux.sockaddr.nl{
        .family = linux.AF.NETLINK,
        .pid = 0,
        .groups = 0,
    };
    std.posix.bind(sock, @ptrCast(&addr), @sizeOf(@TypeOf(addr))) catch |err| {
        log.err("failed to bind netlink socket: {}", .{err});
        return error.IpLink;
    };

    // Netlink definitions.
    const nlmsghdr = linux.nlmsghdr;
    const ifinfomsg = linux.ifinfomsg;

    const nlmsgerr = extern struct {
        @"error": c_int,
        msg: nlmsghdr,
    };

    const IFF_UP = 0x1;

    // Our message to the kernel - header plus interface info.
    const Message = extern struct {
        hdr: nlmsghdr,
        ifi: ifinfomsg,

        comptime {
            assert(@sizeOf(@This()) == @sizeOf(nlmsghdr) + @sizeOf(ifinfomsg));
        }
    };

    // Kernel's message to us - header plus error info.
    const Response = extern struct {
        hdr: nlmsghdr,
        err: nlmsgerr,

        comptime {
            assert(@sizeOf(@This()) == @sizeOf(nlmsghdr) + @sizeOf(nlmsgerr));
        }
    };

    var msg: Message = .{
        .hdr = .{
            .len = @sizeOf(nlmsghdr) + @sizeOf(ifinfomsg),
            .type = .RTM_NEWLINK,
            // ACK says to always send a response, even on success.
            .flags = linux.NLM_F_REQUEST | linux.NLM_F_ACK,
            .seq = 0,
            .pid = 0,
        },
        .ifi = .{
            .family = linux.AF.UNSPEC,
            .type = 0,
            // Seems to be the loopback device, not sure how
            // to find this value the correct way.
            .index = 1,
            .flags = IFF_UP,
            // man pages say use this value.
            .change = 0xFFFFFFFF,
        },
    };

    const msg_buf = std.mem.asBytes(&msg);
    const sent_len = std.posix.send(sock, msg_buf, 0) catch |err| {
        log.err("failed to send netlink message: {}", .{err});
        return error.IpLink;
    };
    assert(sent_len == msg.hdr.len);

    var ack: Response = undefined;
    const ack_buf = std.mem.asBytes(&ack);
    const ack_len = std.posix.recv(sock, ack_buf, 0) catch |err| {
        log.err("failed to receive netlink ack: {}", .{err});
        return error.IpLink;
    };

    assert(ack_len == @sizeOf(Response));
    assert(ack.hdr.type == .ERROR);
    assert(ack.err.msg.pid == msg.hdr.pid);

    if (ack.err.@"error" != 0) {
        log.err("netlink operation failed with errno: {}", .{-ack.err.@"error"});
        return error.IpLink;
    }
}

const ChildArgs = struct {
    exe_path: [*:0]const u8,
    argv: [*:null]?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
    old_sigset: linux.sigset_t,
};

fn fork_and_exit(
    gpa: std.mem.Allocator,
    options: struct {
        exe_path: [*:0]const u8,
        argv: [*:null]const ?[*:0]const u8,
        envp: [*:null]const ?[*:0]const u8,
    },
) !void {
    // Block INT and TERM signals before forking, like standard unshare does.
    // This prevents Ctrl+C from reaching the child directly and allows the
    // parent to handle child termination properly.
    var old_sigset: linux.sigset_t = undefined;
    var new_sigset: linux.sigset_t = linux.empty_sigset;
    linux.sigaddset(&new_sigset, linux.SIG.INT);
    linux.sigaddset(&new_sigset, linux.SIG.TERM);

    const sigprocmask_result = linux.sigprocmask(linux.SIG.BLOCK, &new_sigset, &old_sigset);
    //const sigprocmask_result = linux.sigprocmask(linux.SIG.SETMASK, &new_sigset, &old_sigset);
    if (linux.E.init(sigprocmask_result) != .SUCCESS) {
        log.err("Failed to block signals before fork", .{});
        return error.SignalMaskFailure;
    }

    // Restore signal mask when we're done.
    // There are early-return trys below so this is needed even though we intend to `process.exit`.
    defer {
        _ = linux.sigprocmask(linux.SIG.SETMASK, &old_sigset, null);
    }

    // The posix.execvpeZ_expandArg0 function, unlike `linux.execve`, wants to
    // mutate the argv slice, so we just make a copy instead of pushing more
    // args-related complexity up to the caller.
    const argv_slice = std.mem.span(options.argv);
    const argv_copy: [:null]?[*:0]const u8 = try gpa.allocSentinel(?[*:0]const u8, argv_slice.len, null);
    @memcpy(argv_copy[0..argv_slice.len], argv_slice);
    defer gpa.free(argv_copy);

    const child_args = ChildArgs{
        .exe_path = options.exe_path,
        .argv = argv_copy,
        .envp = options.envp,
        .old_sigset = old_sigset,
    };

    // fixme it _looks_ like unshare is able to just pass null to clone,
    // const clone_stack = null;

    // Allocate stack for child process using mmap.
    const stack_size = 8 * 1024 * 1024; // 8MB stack
    const stack_base = std.posix.mmap(
        null,
        stack_size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .STACK = true },
        -1,
        0,
    ) catch |err| {
        log.err("Failed to allocate stack: {}", .{err});
        return error.StackAllocationFailure;
    };

    // Stack grows downward, so point to the top of allocated memory
    // Align to 16-byte boundary for proper stack alignment
    const stack_top = @intFromPtr(stack_base.ptr) + stack_size;
    const clone_stack = stack_top & ~@as(usize, 15); // Align to 16 bytes

    // Ensure stack cleanup happens even on early return
    defer std.posix.munmap(stack_base);

    const clone_flags = linux.SIG.CHLD;
    const clone_fn_args = @intFromPtr(&child_args);
    const clone_ptid = null;
    const clone_tp = 0;
    const clone_ctid = null;

    const child_pid = linux.clone(
        clone_fn,
        clone_stack,
        clone_flags,
        clone_fn_args,
        clone_ptid,
        clone_tp,
        clone_ctid,
    );
    const clone_errno = linux.E.init(child_pid);
    if (clone_errno != .SUCCESS) {
        log.err("Failed to clone child process: {}", .{clone_errno});
        return error.CloneFailure;
    }

    assert(child_pid > 0);
    log.debug("child_pid: {}", .{child_pid});

    // Parent process: wait for child
    var wstatus: u32 = undefined;
    const wait_result = linux.wait4(@intCast(child_pid), &wstatus, 0, null);
    const wait_errno = linux.E.init(wait_result);
    if (wait_errno != .SUCCESS) {
        log.err("wait4 failed: {}", .{wait_errno});
        std.process.exit(2);
    }

    // Handle child exit status
    if (linux.W.IFEXITED(wstatus)) {
        const exit_code = linux.W.EXITSTATUS(wstatus);
        log.debug("unshared subprocesses exited with exit code {}", .{exit_code});
        std.process.exit(@intCast(exit_code));
    } else if (linux.W.IFSIGNALED(wstatus)) {
        const signal = linux.W.TERMSIG(wstatus);
        log.info("unshared subprocesses exited with signal {}", .{signal});
        std.process.exit(1);
    } else {
        log.err("unshared subprocesses exited abnormally", .{});
        std.process.exit(2);
    }
}

fn clone_fn(args_addr: usize) callconv(.c) u8 {
    const args: *const ChildArgs = @ptrFromInt(args_addr);

    var parent_sigset: linux.sigset_t = undefined;

    const sigprocmask_result = linux.sigprocmask(linux.SIG.SETMASK, &args.old_sigset, &parent_sigset);
    const sigprocmask_errno = linux.E.init(sigprocmask_result);
    if (sigprocmask_errno != .SUCCESS) {
        log.err("unshared child process sigprocmask failed: {}", .{sigprocmask_errno});
        return 2;
    }

    const execvpe_error = std.posix.execvpeZ_expandArg0(.expand, args.exe_path, args.argv, args.envp);
    log.err("unshared child process execvpe failed: {}", .{execvpe_error});
    return 2;
}
