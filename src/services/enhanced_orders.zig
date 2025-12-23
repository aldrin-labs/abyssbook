const std = @import("std");
const OrderService = @import("../services/orders.zig").OrderService;
const BlockchainConfig = @import("../config/blockchain.zig").BlockchainConfig;
const Wallet = @import("../blockchain/wallet.zig").Wallet;
const logging = @import("../logging.zig");
const BlockchainError = @import("../blockchain/error.zig").BlockchainError;
const ErrorHandler = @import("../blockchain/error.zig").ErrorHandler;
const BlockchainConstants = @import("../blockchain/constants.zig").BlockchainConstants;
const Thread = std.Thread;

/// Enhanced order service with secure wallet integration and granular thread safety
pub const EnhancedOrderService = struct {
    allocator: std.mem.Allocator,
    order_service: OrderService,
    wallet: Wallet,
    
    // Granular locking for better performance
    read_mutex: Thread.Mutex,    // For read operations (list orders)
    write_mutex: Thread.Mutex,   // For write operations (place/cancel orders)
    config_mutex: Thread.Mutex,  // For configuration changes
    
    error_handler: ErrorHandler,
    operation_count: std.atomic.Value(u64),
    
    /// Initialize a new enhanced order service with security measures
    pub fn init(allocator: std.mem.Allocator) !EnhancedOrderService {
        logging.infoGlobal("service.orders", "Initializing secure enhanced order service");
        
        // Load blockchain configuration securely
        var config = BlockchainConfig.load(allocator) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to load blockchain configuration", .{
                .error_name = @errorName(err),
            });
            return err;
        };
        defer config.deinit(allocator);
        
        logging.debugGlobal("service.orders", "Blockchain configuration loaded securely");
        
        // Initialize order service with validation
        var order_service = OrderService.init(
            allocator,
            config.api_key,
            config.base_url
        ) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to initialize order service", .{
                .error_name = @errorName(err),
            });
            return err;
        };
        
        // Initialize wallet securely
        const wallet = Wallet.initRandom(allocator) catch |err| {
            order_service.deinit();
            logging.errorGlobalWithContext("service.orders", "Failed to initialize wallet", .{
                .error_name = @errorName(err),
            });
            return err;
        };
        
        // Initialize error handler with security-focused retry strategy
        const error_handler = ErrorHandler.init(
            BlockchainConstants.DEFAULT_ERROR_HANDLER_RETRIES, 
            BlockchainConstants.DEFAULT_ERROR_HANDLER_BASE_DELAY_MS
        );
        
        logging.infoGlobal("service.orders", "Secure enhanced order service initialized successfully");
        
        return EnhancedOrderService{
            .allocator = allocator,
            .order_service = order_service,
            .wallet = wallet,
            .read_mutex = Thread.Mutex{},
            .write_mutex = Thread.Mutex{},
            .config_mutex = Thread.Mutex{},
            .error_handler = error_handler,
            .operation_count = std.atomic.Value(u64).init(0),
        };
    }
    
    /// List orders from the blockchain with thread safety (read operation)
    pub fn listOrders(self: *EnhancedOrderService, side: ?[]const u8) !void {
        self.read_mutex.lock();
        defer self.read_mutex.unlock();
        
        _ = self.operation_count.fetchAdd(1, .monotonic);
        defer _ = self.operation_count.fetchSub(1, .monotonic);
        
        // Validate side parameter if provided
        if (side) |s| {
            if (!std.mem.eql(u8, s, "buy") and !std.mem.eql(u8, s, "sell")) {
                logging.warnGlobalWithContext("service.orders", "Invalid side filter provided", .{
                    .provided_side = s,
                });
                return BlockchainError.InvalidSide;
            }
        }
        
        // Execute with retry logic
        const ListOrdersContext = struct {
            service: *EnhancedOrderService,
            side: ?[]const u8,
        };
        
        const context = ListOrdersContext{
            .service = self,
            .side = side,
        };
        
        const listOrdersImpl = struct {
            fn execute(ctx: ListOrdersContext) BlockchainError!void {
                ctx.service.order_service.listOrders(ctx.side) catch |err| {
                    switch (err) {
                        // Map generic errors to blockchain errors
                        error.OutOfMemory => return BlockchainError.UnknownError,
                        else => return BlockchainError.ApiRequestFailed,
                    }
                };
            }
        }.execute;
        try self.error_handler.executeWithRetry(void, context, listOrdersImpl);
    }
    
    /// Place a new order with comprehensive security and validation (write operation)
    pub fn placeOrder(self: *EnhancedOrderService, side: []const u8, price_str: []const u8, size_str: []const u8) !void {
        self.write_mutex.lock();
        defer self.write_mutex.unlock();
        
        _ = self.operation_count.fetchAdd(1, .monotonic);
        defer _ = self.operation_count.fetchSub(1, .monotonic);
        
        logging.infoGlobalWithContext("service.orders", "Secure order placement request", .{
            .side = side,
            .price_length = price_str.len,
            .size_length = size_str.len,
        });

        // Input validation with security checks
        if (side.len == 0 or side.len > BlockchainConstants.MAX_SIDE_LENGTH) {
            logging.warnGlobalWithContext("service.orders", "Invalid side length", .{
                .side_length = side.len,
            });
            return BlockchainError.InvalidSide;
        }
        
        if (price_str.len == 0 or price_str.len > BlockchainConstants.MAX_PRICE_STRING_LENGTH) {
            logging.warnGlobalWithContext("service.orders", "Invalid price string length", .{
                .price_length = price_str.len,
            });
            return BlockchainError.InvalidPrice;
        }
        
        if (size_str.len == 0 or size_str.len > BlockchainConstants.MAX_SIZE_STRING_LENGTH) {
            logging.warnGlobalWithContext("service.orders", "Invalid size string length", .{
                .size_length = size_str.len,
            });
            return BlockchainError.InvalidSize;
        }

        // Validate side with security checks
        if (!std.mem.eql(u8, side, "buy") and !std.mem.eql(u8, side, "sell")) {
            logging.warnGlobalWithContext("service.orders", "Invalid order side provided", .{
                .provided_side = side,
            });
            return BlockchainError.InvalidSide;
        }
        
        // Parse and validate price with comprehensive error handling
        const price = std.fmt.parseFloat(f64, price_str) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to parse price", .{
                .price_string = price_str,
                .error_name = @errorName(err),
            });
            return BlockchainError.InvalidPrice;
        };

        const size = std.fmt.parseFloat(f64, size_str) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to parse size", .{
                .size_string = size_str,
                .error_name = @errorName(err),
            });
            return BlockchainError.InvalidSize;
        };
        
        // Comprehensive business logic validation
        if (price <= 0.0) {
            logging.warnGlobalWithContext("service.orders", "Non-positive price value", .{
                .price = price,
            });
            return BlockchainError.InvalidPrice;
        }

        if (size <= 0.0) {
            logging.warnGlobalWithContext("service.orders", "Non-positive size value", .{
                .size = size,
            });
            return BlockchainError.InvalidSize;
        }

        // Additional security checks
        if (price > BlockchainConstants.MAX_PRICE_VALUE) {
            logging.warnGlobalWithContext("service.orders", "Price exceeds maximum allowed", .{
                .price = price,
            });
            return BlockchainError.PriceTooHigh;
        }
        
        if (size > BlockchainConstants.MAX_SIZE_VALUE) {
            logging.warnGlobalWithContext("service.orders", "Size exceeds maximum allowed", .{
                .size = size,
            });
            return BlockchainError.SizeTooHigh;
        }
        
        if (std.math.isNan(price) or std.math.isInf(price)) {
            logging.warnGlobalWithContext("service.orders", "Invalid price value (NaN or Inf)", .{
                .price = price,
            });
            return BlockchainError.InvalidPriceValue;
        }
        
        if (std.math.isNan(size) or std.math.isInf(size)) {
            logging.warnGlobalWithContext("service.orders", "Invalid size value (NaN or Inf)", .{
                .size = size,
            });
            return BlockchainError.InvalidSizeValue;
        }
        
        // Sign the transaction with the wallet securely
        logging.debugGlobal("service.orders", "Signing order transaction securely");
        const signature = self.wallet.signPlaceOrderTransaction(
            self.order_service.default_market,
            side,
            price,
            size
        ) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to sign order transaction", .{
                .error_name = @errorName(err),
            });
            return BlockchainError.AuthenticationFailed;
        };
        defer {
            // Secure cleanup of signature
            @memset(@constCast(signature), 0);
            self.allocator.free(signature);
        }
        
        // Execute order placement with retry logic
        const PlaceOrderContext = struct {
            service: *EnhancedOrderService,
            side: []const u8,
            price: f64,
            size: f64,
            signature: []const u8,
        };
        
        const context = PlaceOrderContext{
            .service = self,
            .side = side,
            .price = price,
            .size = size,
            .signature = signature,
        };
        
        const placeOrderImpl = struct {
            fn execute(ctx: PlaceOrderContext) BlockchainError!void {
                const order_id = ctx.service.order_service.client.placeOrder(ctx.side, ctx.price, ctx.size) catch |err| {
                    switch (err) {
                        error.InvalidSide => return BlockchainError.InvalidSide,
                        error.InvalidPrice => return BlockchainError.InvalidPrice,
                        error.InvalidSize => return BlockchainError.InvalidSize,
                        error.PriceTooHigh => return BlockchainError.PriceTooHigh,
                        error.SizeTooHigh => return BlockchainError.SizeTooHigh,
                        error.InvalidPriceValue => return BlockchainError.InvalidPriceValue,
                        error.InvalidSizeValue => return BlockchainError.InvalidSizeValue,
                        error.OutOfMemory => return BlockchainError.UnknownError,
                        else => return BlockchainError.ApiRequestFailed,
                    }
                };
                defer ctx.service.allocator.free(order_id);
                
                // Log successful order placement
                logging.infoGlobalWithContext("service.orders", "Order placed successfully", .{
                    .order_id = order_id,
                    .side = ctx.side,
                    .price = ctx.price,
                    .size = ctx.size,
                    .wallet_address = ctx.service.wallet.getAddress(),
                });
                
                // Display transaction information with improved formatting
                std.debug.print("\n✅ Order Placement Successful\n", .{});
                std.debug.print("─────────────────────────────────\n", .{});
                std.debug.print("  🏷️  Order ID: {s}\n", .{order_id});
                std.debug.print("  📊 Side: {s}\n", .{ctx.side});
                std.debug.print("  💰 Price: ${d:.2}\n", .{ctx.price});
                std.debug.print("  📦 Size: {d:.6} units\n", .{ctx.size});
                std.debug.print("  👛 Wallet: {s}\n", .{ctx.service.wallet.getAddress()});
                std.debug.print("  🔐 Status: Transaction signed securely\n", .{});
                std.debug.print("─────────────────────────────────\n\n", .{});
            }
        }.execute;
        
        try self.error_handler.executeWithRetry(void, context, placeOrderImpl);
    }
    
    /// Cancel an existing order with comprehensive security (write operation)
    pub fn cancelOrder(self: *EnhancedOrderService, order_id: []const u8) !void {
        self.write_mutex.lock();
        defer self.write_mutex.unlock();
        
        _ = self.operation_count.fetchAdd(1, .monotonic);
        defer _ = self.operation_count.fetchSub(1, .monotonic);
        
        logging.infoGlobalWithContext("service.orders", "Secure order cancellation request", .{
            .order_id = order_id,
        });

        // Comprehensive input validation
        if (order_id.len == 0) {
            logging.warnGlobal("service.orders", "Empty order ID provided for cancellation");
            return BlockchainError.InvalidOrderId;
        }
        
        if (order_id.len > BlockchainConstants.MAX_ORDER_ID_LENGTH) {
            logging.warnGlobalWithContext("service.orders", "Order ID too long", .{
                .order_id_length = order_id.len,
            });
            return BlockchainError.OrderIdTooLong;
        }
        
        // Validate order ID format (should be hex)
        for (order_id) |char| {
            if (!std.ascii.isHex(char)) {
                logging.warnGlobalWithContext("service.orders", "Invalid order ID format", .{
                    .invalid_char = char,
                });
                return BlockchainError.InvalidOrderIdFormat;
            }
        }

        // Sign the transaction with the wallet securely
        logging.debugGlobal("service.orders", "Signing cancel order transaction securely");
        const signature = self.wallet.signCancelOrderTransaction(
            self.order_service.default_market,
            order_id
        ) catch |err| {
            logging.errorGlobalWithContext("service.orders", "Failed to sign cancel transaction", .{
                .order_id = order_id,
                .error_name = @errorName(err),
            });
            return BlockchainError.AuthenticationFailed;
        };
        defer {
            // Secure cleanup of signature
            @memset(@constCast(signature), 0);
            self.allocator.free(signature);
        }
        
        // Execute cancellation with retry logic
        const CancelOrderContext = struct {
            service: *EnhancedOrderService,
            order_id: []const u8,
            signature: []const u8,
        };
        
        const context = CancelOrderContext{
            .service = self,
            .order_id = order_id,
            .signature = signature,
        };
        
        const cancelOrderImpl = struct {
            fn execute(ctx: CancelOrderContext) BlockchainError!void {
                ctx.service.order_service.client.cancelOrder(ctx.order_id) catch |err| {
                    switch (err) {
                        error.InvalidOrderId => return BlockchainError.InvalidOrderId,
                        error.OrderIdTooLong => return BlockchainError.OrderIdTooLong,
                        error.InvalidOrderIdFormat => return BlockchainError.InvalidOrderIdFormat,
                    }
                };
                
                // Log successful cancellation
                logging.infoGlobalWithContext("service.orders", "Order cancelled successfully", .{
                    .order_id = ctx.order_id,
                    .wallet_address = ctx.service.wallet.getAddress(),
                });
                
                // Display transaction information with improved formatting
                std.debug.print("\n✅ Order Cancellation Successful\n", .{});
                std.debug.print("─────────────────────────────────\n", .{});
                std.debug.print("  🗑️  Order ID: {s}\n", .{ctx.order_id});
                std.debug.print("  👛 Wallet: {s}\n", .{ctx.service.wallet.getAddress()});
                std.debug.print("  🔐 Status: Transaction signed securely\n", .{});
                std.debug.print("─────────────────────────────────\n\n", .{});
            }
        }.execute;
        
        try self.error_handler.executeWithRetry(void, context, cancelOrderImpl);
    }
    
    /// Deinitialize the service and free resources securely
    pub fn deinit(self: *EnhancedOrderService) void {
        // Wait for all operations to complete with improved timing
        while (self.operation_count.load(.monotonic) > 0) {
            std.Thread.sleep(BlockchainConstants.OPERATION_CLEANUP_SLEEP_MS * std.time.ns_per_ms);
        }
        
        self.order_service.deinit();
        self.wallet.deinit();
        
        logging.infoGlobal("service.orders", "Secure enhanced order service deinitialized");
    }
    
    /// Get current operation count for monitoring
    pub fn getOperationCount(self: *EnhancedOrderService) u64 {
        return self.operation_count.load(.monotonic);
    }
    
    /// Check if service is currently processing operations
    pub fn isBusy(self: *EnhancedOrderService) bool {
        return self.operation_count.load(.monotonic) > 0;
    }
};
