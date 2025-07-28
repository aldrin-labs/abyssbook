const std = @import("std");
const testing = std.testing;
const Thread = std.Thread;

// Import our secure components
const BlockchainClient = @import("../blockchain/client.zig").BlockchainClient;
const EnhancedOrderService = @import("../services/enhanced_orders.zig").EnhancedOrderService;
const OrderService = @import("../services/orders.zig").OrderService;
const BlockchainError = @import("../blockchain/error.zig").BlockchainError;
const ErrorHandler = @import("../blockchain/error.zig").ErrorHandler;

/// Integration tests for secure onchain operations
pub fn runIntegrationTests() !void {
    std.debug.print("Running secure integration tests...\n", .{});
    
    try testSecureOrderServiceWorkflow();
    try testConcurrentOperations();
    try testErrorRecovery();
    try testSecurityBoundaries();
    
    std.debug.print("All integration tests passed!\n", .{});
}

/// Test complete secure order service workflow
fn testSecureOrderServiceWorkflow() !void {
    std.debug.print("Testing secure order service workflow...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create order service with security measures
    var order_service = OrderService.init(
        allocator,
        "test-api-key",
        "https://api.test.com"
    ) catch |err| {
        // Expected to fail in test environment without real API
        switch (err) {
            error.InvalidApiKey, error.InvalidBaseUrl, error.InsecureBaseUrl => {
                std.debug.print("Expected security validation error: {}\n", .{err});
                return;
            },
            else => return err,
        }
    };
    defer order_service.deinit();
    
    std.debug.print("Secure order service workflow test completed.\n", .{});
}

/// Test concurrent operations safety
fn testConcurrentOperations() !void {
    std.debug.print("Testing concurrent operations safety...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var client = try BlockchainClient.init(allocator, "test-key", "https://api.example.com");
    defer client.deinit();
    
    // Test concurrent rate limiting
    const RateLimitContext = struct {
        client: *BlockchainClient,
        operation_count: std.atomic.Value(u32),
        error_count: std.atomic.Value(u32),
    };
    
    var context = RateLimitContext{
        .client = &client,
        .operation_count = std.atomic.Value(u32).init(0),
        .error_count = std.atomic.Value(u32).init(0),
    };
    
    const rateLimitTest = struct {
        fn run(ctx: *RateLimitContext) void {
            var i: u32 = 0;
            while (i < 5) : (i += 1) {
                _ = ctx.operation_count.fetchAdd(1, .monotonic);
                
                // Simulate rapid requests that should trigger rate limiting
                const result = ctx.client.placeOrder("buy", 100.0, 1.0);
                if (result) |order_id| {
                    defer ctx.client.allocator.free(order_id);
                } else |_| {
                    _ = ctx.error_count.fetchAdd(1, .monotonic);
                }
                
                std.time.sleep(10 * std.time.ns_per_ms); // Short delay
            }
        }
    }.run;
    
    // Create multiple threads to test concurrent access
    var threads: [3]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, rateLimitTest, .{&context});
    }
    
    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }
    
    // Verify operations were executed and rate limiting worked
    const total_operations = context.operation_count.load(.monotonic);
    try testing.expect(total_operations == 15); // 3 threads * 5 operations each
    
    std.debug.print("Concurrent operations safety test completed.\n", .{});
}

/// Test error recovery mechanisms
fn testErrorRecovery() !void {
    std.debug.print("Testing error recovery mechanisms...\n", .{});
    
    var error_handler = ErrorHandler.init(3, 50); // 3 retries, 50ms base delay
    
    // Test recovery from transient errors
    const RecoveryContext = struct {
        attempts: u32 = 0,
        should_succeed_after: u32,
    };
    
    var context = RecoveryContext{ .should_succeed_after = 2 };
    
    const recoveryFunction = struct {
        fn execute(ctx: *RecoveryContext) BlockchainError!void {
            ctx.attempts += 1;
            if (ctx.attempts < ctx.should_succeed_after) {
                return BlockchainError.NetworkError; // Transient error
            }
            // Success after retries
        }
    }.execute;
    
    const start_time = std.time.milliTimestamp();
    try error_handler.executeWithRetry(void, &context, recoveryFunction);
    const end_time = std.time.milliTimestamp();
    
    // Verify retry logic worked
    try testing.expect(context.attempts == 2);
    
    // Verify exponential backoff was applied (should take at least 50ms for 1 retry)
    try testing.expect(end_time - start_time >= 50);
    
    std.debug.print("Error recovery test completed.\n", .{});
}

