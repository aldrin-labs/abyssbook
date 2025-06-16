const std = @import("std");
const bench = @import("bench.zig");
const cli = @import("cli.zig");
const logging = @import("logging.zig");

pub fn main() !u8 {
    // Initialize logging system first
    try logging.initGlobalLogger(std.heap.page_allocator, .INFO);
    defer logging.deinitGlobalLogger();
    
    logging.infoGlobal("main", "Abyssbook application starting");
    
    // Get command line arguments
    const args = std.process.args();
    
    // Initialize CLI
    var registry = cli.init();
    defer registry.deinit();
    
    // Convert args iterator to slice for easier handling
    var arg_list = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer arg_list.deinit();
    
    var args_iter = args;
    while (args_iter.next()) |arg| {
        try arg_list.append(arg);
    }
    
    // Log command execution for security monitoring
    if (arg_list.items.len > 1) {
        logging.infoGlobalWithContext("main", "Command executed", .{
            .command = arg_list.items[1],
            .total_args = arg_list.items.len,
        });
    } else {
        logging.infoGlobal("main", "No command provided, showing help");
    }
    
    // Execute the CLI with the provided arguments
    cli.execute(&registry, arg_list.items) catch |err| {
        logging.errorGlobalWithContext("main", "CLI execution failed", .{
            .error_name = @errorName(err),
        });
        
        if (err == error.UnknownCommand) {
            return 1;
        }
        std.debug.print("Error executing command: {}\n", .{err});
        return 1;
    };
    
    logging.infoGlobal("main", "Abyssbook application completed successfully");
    return 0;
}
