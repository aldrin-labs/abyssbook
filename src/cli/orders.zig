const std = @import("std");

/// Handle orders commands
pub fn handleOrdersCommand(args: []const []const u8) !void {
    if (args.len == 0) {
        // Show orders help
        showOrdersHelp();
        return;
    }

    const subcommand = args[0];
    if (std.mem.eql(u8, subcommand, "list")) {
        try listOrders(if (args.len > 1) args[1] else null);
    } else if (std.mem.eql(u8, subcommand, "place")) {
        if (args.len < 4) {
            std.debug.print("Error: Insufficient arguments for place order\n", .{});
            std.debug.print("Usage: abyssbook orders place <buy|sell> <price> <size>\n", .{});
            return;
        }
        try placeOrder(args[1], args[2], args[3]);
    } else if (std.mem.eql(u8, subcommand, "cancel")) {
        if (args.len < 2) {
            std.debug.print("Error: Missing order ID\n", .{});
            std.debug.print("Usage: abyssbook orders cancel <order_id>\n", .{});
            return;
        }
        try cancelOrder(args[1]);
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

/// List orders in the orderbook
fn listOrders(side: ?[]const u8) !void {
    std.debug.print("Listing orders", .{});
    if (side) |s| {
        std.debug.print(" (side: {s})", .{s});
    }
    std.debug.print("\n\n", .{});
    
    // Display header
    std.debug.print("+-----------+---------+-----------+------------+------------------+\n", .{});
    std.debug.print("| Order ID  | Side    | Price     | Size       | Timestamp        |\n", .{});
    std.debug.print("+-----------+---------+-----------+------------+------------------+\n", .{});
    
    // Display mock orders
    if (side == null or std.mem.eql(u8, side.?, "buy")) {
        std.debug.print("| ord-1001  | BUY     | 100.50    | 5.0        | 2023-05-01 14:30 |\n", .{});
        std.debug.print("| ord-1002  | BUY     | 100.25    | 10.0       | 2023-05-01 14:29 |\n", .{});
        std.debug.print("| ord-1003  | BUY     | 100.00    | 15.0       | 2023-05-01 14:28 |\n", .{});
    }
    
    if (side == null or std.mem.eql(u8, side.?, "sell")) {
        std.debug.print("| ord-1004  | SELL    | 101.00    | 7.0        | 2023-05-01 14:27 |\n", .{});
        std.debug.print("| ord-1005  | SELL    | 101.25    | 9.0        | 2023-05-01 14:26 |\n", .{});
        std.debug.print("| ord-1006  | SELL    | 101.50    | 3.0        | 2023-05-01 14:25 |\n", .{});
    }
    
    std.debug.print("+-----------+---------+-----------+------------+------------------+\n", .{});
}

/// Place a new order
fn placeOrder(side: []const u8, price: []const u8, size: []const u8) !void {
    // Validate side
    if (!std.mem.eql(u8, side, "buy") and !std.mem.eql(u8, side, "sell")) {
        std.debug.print("Error: Invalid side. Must be 'buy' or 'sell'\n", .{});
        return;
    }
    
    // In a real implementation, we would validate price and size as numbers
    
    // Generate a mock order ID
    const order_id = "ord-1007";
    
    std.debug.print("Order placed successfully:\n", .{});
    std.debug.print("  Order ID: {s}\n", .{order_id});
    std.debug.print("  Side: {s}\n", .{side});
    std.debug.print("  Price: {s}\n", .{price});
    std.debug.print("  Size: {s}\n", .{size});
}

/// Cancel an existing order
fn cancelOrder(order_id: []const u8) !void {
    // In a real implementation, we would validate the order ID exists
    
    std.debug.print("Order {s} cancelled successfully.\n", .{order_id});
}
