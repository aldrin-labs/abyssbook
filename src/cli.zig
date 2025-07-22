const std = @import("std");
const commands = @import("cli/commands.zig");
const tui = @import("cli/tui.zig");
const logging = @import("logging.zig");

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
    // Add debugging for CLI execution with safety checks
    std.debug.print("CLI execute called with {d} args\n", .{args.len});

    if (args.len <= 1) {
        // No command provided, show help
        logging.debugGlobal("cli", "No command provided, showing help");
        std.debug.print("Showing help for empty command\n", .{});
        // Call help directly using executeCommand to avoid recursion issues
        registry.executeCommand("help", &[_][]const u8{}) catch |err| {
            std.debug.print("Error showing help: {any}\n", .{err});
            logging.errorGlobalWithContext("cli", "Failed to show help", .{
                .error_name = @errorName(err),
            });
            return err;
        };
        return;
    }

    const command_name = args[1];
    const command_args = if (args.len > 2) args[2..] else &[_][]const u8{};

    // Validate command name is not empty
    if (command_name.len == 0) {
        std.debug.print("Error: Empty command name\n", .{});
        logging.errorGlobal("cli", "Empty command name provided");
        return error.EmptyCommand;
    }

    std.debug.print("Executing command: {s} with {d} args\n", .{ command_name, command_args.len });

    // Log command execution for security monitoring
    logging.infoGlobalWithContext("cli", "CLI command execution", .{
        .command = command_name,
        .arg_count = command_args.len,
    });

    registry.executeCommand(command_name, command_args) catch |err| {
        std.debug.print("Command execution failed: {s} -> {any}\n", .{ command_name, err });
        logging.errorGlobalWithContext("cli", "Command execution failed", .{
            .command = command_name,
            .error_name = @errorName(err),
        });

        // Provide more detailed error information
        switch (err) {
            error.UnknownCommand => {
                std.debug.print("Command '{s}' not found. Available commands:\n", .{command_name});
                registry.listCommands() catch {
                    std.debug.print("Error: Could not list available commands\n", .{});
                };
            },
            else => {},
        }

        return err;
    };

    std.debug.print("Command completed successfully: {s}\n", .{command_name});
    logging.debugGlobalWithContext("cli", "Command completed successfully", .{
        .command = command_name,
    });
}
