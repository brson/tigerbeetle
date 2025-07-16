const builtin = @import("builtin");
const std = @import("std");
const Shell = @import("../../../shell.zig");

pub fn tests(shell: *Shell, gpa: std.mem.Allocator) !void {
    _ = gpa;

    // Install dependencies and build
    try shell.exec("npm install", .{});
    try shell.exec("npm run build", .{});

    // Optional: Run linting
    //try shell.exec("npx eslint src --ext .ts", .{});

    // Vortex integration test (Linux only)
    if (builtin.target.os.tag == .linux) {
        const base_path = "../../../../";
        const tigerbeetle_bin = base_path ++ "zig-out/bin/tigerbeetle";
        const vortex_bin = base_path ++ "zig-out/bin/vortex";
        const driver_command = "node " ++ base_path ++ "src/testing/vortex/node_driver/dist/main.js";
        const vortex_out_dir = try shell.create_tmp_dir();
        defer shell.cwd.deleteTree(vortex_out_dir) catch {};

        try shell.exec(
            vortex_bin ++ " run --driver-command={driver_command} " ++
                "--tigerbeetle-executable={tigerbeetle_bin} " ++
                "--output-directory={vortex_out_dir} " ++
                "--replica-count=1 " ++
                "--disable-faults " ++
                "--test-duration-seconds=10",
            .{
                .driver_command = driver_command,
                .tigerbeetle_bin = tigerbeetle_bin,
                .vortex_out_dir = vortex_out_dir,
            },
        );
    }
}
