const std = @import("std");
const OrderService = @import("../services/orders.zig").OrderService;
const BlockchainConfig = @import("../config/blockchain.zig").BlockchainConfig;
const Wallet = @import("../blockchain/wallet.zig").Wallet;
const logging = @import("../logging.zig");

/// Enhanced order service with wallet integration
pub const EnhancedOrderService = struct {
    allocator: std.mem.Allocator,
    order_service: OrderService,
    wallet: Wallet,
    
    /// Initialize a new enhanced order service
    pub fn init(allocator: std.mem.Allocator) !EnhancedOrderService {
        logging.infoGlobal("service.orders", "Initializing enhanced order service");
        
        // Load blockchain configuration
        var config = try BlockchainConfig.load(allocator);
        defer config.deinit(allocator);
        
        logging.debugGlobal("service.orders", "Blockchain configuration loaded");
        
        // Initialize order service
        const order_service = try OrderService.init(
            allocator,
            config.api_key,
            config.base_url
        );
        
        // Initialize wallet
        const wallet = try Wallet.initRandom(allocator);
        
        logging.infoGlobal("service.orders", "Enhanced order service initialized successfully");
        
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
        logging.infoGlobalWithContext("service.orders", "Order placement request", .{
            .side = side,
            .price_length = price_str.len,
            .size_length = size_str.len,
        });

        // Validate side
        if (!std.mem.eql(u8, side, "buy") and !std.mem.eql(u8, side, "sell")) {
            logging.warnGlobalWithContext("service.orders", "Invalid order side provided", .{
                .provided_side = side,
            });
            std.debug.print("Error: Invalid side. Must be 'buy' or 'sell'\n", .{});
            return;
        }
        
        // Parse price and size as floats
        const price = std.fmt.parseFloat(f64, price_str) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to parse price", .{
                .price_string = price_str,
                .error_name = @errorName(err),
            });
            std.debug.print("Error: Invalid price format: {s}\n", .{price_str});
            return;
        };
        
        const size = std.fmt.parseFloat(f64, size_str) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to parse size", .{
                .size_string = size_str,
                .error_name = @errorName(err),
            });
            std.debug.print("Error: Invalid size format: {s}\n", .{size_str});
            return;
        };
        
        // Validate business logic
        if (price <= 0.0) {
            logging.warnGlobalWithContext("service.orders", "Invalid price value", .{
                .price = price,
            });
            std.debug.print("Error: Price must be positive\n", .{});
            return;
        }
        
        if (size <= 0.0) {
            logging.warnGlobalWithContext("service.orders", "Invalid size value", .{
                .size = size,
            });
            std.debug.print("Error: Size must be positive\n", .{});
            return;
        }
        
        // Sign the transaction with the wallet
        logging.debugGlobal("service.orders", "Signing order transaction");
        const signature = self.wallet.signPlaceOrderTransaction(
            self.order_service.default_market,
            side,
            price,
            size
        ) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to sign order transaction", .{
                .error_name = @errorName(err),
            });
            std.debug.print("Error: Failed to sign transaction\n", .{});
            return;
        };
        defer self.allocator.free(signature);
        
        // Log successful order placement
        logging.infoGlobalWithContext("service.orders", "Order placed successfully", .{
            .side = side,
            .price = price,
            .size = size,
            .wallet_address = self.wallet.getAddress(),
        });
        
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
        logging.infoGlobalWithContext("service.orders", "Order cancellation request", .{
            .order_id = order_id,
        });

        // Basic validation
        if (order_id.len == 0) {
            logging.warnGlobal("service.orders", "Empty order ID provided for cancellation");
            std.debug.print("Error: Order ID cannot be empty\n", .{});
            return;
        }

        // Sign the transaction with the wallet
        logging.debugGlobal("service.orders", "Signing cancel order transaction");
        const signature = self.wallet.signCancelOrderTransaction(
            self.order_service.default_market,
            order_id
        ) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to sign cancel transaction", .{
                .order_id = order_id,
                .error_name = @errorName(err),
            });
            std.debug.print("Error: Failed to sign cancel transaction\n", .{});
            return;
        };
        defer self.allocator.free(signature);
        
        // Log successful cancellation
        logging.infoGlobalWithContext("service.orders", "Order cancelled successfully", .{
            .order_id = order_id,
            .wallet_address = self.wallet.getAddress(),
        });
        
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
