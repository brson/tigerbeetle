const builtin = @import("builtin");
const std = @import("std");

const Shell = @import("../../../shell.zig");

pub fn tests(shell: *Shell, gpa: std.mem.Allocator) !void {
    try shell.exec("python3 -m mypy main.py --ignore-missing-imports", .{});

    // NB: This expects the vortex bin to be available.
    if (builtin.target.os.tag == .linux) {
        const base_path = "../../../../";
        const tigerbeetle_bin = base_path ++ "zig-out/bin/tigerbeetle";
        const vortex_bin = base_path ++ "zig-out/bin/vortex";
        const driver_command = "python3 " ++ base_path ++ "src/testing/vortex/python_driver/main.py";
        const vortex_out_dir = try shell.create_tmp_dir();
        defer shell.cwd.deleteTree(vortex_out_dir) catch {};

        const env_pythonpath = std.process.getEnvVarOwned(gpa, "PYTHONPATH") catch "";
        defer gpa.free(env_pythonpath);

        const pythonpath = try std.fmt.allocPrint(gpa, "{s}src/clients/python/src:{s}", .{ base_path, env_pythonpath });
        std.debug.print("PYTHONPATH: {s}\n", .{pythonpath});
        defer gpa.free(pythonpath);

        try shell.env.put("PYTHONPATH", pythonpath);

        try shell.exec(
            vortex_bin ++ " " ++
                "run --driver-command={driver_command} " ++
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
