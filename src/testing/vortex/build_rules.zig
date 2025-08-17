const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b;
    // This module is not intended to be built standalone
}

pub fn build_vortex_drivers(
    b: *std.Build,
    steps: struct {
        vortex_java: *std.Build.Step,
        vortex_rust: *std.Build.Step,
        vortex_python: *std.Build.Step,
        vortex_all: *std.Build.Step,
    },
    options: struct {
        vortex_step: *std.Build.Step,
        clients_java_step: *std.Build.Step,
        clients_python_step: *std.Build.Step,
    },
) void {
    build_vortex_java_driver(b, steps.vortex_java, .{
        .clients_java_step = options.clients_java_step,
    });

    build_vortex_rust_driver(b, steps.vortex_rust);

    build_vortex_python_driver(b, steps.vortex_python, .{
        .clients_python_step = options.clients_python_step,
    });

    // vortex:all builds vortex binary and all drivers
    steps.vortex_all.dependOn(options.vortex_step);
    steps.vortex_all.dependOn(steps.vortex_java);
    steps.vortex_all.dependOn(steps.vortex_rust);
    steps.vortex_all.dependOn(steps.vortex_python);
}

fn build_vortex_java_driver(
    b: *std.Build,
    step_vortex_java: *std.Build.Step,
    options: struct {
        clients_java_step: *std.Build.Step,
    },
) void {
    // Java driver depends on the Java client being installed first
    step_vortex_java.dependOn(options.clients_java_step);

    // Build the Java driver JAR
    const mvn_package = b.addSystemCommand(&.{
        "mvn", "package", "-DskipTests"
    });
    mvn_package.cwd = b.path("src/testing/vortex/java_driver");
    mvn_package.setName("build java vortex driver");

    step_vortex_java.dependOn(&mvn_package.step);
}

fn build_vortex_rust_driver(
    b: *std.Build,
    step_vortex_rust: *std.Build.Step,
) void {
    const cargo_build = b.addSystemCommand(&.{
        "cargo", "build"
    });
    cargo_build.cwd = b.path("src/testing/vortex/rust_driver");
    cargo_build.setName("build rust vortex driver");

    step_vortex_rust.dependOn(&cargo_build.step);
}

fn build_vortex_python_driver(
    b: *std.Build,
    step_vortex_python: *std.Build.Step,
    options: struct {
        clients_python_step: *std.Build.Step,
    },
) void {
    _ = b;
    // Python driver uses the Python client, so depend on it being built
    step_vortex_python.dependOn(options.clients_python_step);
}
