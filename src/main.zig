const std = @import("std");
const bench = @import("bench.zig");
const cli = @import("cli.zig");

pub fn main() !u8 {
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
    
    // Execute the CLI with the provided arguments
    cli.execute(&registry, arg_list.items) catch |err| {
        if (err == error.UnknownCommand) {
            return 1;
        }
        std.debug.print("Error executing command: {}\n", .{err});
        return 1;
    };
    
    return 0;
}
