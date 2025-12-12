const std = @import("std");
const bench = @import("bench.zig");
const cli = @import("cli.zig");
const logging = @import("logging.zig");

pub fn main() !u8 {
    // Initialize logging system first
    try logging.initGlobalLogger(std.heap.page_allocator, .INFO);
    defer logging.deinitGlobalLogger();

    logging.infoGlobal("main", "Abyssbook application starting");

    // Get command line arguments with error handling
    const args = std.process.args();

    // Initialize CLI with error handling
    var registry = cli.init();
    defer registry.deinit();
    
    // Set global registry reference for help command access
    registry.setGlobalRef();

    // Convert args iterator to slice for easier handling with error handling
    var arg_list: [32][]const u8 = undefined;
    var arg_count: usize = 0;
    var args_iter = args;
    while (args_iter.next()) |arg| {
        if (arg_count >= arg_list.len) {
            std.debug.print("Error: Too many command line arguments (max {d})\n", .{arg_list.len});
            return 1;
        }
        arg_list[arg_count] = arg;
        arg_count += 1;
    }

    // Log command execution for security monitoring with safety checks
    if (arg_count > 1) {
        const command = if (arg_count > 1) arg_list[1] else "none";
        logging.infoGlobalWithContext("main", "Command executed", .{
            .command = command,
            .total_args = arg_count,
        });
    } else {
        logging.infoGlobal("main", "No command provided, showing help");
    }

    // Execute the CLI with the provided arguments with comprehensive error handling
    cli.execute(&registry, arg_list[0..arg_count]) catch |err| {
        // Enhanced error reporting to prevent silent failures
        const error_name = @errorName(err);
        std.debug.print("Error executing command: {any} ({s})\n", .{ err, error_name });

        logging.errorGlobalWithContext("main", "CLI execution failed", .{
            .error_name = error_name,
            .command = if (arg_count > 1) arg_list[1] else "none",
            .total_args = arg_count,
        });

        // Provide specific error messages for common issues
        switch (err) {
            error.UnknownCommand => {
                std.debug.print("Unknown command provided. Use 'abyssbook help' for available commands.\n", .{});
                return 1;
            },
            error.OutOfMemory => {
                std.debug.print("Out of memory. Please try with smaller inputs or check system resources.\n", .{});
                return 1;
            },
            error.InvalidArgument => {
                std.debug.print("Invalid argument provided. Check command syntax with 'abyssbook help <command>'.\n", .{});
                return 1;
            },
            else => {
                std.debug.print("Unexpected error occurred: {any}\n", .{err});
                return 1;
            },
        }
    };

    logging.infoGlobal("main", "Abyssbook application completed successfully");
    return 0;
}
