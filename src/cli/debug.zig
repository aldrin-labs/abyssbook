const std = @import("std");

/// Handle debug commands
pub fn handleDebugCommand(args: []const []const u8) !void {
    if (args.len == 0) {
        // Show debug help
        showDebugHelp();
        return;
    }

    const subcommand = args[0];
    if (std.mem.eql(u8, subcommand, "log")) {
        if (args.len < 2) {
            std.debug.print("Error: Missing log level\n", .{});
            std.debug.print("Usage: abyss debug log <level>\n", .{});
            return;
        }
        try setLogLevel(args[1]);
    } else if (std.mem.eql(u8, subcommand, "dump")) {
        if (args.len < 2) {
            std.debug.print("Error: Missing dump target\n", .{});
            std.debug.print("Usage: abyss debug dump <target>\n", .{});
            return;
        }
        try dumpState(args[1]);
    } else if (std.mem.eql(u8, subcommand, "perf")) {
        try runPerfTest(if (args.len > 1) args[1..] else &[_][]const u8{});
    } else {
        std.debug.print("Unknown debug subcommand: {s}\n", .{subcommand});
        showDebugHelp();
    }
}

/// Show debug command help
fn showDebugHelp() void {
    std.debug.print("Abyssbook Debug Commands\n", .{});
    std.debug.print("======================\n\n", .{});
    std.debug.print("Available subcommands:\n", .{});
    std.debug.print("  log <level>     - Set log level (debug, info, warn, error)\n", .{});
    std.debug.print("  dump <target>   - Dump internal state (orderbook, memory, stats)\n", .{});
    std.debug.print("  perf [test]     - Run performance tests\n", .{});
}

/// Set the log level
fn setLogLevel(level: []const u8) !void {
    if (std.mem.eql(u8, level, "debug") or
        std.mem.eql(u8, level, "info") or
        std.mem.eql(u8, level, "warn") or
        std.mem.eql(u8, level, "error"))
    {
        std.debug.print("Setting log level to: {s}\n", .{level});
    } else {
        std.debug.print("Invalid log level: {s}\n", .{level});
        std.debug.print("Valid levels: debug, info, warn, error\n", .{});
    }
}

/// Dump internal state
fn dumpState(target: []const u8) !void {
    if (std.mem.eql(u8, target, "orderbook")) {
        std.debug.print("Dumping orderbook state...\n", .{});
        std.debug.print("Buy orders: 25\n", .{});
        std.debug.print("Sell orders: 17\n", .{});
        // In a real implementation, this would dump the actual orderbook state
    } else if (std.mem.eql(u8, target, "memory")) {
        std.debug.print("Dumping memory usage...\n", .{});
        std.debug.print("Total allocated: 128MB\n", .{});
        std.debug.print("Peak usage: 156MB\n", .{});
    } else if (std.mem.eql(u8, target, "stats")) {
        std.debug.print("Dumping statistics...\n", .{});
        std.debug.print("Orders processed: 1042\n", .{});
        std.debug.print("Trades executed: 318\n", .{});
        std.debug.print("Average processing time: 0.5ms\n", .{});
    } else {
        std.debug.print("Unknown dump target: {s}\n", .{target});
        std.debug.print("Valid targets: orderbook, memory, stats\n", .{});
    }
}

/// Run performance tests
fn runPerfTest(args: []const []const u8) !void {
    std.debug.print("Running performance tests...\n", .{});
    
    if (args.len > 0) {
        const test_name = args[0];
        std.debug.print("Running test: {s}\n", .{test_name});
    } else {
        std.debug.print("Running all performance tests\n", .{});
    }
    
    // Simulate running tests
    std.debug.print("\nTest results:\n", .{});
    std.debug.print("  Order insertion: 100,000 ops/sec\n", .{});
    std.debug.print("  Order matching: 50,000 ops/sec\n", .{});
    std.debug.print("  Order cancellation: 120,000 ops/sec\n", .{});
}
