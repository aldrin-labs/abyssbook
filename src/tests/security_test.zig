const std = @import("std");
const testing = std.testing;
const BlockchainClient = @import("../blockchain/client.zig").BlockchainClient;
const BlockchainError = @import("../blockchain/error.zig").BlockchainError;
const ErrorHandler = @import("../blockchain/error.zig").ErrorHandler;
const BlockchainConstants = @import("../blockchain/constants.zig").BlockchainConstants;
const EnhancedOrderService = @import("../services/enhanced_orders.zig").EnhancedOrderService;

/// Test suite for security features in blockchain integration
pub fn runSecurityTests() !void {
    std.debug.print("Running comprehensive security tests...\n", .{});
    
    try testBlockchainClientSecurity();
    try testInputValidation();
    try testConcurrencySafety();
    try testErrorHandling();
    try testMemoryManagement();
    try testConstants();
    try testImprovedErrorMessages();
    
    std.debug.print("All security tests passed!\n", .{});
}

/// Test blockchain client security measures
fn testBlockchainClientSecurity() !void {
    std.debug.print("Testing blockchain client security...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test 1: Invalid API key
    {
        const result = BlockchainClient.init(allocator, "", "https://api.example.com");
        try testing.expectError(error.InvalidApiKey, result);
    }
    
    // Test 2: Invalid base URL
    {
        const result = BlockchainClient.init(allocator, "test-key", "");
        try testing.expectError(error.InvalidBaseUrl, result);
    }
    
    // Test 3: Insecure base URL
    {
        const result = BlockchainClient.init(allocator, "test-key", "http://api.example.com");
        try testing.expectError(error.InsecureBaseUrl, result);
    }
    
    // Test 4: Valid initialization
    {
        var client = try BlockchainClient.init(allocator, "test-key", "https://api.example.com");
        try testing.expect(client.getConnectionCount() == 0);
        client.deinit();
    }
    
    std.debug.print("Blockchain client security tests passed.\n", .{});
}

/// Test comprehensive input validation
fn testInputValidation() !void {
    std.debug.print("Testing input validation...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var client = try BlockchainClient.init(allocator, "test-key", "https://api.example.com");
    defer client.deinit();
    
    // Test invalid market names
    {
        const result = client.getOrderbook("");
        try testing.expectError(error.InvalidMarket, result);
    }
    
    {
        const long_market = "A" ** 65; // 65 characters
        const result = client.getOrderbook(long_market);
        try testing.expectError(error.MarketNameTooLong, result);
    }
    
    {
        const result = client.getOrderbook("SOL/USDC;DROP TABLE");
        try testing.expectError(error.InvalidMarketCharacters, result);
    }
    
    // Test invalid order parameters
    {
        const result = client.placeOrder("", 10.0, 1.0);
        try testing.expectError(error.InvalidSide, result);
    }
    
    {
        const result = client.placeOrder("invalid", 10.0, 1.0);
        try testing.expectError(error.InvalidSide, result);
    }
    
    {
        const result = client.placeOrder("buy", -10.0, 1.0);
        try testing.expectError(error.InvalidPrice, result);
    }
    
    {
        const result = client.placeOrder("buy", 10.0, -1.0);
        try testing.expectError(error.InvalidSize, result);
    }
    
    {
        const result = client.placeOrder("buy", 2000000000.0, 1.0);
        try testing.expectError(error.PriceTooHigh, result);
    }
    
    {
        const result = client.placeOrder("buy", 10.0, 2000000000.0);
        try testing.expectError(error.SizeTooHigh, result);
    }
    
    {
        const result = client.placeOrder("buy", std.math.nan(f64), 1.0);
        try testing.expectError(error.InvalidPriceValue, result);
    }
    
    {
        const result = client.placeOrder("buy", 10.0, std.math.inf(f64));
        try testing.expectError(error.InvalidSizeValue, result);
    }
    
    // Test invalid order ID for cancellation
    {
        const result = client.cancelOrder("");
        try testing.expectError(error.InvalidOrderId, result);
    }
    
    {
        const long_order_id = "A" ** 65; // 65 characters
        const result = client.cancelOrder(long_order_id);
        try testing.expectError(error.OrderIdTooLong, result);
    }
    
    {
        const result = client.cancelOrder("invalid-order-id!");
        try testing.expectError(error.InvalidOrderIdFormat, result);
    }
    
    std.debug.print("Input validation tests passed.\n", .{});
}

/// Test concurrency safety
fn testConcurrencySafety() !void {
    std.debug.print("Testing concurrency safety...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var client = try BlockchainClient.init(allocator, "test-key", "https://api.example.com");
    defer client.deinit();
    
    // Test concurrent connections
    const ThreadContext = struct {
        client: *BlockchainClient,
        iterations: u32,
    };
    
    var context = ThreadContext{
        .client = &client,
        .iterations = 10,
    };
    
    const connectTest = struct {
        fn run(ctx: *ThreadContext) void {
            var i: u32 = 0;
            while (i < ctx.iterations) : (i += 1) {
                ctx.client.connect() catch {};
                ctx.client.disconnect();
                std.time.sleep(1 * std.time.ns_per_ms);
            }
        }
    }.run;
    
    // Create multiple threads
    var threads: [4]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, connectTest, .{&context});
    }
    
    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }
    
    try testing.expect(client.getConnectionCount() == 0);
    
    std.debug.print("Concurrency safety tests passed.\n", .{});
}

