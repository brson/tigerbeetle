const std = @import("std");
const builtin = @import("builtin");
const log = std.log;
const assert = std.debug.assert;

const Shell = @import("../../shell.zig");
const TmpTigerBeetle = @import("../../testing/tmp_tigerbeetle.zig");

pub fn tests(shell: *Shell, gpa: std.mem.Allocator) !void {
    assert(shell.file_exists("Gemfile"));

    // Build the native library.
    try shell.exec_zig("build clients:ruby -Drelease", .{});

    // Install Ruby dependencies.
    try shell.exec("bundle install", .{});

    // Run tests with a temporary TigerBeetle instance.
    {
        log.info("running minitest", .{});
        var tmp_beetle = try TmpTigerBeetle.init(gpa, .{
            .development = true,
        });
        defer tmp_beetle.deinit(gpa);
        errdefer tmp_beetle.log_stderr();

        try shell.env.put("TB_ADDRESS", tmp_beetle.port_str);
        try shell.exec("bundle exec rake test", .{});
    }

    // Run samples.
    inline for ([_][]const u8{ "basic", "two_phase" }) |sample| {
        log.info("testing sample '{s}'", .{sample});

        var tmp_beetle = try TmpTigerBeetle.init(gpa, .{
            .development = true,
        });
        defer tmp_beetle.deinit(gpa);
        errdefer tmp_beetle.log_stderr();

        try shell.env.put("TB_ADDRESS", tmp_beetle.port_str);
        try shell.exec("bundle exec ruby samples/{sample}.rb", .{ .sample = sample });
    }
}

pub fn validate_release(shell: *Shell, gpa: std.mem.Allocator, options: struct {
    version: []const u8,
    tigerbeetle: []const u8,
}) !void {
    _ = shell;
    _ = gpa;
    _ = options;
    // The Ruby client is not yet published.
}

pub fn release_published_latest(shell: *Shell) ![]const u8 {
    _ = shell;
    return "unimplemented";
}
