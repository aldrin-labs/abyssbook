const std = @import("std");
const BlockchainClient = @import("../blockchain/client.zig").BlockchainClient;
const Orderbook = @import("../blockchain/client.zig").Orderbook;
const Order = @import("../blockchain/client.zig").Order;

/// OrderService provides an interface between CLI commands and blockchain data
pub const OrderService = struct {
    allocator: std.mem.Allocator,
    client: BlockchainClient,
    default_market: []const u8,

    /// Initialize a new order service
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !OrderService {
        const client = try BlockchainClient.init(allocator, api_key, base_url);

        return OrderService{
            .allocator = allocator,
            .client = client,
            .default_market = try allocator.dupe(u8, "SOL/USDC"),
        };
    }

    /// List orders from the blockchain
    pub fn listOrders(self: *OrderService, side: ?[]const u8) !void {
        // Get orderbook data from blockchain
        var orderbook = try self.client.getOrderbook(self.default_market);
        defer orderbook.deinit(self.allocator);

        // Display header
        std.debug.print("Listing orders", .{});
        if (side) |s| {
            std.debug.print(" (side: {s})", .{s});
        }
        std.debug.print("\n\n", .{});

        std.debug.print("+-----------+---------+-----------+------------+------------------+\n", .{});
        std.debug.print("| Order ID  | Side    | Price     | Size       | Owner           |\n", .{});
        std.debug.print("+-----------+---------+-----------+------------+------------------+\n", .{});

        // Display buy orders if requested
        if (side == null or std.mem.eql(u8, side.?, "buy")) {
            for (orderbook.bids) |bid| {
                // Truncate owner address for display
                const owner_short = if (bid.owner_address.len > 10)
                    bid.owner_address[0..10]
                else
                    bid.owner_address;

                std.debug.print("| {s:<9} | BUY     | {d:8.2}    | {d:8.2}    | {s:<16} |\n", .{ bid.order_id, bid.price, bid.size, owner_short });
            }
        }

        // Display sell orders if requested
        if (side == null or std.mem.eql(u8, side.?, "sell")) {
            for (orderbook.asks) |ask| {
                // Truncate owner address for display
                const owner_short = if (ask.owner_address.len > 10)
                    ask.owner_address[0..10]
                else
                    ask.owner_address;

                std.debug.print("| {s:<9} | SELL    | {d:8.2}    | {d:8.2}    | {s:<16} |\n", .{ ask.order_id, ask.price, ask.size, owner_short });
            }
        }

        std.debug.print("+-----------+---------+-----------+------------+------------------+\n", .{});
    }

    /// Place a new order
    pub fn placeOrder(self: *OrderService, side: []const u8, price_str: []const u8, size_str: []const u8) !void {
        // Validate side
        if (!std.mem.eql(u8, side, "buy") and !std.mem.eql(u8, side, "sell")) {
            std.debug.print("Error: Invalid side. Must be 'buy' or 'sell'\n", .{});
            return;
        }

        // Parse price and size as floats
        const price = try std.fmt.parseFloat(f64, price_str);
        const size = try std.fmt.parseFloat(f64, size_str);

        // Place order through blockchain client
        const order_id = try self.client.placeOrder(side, price, size);

        std.debug.print("Order placed successfully:\n", .{});
        std.debug.print("  Order ID: {s}\n", .{order_id});
        std.debug.print("  Side: {s}\n", .{side});
        std.debug.print("  Price: {d} USD\n", .{price});
        std.debug.print("  Size: {d} shares\n", .{size});
    }

    /// Cancel an existing order
    pub fn cancelOrder(self: *OrderService, order_id: []const u8) !void {
        try self.client.cancelOrder(order_id);
        std.debug.print("Order {s} cancelled successfully.\n", .{order_id});
    }

    /// Deinitialize the service and free resources
    pub fn deinit(self: *OrderService) void {
        self.client.deinit();
        self.allocator.free(self.default_market);
    }
};