/// Test error handling with retries
fn testErrorHandling() !void {
    std.debug.print("Testing error handling...\n", .{});
    
    var error_handler = ErrorHandler.init(3, 100);
    
    // Test retry mechanism
    const RetryContext = struct {
        attempts: u32 = 0,
        max_attempts: u32,
    };
    
    var context = RetryContext{ .max_attempts = 2 };
    
    const failingFunction = struct {
        fn execute(ctx: *RetryContext) BlockchainError!void {
            ctx.attempts += 1;
            if (ctx.attempts < ctx.max_attempts) {
                return BlockchainError.NetworkError;
            }
            // Success on the final attempt
        }
    }.execute;
    
    try error_handler.executeWithRetry(void, &context, failingFunction);
    try testing.expect(context.attempts == 2);
    
    // Test non-retryable errors
    context = RetryContext{ .max_attempts = 5 };
    
    const nonRetryableFunction = struct {
        fn execute(ctx: *RetryContext) BlockchainError!void {
            ctx.attempts += 1;
            return BlockchainError.AuthenticationFailed;
        }
    }.execute;
    
    const result = error_handler.executeWithRetry(void, &context, nonRetryableFunction);
    try testing.expectError(BlockchainError.AuthenticationFailed, result);
    try testing.expect(context.attempts == 1); // Should not retry
    
    std.debug.print("Error handling tests passed.\n", .{});
}

