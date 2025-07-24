const std = @import("std");
const testing = std.testing;
const logging = @import("logging.zig");
const cli = @import("cli.zig");

test "CLI logging integration" {
    // Initialize global logger for testing
    try logging.initGlobalLogger(testing.allocator, .DEBUG);
    defer logging.deinitGlobalLogger();

    // Test basic CLI initialization
    var registry = cli.init();
    defer registry.deinit();

    // Test help command execution (should not fail)
    try cli.execute(&registry, &[_][]const u8{"abyssbook"});

    // Test invalid command logging
    const result = cli.execute(&registry, &[_][]const u8{ "abyssbook", "invalid_command" });
    try testing.expect(result == error.UnknownCommand or result == void{});
}

test "Security logging patterns" {
    try logging.initGlobalLogger(testing.allocator, .DEBUG);
    defer logging.deinitGlobalLogger();

    // Test security event logging
    logging.logGlobalWithContext(.WARN, "security", "Test security event", .{
        .event_type = "test_event",
        .severity = "medium",
        .detected_at = "test_time",
    });

    // Test CLI security logging
    logging.logGlobalWithContext(.ERROR, "cli.args", "Suspicious input detected", .{
        .input_type = "command_arg",
        .pattern_detected = "injection_attempt",
        .blocked = true,
    });

    // Test order security logging
    logging.logGlobalWithContext(.INFO, "service.orders", "Order validation", .{
        .order_type = "buy",
        .validation_result = "passed",
        .risk_score = @as(u32, 1),
    });
}

test "Log level configuration" {
    try logging.initGlobalLogger(testing.allocator, .INFO);
    defer logging.deinitGlobalLogger();

    // Test log level changes
    logging.setGlobalLogLevel(.ERROR);

    const logger = logging.getGlobalLogger();
    try testing.expect(logger != null);
    if (logger) |l| {
        try testing.expect(l.getLevel() == .ERROR);
    }

    // Test invalid log level parsing
    try testing.expect(logging.LogLevel.fromString("invalid") == null);
    try testing.expect(logging.LogLevel.fromString("debug") == .DEBUG);
}

test "Context logging validation" {
    try logging.initGlobalLogger(testing.allocator, .DEBUG);
    defer logging.deinitGlobalLogger();

    // Test various context types
    logging.logGlobalWithContext(.INFO, "test", "Mixed context test", .{
        .string_field = "test_value",
        .int_field = @as(i32, 42),
        .float_field = @as(f64, 3.14),
        .bool_field = true,
    });

    // Test security-relevant context
    logging.logGlobalWithContext(.WARN, "auth", "Authentication attempt", .{
        .user_id = @as(u32, 12345),
        .source_ip = "192.168.1.100",
        .success = false,
        .attempt_count = @as(u32, 3),
    });
}

test "Performance logging overhead" {
    try logging.initGlobalLogger(testing.allocator, .INFO);
    defer logging.deinitGlobalLogger();

    const start_time = std.time.nanoTimestamp();

    // Log many messages to test performance
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        logging.infoGlobal("perf_test", "Performance test message");
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    // Log timing info (should be reasonably fast)
    std.debug.print("1000 log messages took {d:.2}ms\n", .{duration_ms});

    // Should complete in reasonable time (less than 100ms for 1000 messages)
    try testing.expect(duration_ms < 100.0);
}
