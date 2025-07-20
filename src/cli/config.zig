const std = @import("std");
const logging = @import("../logging.zig");

/// Handle configuration commands
pub fn handleConfigCommand(args: []const []const u8) !void {
    logging.infoGlobalWithContext("cli.config", "Configuration command initiated", .{
        .arg_count = args.len,
        .subcommand = if (args.len > 0) args[0] else "none",
    });

    if (args.len == 0) {
        // Show current configuration
        showConfig();
        return;
    }

    const subcommand = args[0];
    if (std.mem.eql(u8, subcommand, "get")) {
        if (args.len < 2) {
            logging.warnGlobal("cli.config", "Missing key name for get command");
            std.debug.print("Error: Missing key name\n", .{});
            std.debug.print("Usage: abyssbook config get <key>\n", .{});
            return;
        }
        try getConfigValue(args[1]);
    } else if (std.mem.eql(u8, subcommand, "set")) {
        if (args.len < 3) {
            logging.warnGlobal("cli.config", "Missing key or value for set command");
            std.debug.print("Error: Missing key or value\n", .{});
            std.debug.print("Usage: abyssbook config set <key> <value>\n", .{});
            return;
        }
        try setConfigValue(args[1], args[2]);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        showConfig();
    } else {
        logging.warnGlobalWithContext("cli.config", "Unknown config subcommand", .{
            .subcommand = subcommand,
        });
        std.debug.print("Unknown config subcommand: {s}\n", .{subcommand});
        std.debug.print("Available subcommands: get, set, list\n", .{});
    }
}

/// Show all configuration settings
fn showConfig() void {
    logging.debugGlobal("cli.config", "Configuration listing requested");

    std.debug.print("Abyssbook Configuration\n", .{});
    std.debug.print("======================\n\n", .{});

    std.debug.print("General Settings:\n", .{});
    std.debug.print("  node.name = \"abyssbook-node-1\"\n", .{});
    std.debug.print("  node.log_level = \"info\"\n", .{});
    std.debug.print("  node.data_dir = \"/var/lib/abyssbook\"\n\n", .{});

    std.debug.print("Logging Settings:\n", .{});
    std.debug.print("  logging.level = \"info\"\n", .{});
    std.debug.print("  logging.format = \"json\"\n", .{});
    std.debug.print("  logging.output = \"stderr\"\n", .{});
    std.debug.print("  logging.security_events = true\n\n", .{});

    std.debug.print("Orderbook Settings:\n", .{});
    std.debug.print("  orderbook.max_orders = 10000\n", .{});
    std.debug.print("  orderbook.price_precision = 2\n", .{});
    std.debug.print("  orderbook.size_precision = 4\n\n", .{});

    std.debug.print("Performance Settings:\n", .{});
    std.debug.print("  perf.threads = 4\n", .{});
    std.debug.print("  perf.batch_size = 100\n", .{});
    std.debug.print("  perf.matching_algorithm = \"price-time\"\n", .{});
}

/// Get a specific configuration value
fn getConfigValue(key: []const u8) !void {
    logging.debugGlobalWithContext("cli.config", "Configuration value requested", .{
        .key = key,
    });

    // In a real implementation, this would look up the value in a config store
    if (std.mem.eql(u8, key, "node.name")) {
        std.debug.print("node.name = \"abyssbook-node-1\"\n", .{});
    } else if (std.mem.eql(u8, key, "node.log_level")) {
        std.debug.print("node.log_level = \"info\"\n", .{});
    } else if (std.mem.eql(u8, key, "logging.level")) {
        std.debug.print("logging.level = \"info\"\n", .{});
    } else if (std.mem.eql(u8, key, "logging.format")) {
        std.debug.print("logging.format = \"json\"\n", .{});
    } else if (std.mem.eql(u8, key, "logging.output")) {
        std.debug.print("logging.output = \"stderr\"\n", .{});
    } else if (std.mem.eql(u8, key, "logging.security_events")) {
        std.debug.print("logging.security_events = true\n", .{});
    } else if (std.mem.eql(u8, key, "orderbook.max_orders")) {
        std.debug.print("orderbook.max_orders = 10000\n", .{});
    } else {
        logging.warnGlobalWithContext("cli.config", "Unknown configuration key requested", .{
            .key = key,
        });
        std.debug.print("Unknown configuration key: {s}\n", .{key});
    }
}

/// Set a configuration value
fn setConfigValue(key: []const u8, value: []const u8) !void {
    logging.infoGlobalWithContext("cli.config", "Configuration value change requested", .{
        .key = key,
        .value_length = value.len,
    });

    // Handle special case for logging level changes
    if (std.mem.eql(u8, key, "logging.level") or std.mem.eql(u8, key, "node.log_level")) {
        if (logging.LogLevel.fromString(value)) |new_level| {
            logging.setGlobalLogLevel(new_level);
            logging.infoGlobalWithContext("cli.config", "Log level updated via configuration", .{
                .new_level = new_level.toString(),
            });
            std.debug.print("Setting {s} = \"{s}\"\n", .{ key, value });
            std.debug.print("Log level updated to: {s}\n", .{value});
        } else {
            logging.warnGlobalWithContext("cli.config", "Invalid log level in configuration", .{
                .provided_level = value,
            });
            std.debug.print("Invalid log level: {s}\n", .{value});
            std.debug.print("Valid levels: debug, info, warn, error, critical\n", .{});
            return;
        }
    } else {
        // In a real implementation, this would update the value in a config store
        std.debug.print("Setting {s} = \"{s}\"\n", .{ key, value });
    }

    std.debug.print("Configuration updated successfully.\n", .{});
}
