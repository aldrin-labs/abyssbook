const std = @import("std");
const commands = @import("cli/commands.zig");
const tui = @import("cli/tui.zig");
const logging = @import("logging.zig");
const InputSanitizer = @import("cli/input_sanitizer.zig").InputSanitizer;

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

    // Initialize input sanitizer
    var sanitizer = InputSanitizer.init(std.heap.page_allocator, .{
        .max_length = 2048,
        .allow_unicode = false, // Restrict for security
        .allow_special_chars = true,
        .strict_commands = true,
        .filter_sql_injection = true,
        .filter_path_traversal = true,
        .filter_script_injection = true,
    });

    const command_name = args[1];
    const command_args = if (args.len > 2) args[2..] else &[_][]const u8{};

    // Stage 1: Quick validation for performance
    if (!sanitizer.quickValidate(command_name)) {
        std.debug.print("Error: Command name failed security validation\n", .{});
        logging.errorGlobal("cli", "Command name blocked by security filter");
        return error.SecurityViolation;
    }

    // Stage 2: Full sanitization of command name
    var command_result = sanitizer.sanitize(command_name, .{
        .strict_commands = true,
        .allow_special_chars = false,
    }) catch |err| {
        std.debug.print("Error: Command sanitization failed: {any}\n", .{err});
        logging.errorGlobal("cli", "Command sanitization error");
        return err;
    };
    defer command_result.deinit(std.heap.page_allocator);

    if (command_result.security_level == .BLOCKED) {
        std.debug.print("Error: Command blocked by security filter\n", .{});
        for (command_result.blocked_patterns.items) |pattern| {
            std.debug.print("  Blocked: {s}\n", .{pattern});
        }
        logging.errorGlobal("cli", "Command execution blocked by security filter");
        return error.SecurityViolation;
    }

    // Log security warnings
    if (command_result.warnings.items.len > 0) {
        for (command_result.warnings.items) |warning| {
            logging.warnGlobalWithContext("cli", "Command security warning", .{
                .warning = warning,
                .command = command_name,
            });
        }
    }

    // Stage 3: Sanitize command arguments
    var sanitized_args = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer {
        for (sanitized_args.items) |arg| {
            std.heap.page_allocator.free(arg);
        }
        sanitized_args.deinit();
    }

    for (command_args) |arg| {
        if (!sanitizer.quickValidate(arg)) {
            std.debug.print("Warning: Argument filtered by security: {s}\n", .{arg});
            continue; // Skip dangerous arguments
        }

        var arg_result = sanitizer.sanitize(arg, .{
            .allow_special_chars = true,
            .allow_unicode = false,
        }) catch |err| {
            std.debug.print("Warning: Argument sanitization failed: {any}\n", .{err});
            continue;
        };
        defer arg_result.deinit(std.heap.page_allocator);

        if (arg_result.security_level == .BLOCKED) {
            std.debug.print("Warning: Argument blocked: {s}\n", .{arg});
            for (arg_result.blocked_patterns.items) |pattern| {
                logging.warnGlobalWithContext("cli", "Argument blocked", .{
                    .pattern = pattern,
                    .arg = arg,
                });
            }
            continue;
        }

        try sanitized_args.append(try std.heap.page_allocator.dupe(u8, arg_result.cleaned_input));
    }

    // Validate command name is not empty after sanitization
    if (command_result.cleaned_input.len == 0) {
        std.debug.print("Error: Empty command name after sanitization\n", .{});
        logging.errorGlobal("cli", "Empty command name after sanitization");
        return error.EmptyCommand;
    }

    std.debug.print("Executing sanitized command: {s} with {d} args\n", .{ command_result.cleaned_input, sanitized_args.items.len });

    // Log command execution for security monitoring with sanitized data
    const escaped_command = sanitizer.escapeForLogging(command_result.cleaned_input) catch command_result.cleaned_input;
    defer if (escaped_command.ptr != command_result.cleaned_input.ptr) std.heap.page_allocator.free(escaped_command);

    logging.infoGlobalWithContext("cli", "CLI command execution", .{
        .command = escaped_command,
        .arg_count = sanitized_args.items.len,
        .security_level = @tagName(command_result.security_level),
    });

    registry.executeCommand(command_result.cleaned_input, sanitized_args.items) catch |err| {
        std.debug.print("Command execution failed: {s} -> {any}\n", .{ command_result.cleaned_input, err });
        logging.errorGlobalWithContext("cli", "Command execution failed", .{
            .command = escaped_command,
            .error_name = @errorName(err),
        });

        // Provide more detailed error information
        switch (err) {
            error.UnknownCommand => {
                std.debug.print("Command '{s}' not found. Available commands:\n", .{command_result.cleaned_input});
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
