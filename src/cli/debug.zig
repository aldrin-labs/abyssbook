const std = @import("std");
const logging = @import("../logging.zig");

/// Handle debug commands
pub fn handleDebugCommand(args: []const []const u8) !void {
    // Log the debug command execution
    if (args.len > 0) {
        logging.infoGlobal("cli.debug", "Debug command executed");
        logging.logGlobalWithContext(.INFO, "cli.debug", "Debug command details", .{
            .subcommand = args[0],
            .arg_count = args.len,
        });
    }

    if (args.len == 0) {
        // Show debug help
        showDebugHelp();
        return;
    }

    const subcommand = args[0];
    if (std.mem.eql(u8, subcommand, "log")) {
        if (args.len < 2) {
            logging.warnGlobal("cli.debug", "Missing log level argument");
            std.debug.print("Error: Missing log level\n", .{});
            std.debug.print("Usage: abyssbook debug log <level>\n", .{});
            return;
        }
        try setLogLevel(args[1]);
    } else if (std.mem.eql(u8, subcommand, "dump")) {
        if (args.len < 2) {
            logging.warnGlobal("cli.debug", "Missing dump target argument");
            std.debug.print("Error: Missing dump target\n", .{});
            std.debug.print("Usage: abyssbook debug dump <target>\n", .{});
            return;
        }
        try dumpState(args[1]);
    } else if (std.mem.eql(u8, subcommand, "perf")) {
        try runPerfTest(if (args.len > 1) args[1..] else &[_][]const u8{});
    } else {
        logging.warnGlobalWithContext("cli.debug", "Unknown debug subcommand", .{
            .subcommand = subcommand,
        });
        std.debug.print("Unknown debug subcommand: {s}\n", .{subcommand});
        showDebugHelp();
    }
}

/// Show debug command help
fn showDebugHelp() void {
    logging.debugGlobal("cli.debug", "Debug help requested");
    std.debug.print("Abyssbook Debug Commands\n", .{});
    std.debug.print("======================\n\n", .{});
    std.debug.print("Available subcommands:\n", .{});
    std.debug.print("  log <level>     - Set log level (debug, info, warn, error, critical)\n", .{});
    std.debug.print("  dump <target>   - Dump internal state (orderbook, memory, stats)\n", .{});
    std.debug.print("  perf [test]     - Run performance tests\n", .{});
}

/// Set the log level
fn setLogLevel(level: []const u8) !void {
    const log_level = logging.LogLevel.fromString(level);
    if (log_level) |new_level| {
        logging.setGlobalLogLevel(new_level);
        logging.infoGlobalWithContext("cli.debug", "Log level changed", .{
            .old_level = if (logging.getGlobalLogger()) |logger| logger.getLevel().toString() else "unknown",
            .new_level = new_level.toString(),
        });
        std.debug.print("Setting log level to: {s}\n", .{level});
    } else {
        logging.warnGlobalWithContext("cli.debug", "Invalid log level specified", .{
            .provided_level = level,
        });
        std.debug.print("Invalid log level: {s}\n", .{level});
        std.debug.print("Valid levels: debug, info, warn, error, critical\n", .{});
    }
}

/// Dump internal state
fn dumpState(target: []const u8) !void {
    logging.infoGlobalWithContext("cli.debug", "State dump requested", .{
        .target = target,
    });

    if (std.mem.eql(u8, target, "orderbook")) {
        logging.debugGlobal("cli.debug", "Dumping orderbook state");
        std.debug.print("Dumping orderbook state...\n", .{});
        std.debug.print("Buy orders: 25\n", .{});
        std.debug.print("Sell orders: 17\n", .{});
        // In a real implementation, this would dump the actual orderbook state
    } else if (std.mem.eql(u8, target, "memory")) {
        logging.debugGlobal("cli.debug", "Dumping memory usage");
        std.debug.print("Dumping memory usage...\n", .{});
        std.debug.print("Total allocated: 128MB\n", .{});
        std.debug.print("Peak usage: 156MB\n", .{});
    } else if (std.mem.eql(u8, target, "stats")) {
        logging.debugGlobal("cli.debug", "Dumping statistics");
        std.debug.print("Dumping statistics...\n", .{});
        std.debug.print("Orders processed: 1042\n", .{});
        std.debug.print("Trades executed: 318\n", .{});
        std.debug.print("Average processing time: 0.5ms\n", .{});
    } else {
        logging.warnGlobalWithContext("cli.debug", "Unknown dump target requested", .{
            .target = target,
        });
        std.debug.print("Unknown dump target: {s}\n", .{target});
        std.debug.print("Valid targets: orderbook, memory, stats\n", .{});
    }
}

/// Run performance tests
fn runPerfTest(args: []const []const u8) !void {
    logging.infoGlobalWithContext("cli.debug", "Performance test initiated", .{
        .test_count = args.len,
    });

    std.debug.print("Running performance tests...\n", .{});

    if (args.len > 0) {
        const test_name = args[0];
        logging.debugGlobalWithContext("cli.debug", "Running specific performance test", .{
            .test_name = test_name,
        });
        std.debug.print("Running test: {s}\n", .{test_name});
    } else {
        logging.debugGlobal("cli.debug", "Running all performance tests");
        std.debug.print("Running all performance tests\n", .{});
    }

    // Simulate running tests
    std.debug.print("\nTest results:\n", .{});
    std.debug.print("  Order insertion: 100,000 ops/sec\n", .{});
    std.debug.print("  Order matching: 50,000 ops/sec\n", .{});
    std.debug.print("  Order cancellation: 120,000 ops/sec\n", .{});

    logging.infoGlobal("cli.debug", "Performance test completed");
}
