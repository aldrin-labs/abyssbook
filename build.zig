const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "abyssbook",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Add benchmark executable
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });

    const bench_cmd = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&bench_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // E2E tests
    const e2e_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/e2e_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_e2e_tests = b.addRunArtifact(e2e_tests);
    const e2e_test_step = b.step("test-e2e", "Run end-to-end tests");
    e2e_test_step.dependOn(&run_e2e_tests.step);

    // Security tests
    const security_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/security_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    // Add the src directory to the import path for security tests
    security_tests.root_module.addAnonymousImport("cli", .{ .root_source_file = b.path("src/cli.zig") });

    const blockchain_security_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/blockchain_security_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    // Add the src directory to the import path for blockchain security tests 
    blockchain_security_tests.root_module.addAnonymousImport("blockchain_client", .{ .root_source_file = b.path("src/blockchain/client.zig") });

    const run_security_tests = b.addRunArtifact(security_tests);
    const run_blockchain_security_tests = b.addRunArtifact(blockchain_security_tests);
    
    const security_test_step = b.step("test-security", "Run security tests");
    security_test_step.dependOn(&run_security_tests.step);
    security_test_step.dependOn(&run_blockchain_security_tests.step);

    // Combined test step
    const all_tests_step = b.step("test-all", "Run all tests (unit, e2e, and security)");
    all_tests_step.dependOn(&run_unit_tests.step);
    all_tests_step.dependOn(&run_e2e_tests.step);
    all_tests_step.dependOn(&run_security_tests.step);
    all_tests_step.dependOn(&run_blockchain_security_tests.step);
}