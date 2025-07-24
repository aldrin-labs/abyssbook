const std = @import("std");
const logging = @import("logging.zig");
const testing = std.testing;

test "logger initialization and basic functionality" {
    var logger = try logging.Logger.init(testing.allocator, .INFO);
    defer logger.deinit();

    // Test that logger is initialized with correct level
    try testing.expect(logger.getLevel() == .INFO);

    // Test level setting
    logger.setLevel(.DEBUG);
    try testing.expect(logger.getLevel() == .DEBUG);

    // Test logging functions don't crash
    try logger.debug("test", "Debug message");
    try logger.info("test", "Info message");
    try logger.warn("test", "Warning message");
    try logger.err("test", "Error message");
    try logger.critical("test", "Critical message");
}

test "log level parsing" {
    try testing.expect(logging.LogLevel.fromString("debug") == .DEBUG);
    try testing.expect(logging.LogLevel.fromString("info") == .INFO);
    try testing.expect(logging.LogLevel.fromString("warn") == .WARN);
    try testing.expect(logging.LogLevel.fromString("error") == .ERROR);
    try testing.expect(logging.LogLevel.fromString("critical") == .CRITICAL);
    try testing.expect(logging.LogLevel.fromString("invalid") == null);
}

test "log level toString" {
    try testing.expectEqualStrings("DEBUG", logging.LogLevel.DEBUG.toString());
    try testing.expectEqualStrings("INFO", logging.LogLevel.INFO.toString());
    try testing.expectEqualStrings("WARN", logging.LogLevel.WARN.toString());
    try testing.expectEqualStrings("ERROR", logging.LogLevel.ERROR.toString());
    try testing.expectEqualStrings("CRITICAL", logging.LogLevel.CRITICAL.toString());
}

test "logging with context" {
    var logger = try logging.Logger.init(testing.allocator, .DEBUG);
    defer logger.deinit();

    const context = .{
        .user_id = @as(u32, 123),
        .action = "test_action",
        .success = true,
    };

    try logger.logWithContext(.INFO, "test", "Test message with context", context);
}

test "global logger initialization" {
    try logging.initGlobalLogger(testing.allocator, .INFO);
    defer logging.deinitGlobalLogger();

    // Test that global logger is available
    const global_logger = logging.getGlobalLogger();
    try testing.expect(global_logger != null);

    // Test global logging functions
    logging.infoGlobal("test", "Global info message");
    logging.debugGlobal("test", "Global debug message");
    logging.warnGlobal("test", "Global warning message");
    logging.errorGlobal("test", "Global error message");
    logging.criticalGlobal("test", "Global critical message");
}

test "security logging context" {
    try logging.initGlobalLogger(testing.allocator, .DEBUG);
    defer logging.deinitGlobalLogger();

    // Test security-related logging
    logging.logGlobalWithContext(.WARN, "security", "Suspicious activity detected", .{
        .source_ip = "192.168.1.100",
        .user_agent = "suspicious_bot",
        .attempts = @as(u32, 5),
    });

    logging.logGlobalWithContext(.ERROR, "auth", "Authentication failure", .{
        .username = "admin",
        .failed_attempts = @as(u32, 3),
        .locked_out = true,
    });
}