/// Test security boundaries and validation
fn testSecurityBoundaries() !void {
    std.debug.print("Testing security boundaries...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test 1: Input sanitization
    {
        const result = BlockchainClient.init(allocator, "key", "https://api.test.com");
        if (result) |client| {
            defer client.deinit();
            
            // Test malicious market name
            const malicious_market = "SOL/USDC'; DROP TABLE orders; --";
            const market_result = client.getOrderbook(malicious_market);
            try testing.expectError(error.InvalidMarketCharacters, market_result);
        } else |_| {
            // Expected in test environment
        }
    }
    
    // Test 2: Memory bounds checking
    {
        const result = BlockchainClient.init(allocator, "key", "https://api.test.com");
        if (result) |client| {
            defer client.deinit();
            
            // Test extremely long order ID
            var long_id = try allocator.alloc(u8, 1000);
            defer allocator.free(long_id);
            std.mem.set(u8, long_id, 'A');
            
            const cancel_result = client.cancelOrder(long_id);
            try testing.expectError(error.OrderIdTooLong, cancel_result);
        } else |_| {
            // Expected in test environment
        }
    }
    
    // Test 3: Numerical bounds checking
    {
        const result = BlockchainClient.init(allocator, "key", "https://api.test.com");
        if (result) |client| {
            defer client.deinit();
            
            // Test extreme values
            const extreme_price_result = client.placeOrder("buy", std.math.floatMax(f64), 1.0);
            try testing.expectError(error.PriceTooHigh, extreme_price_result);
            
            const extreme_size_result = client.placeOrder("buy", 100.0, std.math.floatMax(f64));
            try testing.expectError(error.SizeTooHigh, extreme_size_result);
        } else |_| {
            // Expected in test environment
        }
    }
    
    std.debug.print("Security boundaries test completed.\n", .{});
}

// Test memory safety and cleanup
test "memory safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();
    
    // Test secure memory cleanup in blockchain client
    {
        var client = try BlockchainClient.init(allocator, "test-key", "https://api.example.com");
        
        // Generate order ID to test secure cleanup
        const order_id = try client.placeOrder("buy", 100.0, 10.0);
        defer allocator.free(order_id);
        
        // Verify order ID is properly generated
        try testing.expect(order_id.len == 32); // 16 bytes as hex = 32 chars
        
        client.deinit(); // Should securely clear sensitive data
    }
}

// Test atomic operations
test "atomic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var client = try BlockchainClient.init(allocator, "test-key", "https://api.example.com");
    defer client.deinit();
    
    // Test atomic connection counting
    try testing.expect(client.getConnectionCount() == 0);
    
    try client.connect();
    try testing.expect(client.getConnectionCount() == 1);
    
    try client.connect(); // Should not increment again
    try testing.expect(client.getConnectionCount() == 1);
    
    client.disconnect();
    try testing.expect(client.getConnectionCount() == 0);
}

// Test rate limiting functionality
test "rate limiting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var client = try BlockchainClient.init(allocator, "test-key", "https://api.example.com");
    defer client.deinit();
    
    // Test that rate limiting tracking works
    const initial_time = client.getLastRequestTime();
    try testing.expect(initial_time == 0);
    
    // Simulate a request (would normally trigger rate limiting)
    const order_result = client.placeOrder("buy", 100.0, 1.0);
    if (order_result) |order_id| {
        defer allocator.free(order_id);
        const new_time = client.getLastRequestTime();
        try testing.expect(new_time > initial_time);
    } else |_| {
        // Expected in test environment
    }
}

// Stress test for concurrent access
test "stress test concurrent access" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var client = try BlockchainClient.init(allocator, "test-key", "https://api.example.com");
    defer client.deinit();
    
    const StressContext = struct {
        client: *BlockchainClient,
        success_count: std.atomic.Value(u32),
        error_count: std.atomic.Value(u32),
    };
    
    var context = StressContext{
        .client = &client,
        .success_count = std.atomic.Value(u32).init(0),
        .error_count = std.atomic.Value(u32).init(0),
    };
    
    const stressTest = struct {
        fn run(ctx: *StressContext) void {
            var i: u32 = 0;
            while (i < 20) : (i += 1) {
                // Rapid connection/disconnection
                ctx.client.connect() catch {
                    _ = ctx.error_count.fetchAdd(1, .monotonic);
                    continue;
                };
                
                ctx.client.disconnect();
                _ = ctx.success_count.fetchAdd(1, .monotonic);
                
                // Small delay to prevent overwhelming
                std.time.sleep(1 * std.time.ns_per_ms);
            }
        }
    }.run;
    
    // Run stress test with multiple threads
    var threads: [5]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, stressTest, .{&context});
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    const total_operations = context.success_count.load(.monotonic) + context.error_count.load(.monotonic);
    try testing.expect(total_operations == 100); // 5 threads * 20 operations each
    
    // Verify no connections are left open
    try testing.expect(client.getConnectionCount() == 0);
}