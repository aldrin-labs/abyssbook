const std = @import("std");
const tui = @import("tui.zig");
const status = @import("status.zig");
const config = @import("config.zig");
const orders = @import("orders.zig");
const debug = @import("debug.zig");
const args = @import("args.zig");

/// Global registry reference for help command access
var registry_ref: ?*CommandRegistry = null;

/// Function type for command execution
pub const CommandFn = *const fn (args: []const []const u8) anyerror!void;

/// Command structure representing a CLI command
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    execute: CommandFn,
};

/// Registry for storing and executing commands
pub const CommandRegistry = struct {
    commands: std.StringHashMap(Command),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandRegistry {
        var registry = CommandRegistry{
            .commands = std.StringHashMap(Command).init(allocator),
            .allocator = allocator,
        };
        // Store reference for help command access
        registry_ref = &registry;
        return registry;
    }

    pub fn deinit(self: *CommandRegistry) void {
        self.commands.deinit();
        // Clear registry reference if it points to this instance
        if (registry_ref == self) {
            registry_ref = null;
        }
    }

    pub fn register(self: *CommandRegistry, command: Command) void {
        self.commands.put(command.name, command) catch |err| {
            std.debug.print("Failed to register command: {s}, error: {}\n", .{ command.name, err });
        };
    }

    pub fn executeCommand(self: *CommandRegistry, name: []const u8, args: []const []const u8) !void {
        if (self.commands.get(name)) |command| {
            try command.execute(args);
        } else {
            std.debug.print("Unknown command: {s}\n", .{name});
            try self.executeCommand("help", &[_][]const u8{});
            return error.UnknownCommand;
        }
    }

    pub fn listCommands(self: *CommandRegistry) !void {
        var it = self.commands.iterator();
        while (it.next()) |entry| {
            const cmd = entry.value_ptr.*;
            std.debug.print("{s:<15} - {s}\n", .{ cmd.name, cmd.description });
        }
    }
};

/// Help command implementation with registry access
fn executeHelp(args: []const []const u8) !void {
    // Store registry reference in thread-local storage for access
    if (registry_ref == null) {
        std.debug.print("Error: Command registry not initialized\n", .{});
        return;
    }
    
    std.debug.print("Abyssbook Node Management CLI\n\n", .{});
    std.debug.print("Usage: abyssbook <command> [options]\n\n", .{});
    std.debug.print("Available commands:\n", .{});
    
    // If a specific command was requested, show its usage
    if (args.len > 0) {
        const command_name = args[0];
        if (registry_ref.?.commands.get(command_name)) |command| {
            std.debug.print("\n{s} - {s}\n", .{ command.name, command.description });
            std.debug.print("Usage: {s}\n\n", .{command.usage});
            return;
        } else {
            std.debug.print("Unknown command: {s}\n\n", .{command_name});
        }
    }
    
    // List all commands with descriptions using the registry
    try registry_ref.?.listCommands();
}

/// TUI command implementation
fn executeTui(args: []const []const u8) !void {
    _ = args; // Unused for now
    try tui.run();
}

/// Status command implementation
fn executeStatus(args: []const []const u8) !void {
    _ = args; // Unused for now
    try status.showStatus();
}

/// Config command implementation
fn executeConfig(args: []const []const u8) !void {
    try config.handleConfigCommand(args);
}

/// Orders command implementation
fn executeOrders(args: []const []const u8) !void {
    try orders.handleOrdersCommand(args);
}

/// Debug command implementation
fn executeDebug(args: []const []const u8) !void {
    try debug.handleDebugCommand(args);
}

// Command factory functions
pub fn helpCommand() Command {
    return .{
        .name = "help",
        .description = "Display help information",
        .usage = "abyssbook help [command]",
        .execute = executeHelp,
    };
}

pub fn tuiCommand() Command {
    return .{
        .name = "tui",
        .description = "Launch the text-based user interface",
        .usage = "abyssbook tui",
        .execute = executeTui,
    };
}

pub fn statusCommand() Command {
    return .{
        .name = "status",
        .description = "Show node status and performance metrics",
        .usage = "abyssbook status",
        .execute = executeStatus,
    };
}

pub fn configCommand() Command {
    return .{
        .name = "config",
        .description = "View or modify configuration settings",
        .usage = "abyssbook config [get|set] [key] [value]",
        .execute = executeConfig,
    };
}

pub fn ordersCommand() Command {
    return .{
        .name = "orders",
        .description = "Manage orders in the orderbook",
        .usage = "abyssbook orders [list|place|cancel] [options]",
        .execute = executeOrders,
    };
}

pub fn debugCommand() Command {
    return .{
        .name = "debug",
        .description = "Debug and diagnostic commands",
        .usage = "abyssbook debug [options]",
        .execute = executeDebug,
    };
}
