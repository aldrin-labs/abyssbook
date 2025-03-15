const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main library
    const lib = b.addStaticLibrary(.{
        .name = "abyssbook",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Main executable
    const exe = b.addExecutable(.{
        .name = "abyssbook",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Phishing detector executable
    const phishing_detector = b.addExecutable(.{
        .name = "phishing-detector",
        .root_source_file = b.path("src/phishing_detector.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(phishing_detector);

    // Run command for the main executable
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Run command for the phishing detector
    const run_phishing_cmd = b.addRunArtifact(phishing_detector);
    run_phishing_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_phishing_cmd.addArgs(args);
    }
    const run_phishing_step = b.step("run-phishing", "Run the phishing detector");
    run_phishing_step.dependOn(&run_phishing_cmd.step);

    // Tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // URL validator tests
    const url_validator_tests = b.addTest(.{
        .root_source_file = b.path("src/url_validator.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_url_validator_tests = b.addRunArtifact(url_validator_tests);
    const url_validator_test_step = b.step("test-url", "Run URL validator tests");
    url_validator_test_step.dependOn(&run_url_validator_tests.step);
}