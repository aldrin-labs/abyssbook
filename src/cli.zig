const std = @import("std");
const commands = @import("cli/commands.zig");
const tui = @import("cli/tui.zig");

pub const Command = commands.Command;
pub const CommandRegistry = commands.CommandRegistry;

/// Initialize the CLI and register all available commands
pub fn init() CommandRegistry {
    var registry = CommandRegistry.init(std.heap.page_allocator);
    
    // Register all commands
    registry.register(commands.helpCommand());
    registry.register(commands.tuiCommand());
    registry.register(commands.statusCommand());
    registry.register(commands.configCommand());
    registry.register(commands.ordersCommand());
    registry.register(commands.debugCommand());
    
    return registry;
}

/// Parse command line arguments and execute the appropriate command
pub fn execute(registry: *CommandRegistry, args: []const []const u8) !void {
    if (args.len <= 1) {
        // No command provided, show help
        try registry.executeCommand("help", &[_][]const u8{});
        return;
    }

    const command_name = args[1];
    const command_args = if (args.len > 2) args[2..] else &[_][]const u8{};

    try registry.executeCommand(command_name, command_args);
}