/// Test memory management and security
fn testMemoryManagement() !void {
    std.debug.print("Testing memory management...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test secure memory cleanup
    var client = try BlockchainClient.init(allocator, "test-key", "https://api.example.com");
    
    // Test that connection count is properly managed
    try testing.expect(client.getConnectionCount() == 0);
    
    try client.connect();
    try testing.expect(client.getConnectionCount() == 1);
    
    client.disconnect();
    try testing.expect(client.getConnectionCount() == 0);
    
    // Test secure deinitialization
    client.deinit();
    
    std.debug.print("Memory management tests passed.\n", .{});
}

// Test order data validation
test "order validation" {
    const Order = @import("../blockchain/client.zig").Order;
    
    var valid_order = Order{
        .price = 100.0,
        .size = 10.0,
        .order_id = "123456789",
        .owner_address = "wallet123",
    };
    
    try valid_order.validate();
    
    // Test invalid price
    var invalid_order = Order{
        .price = -100.0,
        .size = 10.0,
        .order_id = "123456789",
        .owner_address = "wallet123",
    };
    
    try testing.expectError(error.InvalidPrice, invalid_order.validate());
    
    // Test price too high
    invalid_order.price = 2000000000.0;
    try testing.expectError(error.PriceTooHigh, invalid_order.validate());
    
    // Test NaN price
    invalid_order.price = std.math.nan(f64);
    try testing.expectError(error.InvalidPriceValue, invalid_order.validate());
}

// Test orderbook validation
test "orderbook validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const Orderbook = @import("../blockchain/client.zig").Orderbook;
    const Order = @import("../blockchain/client.zig").Order;
    
    var orders = try allocator.alloc(Order, 2);
    defer allocator.free(orders);
    
    orders[0] = Order{
        .price = 100.0,
        .size = 10.0,
        .order_id = try allocator.dupe(u8, "123456789"),
        .owner_address = try allocator.dupe(u8, "wallet123"),
    };
    
    orders[1] = Order{
        .price = 99.0,
        .size = 5.0,
        .order_id = try allocator.dupe(u8, "987654321"),
        .owner_address = try allocator.dupe(u8, "wallet456"),
    };
    
    var asks = try allocator.alloc(Order, 1);
    defer allocator.free(asks);
    
    asks[0] = Order{
        .price = 101.0,
        .size = 15.0,
        .order_id = try allocator.dupe(u8, "555666777"),
        .owner_address = try allocator.dupe(u8, "wallet789"),
    };
    
    var orderbook = Orderbook{
        .market = try allocator.dupe(u8, "SOL/USDC"),
        .market_address = try allocator.dupe(u8, "market123"),
        .bids = orders,
        .asks = asks,
    };
    
    try orderbook.validate();
    
    // Test crossed orderbook (bid higher than ask)
    orders[0].price = 102.0; // Higher than lowest ask
    try testing.expectError(error.CrossedOrderbook, orderbook.validate());
    
    // Clean up
    orderbook.deinit(allocator);
}

/// Test centralized constants
fn testConstants() !void {
    std.debug.print("Testing centralized constants...\n", .{});
    
    // Test that constants are properly defined and reasonable
    try testing.expect(BlockchainConstants.MAX_RETRIES > 0);
    try testing.expect(BlockchainConstants.BASE_RETRY_DELAY_MS > 0);
    try testing.expect(BlockchainConstants.RATE_LIMIT_DELAY_MS > 0);
    try testing.expect(BlockchainConstants.MAX_RESPONSE_SIZE > 1024); // At least 1KB
    try testing.expect(BlockchainConstants.MAX_MARKET_NAME_LENGTH > 0);
    try testing.expect(BlockchainConstants.MAX_ORDER_ID_LENGTH > 0);
    try testing.expect(BlockchainConstants.MAX_PRICE_VALUE > 0);
    try testing.expect(BlockchainConstants.MAX_SIZE_VALUE > 0);
    try testing.expect(BlockchainConstants.ORDER_ID_BYTES > 0);
    try testing.expect(BlockchainConstants.ORDER_ID_HEX_LENGTH == BlockchainConstants.ORDER_ID_BYTES * 2);
    
    std.debug.print("Constants validation tests passed.\n", .{});
}

/// Test improved error message formatting
fn testImprovedErrorMessages() !void {
    std.debug.print("Testing improved error messages...\n", .{});
    
    // Test that error messages contain emojis and context
    const network_error_msg = ErrorHandler.formatErrorMessage(BlockchainError.NetworkError);
    try testing.expect(std.mem.indexOf(u8, network_error_msg, "🌐") != null);
    
    const auth_error_msg = ErrorHandler.formatErrorMessage(BlockchainError.AuthenticationFailed);
    try testing.expect(std.mem.indexOf(u8, auth_error_msg, "🔑") != null);
    
    const validation_error_msg = ErrorHandler.formatErrorMessage(BlockchainError.InvalidPrice);
    try testing.expect(std.mem.indexOf(u8, validation_error_msg, "💰") != null);
    
    // Test that all error messages are non-empty
    inline for (@typeInfo(BlockchainError).ErrorSet.?) |error_info| {
        const error_value = @field(BlockchainError, error_info.name);
        const msg = ErrorHandler.formatErrorMessage(error_value);
        try testing.expect(msg.len > 0);
    }
    
    std.debug.print("Error message formatting tests passed.\n", .{});
}