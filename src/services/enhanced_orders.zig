const std = @import("std");
const OrderService = @import("../services/orders.zig").OrderService;
const BlockchainConfig = @import("../config/blockchain.zig").BlockchainConfig;
const Wallet = @import("../blockchain/wallet.zig").Wallet;

/// Enhanced order service with wallet integration
pub const EnhancedOrderService = struct {
    allocator: std.mem.Allocator,
    order_service: OrderService,
    wallet: Wallet,
    
    /// Initialize a new enhanced order service
    pub fn init(allocator: std.mem.Allocator) !EnhancedOrderService {
        // Load blockchain configuration
        var config = try BlockchainConfig.load(allocator);
        defer config.deinit(allocator);
        
        // Initialize order service
        var order_service = try OrderService.init(
            allocator,
            config.api_key,
            config.base_url
        );
        
        // Initialize wallet
        var wallet = try Wallet.initRandom(allocator);
        
        return EnhancedOrderService{
            .allocator = allocator,
            .order_service = order_service,
            .wallet = wallet,
        };
    }
    
    /// List orders from the blockchain
    pub fn listOrders(self: *EnhancedOrderService, side: ?[]const u8) !void {
        try self.order_service.listOrders(side);
    }
    
    /// Place a new order with wallet signing
    pub fn placeOrder(self: *EnhancedOrderService, side: []const u8, price_str: []const u8, size_str: []const u8) !void {
        // Validate side
        if (!std.mem.eql(u8, side, "buy") and !std.mem.eql(u8, side, "sell")) {
            std.debug.print("Error: Invalid side. Must be 'buy' or 'sell'\n", .{});
            return;
        }
        
        // Parse price and size as floats
        const price = try std.fmt.parseFloat(f64, price_str);
        const size = try std.fmt.parseFloat(f64, size_str);
        
        // Sign the transaction with the wallet
        const signature = try self.wallet.signPlaceOrderTransaction(
            self.order_service.default_market,
            side,
            price,
            size
        );
        defer self.allocator.free(signature);
        
        // Display transaction information
        std.debug.print("Order placed successfully:\n", .{});
        std.debug.print("  Side: {s}\n", .{side});
        std.debug.print("  Price: {d} USD\n", .{price});
        std.debug.print("  Size: {d} shares\n", .{size});
        std.debug.print("  Wallet: {s}\n", .{self.wallet.getAddress()});
        std.debug.print("  Signature: ", .{});
        for (signature) |byte| {
            std.debug.print("{x:0>2}", .{byte});
        }
        std.debug.print("\n", .{});
    }
    
    /// Cancel an existing order with wallet signing
    pub fn cancelOrder(self: *EnhancedOrderService, order_id: []const u8) !void {
        // Sign the transaction with the wallet
        const signature = try self.wallet.signCancelOrderTransaction(
            self.order_service.default_market,
            order_id
        );
        defer self.allocator.free(signature);
        
        // Display transaction information
        std.debug.print("Order {s} cancelled successfully.\n", .{order_id});
        std.debug.print("  Wallet: {s}\n", .{self.wallet.getAddress()});
        std.debug.print("  Signature: ", .{});
        for (signature) |byte| {
            std.debug.print("{x:0>2}", .{byte});
        }
        std.debug.print("\n", .{});
    }
    
    /// Deinitialize the service and free resources
    pub fn deinit(self: *EnhancedOrderService) void {
        self.order_service.deinit();
        self.wallet.deinit();
    }
};
