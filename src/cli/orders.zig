const std = @import("std");
const EnhancedOrderService = @import("../services/enhanced_orders.zig").EnhancedOrderService;

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
        try order_service.listOrders(if (args.len > 1) args[1] else null);
    } else if (std.mem.eql(u8, subcommand, "place")) {
        if (args.len < 4) {
            std.debug.print("Error: Insufficient arguments for place order\n", .{});
            std.debug.print("Usage: abyssbook orders place <buy|sell> <price> <size>\n", .{});
            return;
        }
        try order_service.placeOrder(args[1], args[2], args[3]);
    } else if (std.mem.eql(u8, subcommand, "cancel")) {
        if (args.len < 2) {
            std.debug.print("Error: Missing order ID\n", .{});
            std.debug.print("Usage: abyssbook orders cancel <order_id>\n", .{});
            return;
        }
        try order_service.cancelOrder(args[1]);
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
    std.debug.print("  place <buy|sell> <price> <size> - Place a new order\n", .{});
    std.debug.print("  cancel <order_id> - Cancel an existing order\n", .{});
}
