const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Version option (defaults to "dev" for local builds)
    const version = b.option([]const u8, "version", "Version string") orelse "dev";

    // Build options for passing version to source
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    // Library module
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Executable
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = "santa-tinsel",
        .root_module = exe_mod,
    });
    exe.root_module.addImport("lib", lib_mod);
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the formatter CLI");
    run_step.dependOn(&run_cmd.step);

    // Library tests
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    // Formatter tests
    const formatter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/formatter_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_formatter_tests = b.addRunArtifact(formatter_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_formatter_tests.step);
}
