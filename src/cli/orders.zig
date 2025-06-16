const std = @import("std");
const EnhancedOrderService = @import("../services/enhanced_orders.zig").EnhancedOrderService;
const args_module = @import("args.zig");
const OrdersCommandArgs = args_module.OrdersCommandArgs;
const ArgParser = args_module.ArgParser;
const ArgError = args_module.ArgError;

/// Handle orders commands with blockchain integration
pub fn handleOrdersCommand(args: []const []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    
    // Initialize the enhanced order service with blockchain and wallet integration
    var order_service = try EnhancedOrderService.init(allocator);
    defer order_service.deinit();
    
    if (args.len == 0) {
        // Show orders help
        showOrdersHelp();
        return;
    }
    
    const subcommand = args[0];
    if (std.mem.eql(u8, subcommand, "list")) {
        // Parse list arguments
        var parser = try OrdersCommandArgs.listArgs(allocator);
        defer parser.deinit();
        
        // Set arguments from command line
        if (args.len > 1) {
            parser.args = args[1..];
        }
        
        try parser.parse();
        const side = parser.getString("side");
        try order_service.listOrders(side);
    } else if (std.mem.eql(u8, subcommand, "place")) {
        // Parse place arguments
        var parser = try OrdersCommandArgs.placeArgs(allocator);
        defer parser.deinit();
        
        // Set arguments from command line
        if (args.len > 1) {
            parser.args = args[1..];
        } else {
            std.debug.print("Error: Insufficient arguments for place order\n", .{});
            std.debug.print("Usage: abyssbook orders place <buy|sell> <price> <size>\n", .{});
            std.debug.print("Usage: abyssbook orders place <buy|sell> <price in USD> <size in shares>\n", .{});
            return;
        }
        
        // Parse and validate arguments
        parser.parse() catch |err| {
            switch (err) {
                ArgError.MissingRequiredArgument => {
                    std.debug.print("Error: Missing required arguments for place order\n", .{});
                    std.debug.print("Usage: abyssbook orders place <buy|sell> <price in USD> <size in shares>\n", .{});
                    return;
                },
                else => return err,
            }
        };
        
        const side = try parser.getStringOrError("side");
        const price = try parser.getStringOrError("price");
        const size = try parser.getStringOrError("size");
        
        try order_service.placeOrder(side, price, size);
    } else if (std.mem.eql(u8, subcommand, "cancel")) {
        // Parse cancel arguments
        var parser = try OrdersCommandArgs.cancelArgs(allocator);
        defer parser.deinit();
        
        // Set arguments from command line
        if (args.len > 1) {
            parser.args = args[1..];
        } else {
            std.debug.print("Error: Missing order ID\n", .{});
            std.debug.print("Usage: abyssbook orders cancel <order_id>\n", .{});
            return;
        }
        
        // Parse and validate arguments
        parser.parse() catch |err| {
            switch (err) {
                ArgError.MissingRequiredArgument => {
                    std.debug.print("Error: Missing order ID\n", .{});
                    std.debug.print("Usage: abyssbook orders cancel <order_id>\n", .{});
                    return;
                },
                else => return err,
            }
        };
        
        const order_id = try parser.getStringOrError("order_id");
        try order_service.cancelOrder(order_id);
    } else {
        std.debug.print("Unknown orders subcommand: {s}\n", .{subcommand});
        showOrdersHelp();
    }
}

/// Show orders command help
fn showOrdersHelp() void {
    std.debug.print("Abyssbook Orders Commands\n", .{});
    std.debug.print("=======================\n\n", .{});
    std.debug.print("Available subcommands:\n", .{});
    std.debug.print("  list [buy|sell]  - List all orders or filter by side\n", .{});
    std.debug.print("  place <buy|sell> <price in USD> <size in shares> - Place a new order\n", .{});
    std.debug.print("  cancel <order_id> - Cancel an existing order\n", .{});
}
