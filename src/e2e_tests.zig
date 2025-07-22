const std = @import("std");
const testing = std.testing;
const orderbook = @import("orderbook.zig");
const market = @import("market.zig");
const fees = @import("fees.zig");
const OrderSide = orderbook.OrderSide;

// E2E test for a complete trading scenario with multiple order types
test "E2E - Complete Trading Scenario" {
    const allocator = testing.allocator;
    // Use fewer shards for CI to reduce memory usage
    var shard_count: u64 = 8;
    if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) shard_count = 4;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // 1. Setup initial market state with limit orders
    try book.placeOrder(.Buy, 98, 10, 1);
    try book.placeOrder(.Buy, 99, 20, 2);
    try book.placeOrder(.Sell, 101, 15, 3);
    try book.placeOrder(.Sell, 102, 25, 4);

    // Verify initial state
    try testing.expectEqual(@as(u64, 10), try book.getVolume(.Buy, 98));
    try testing.expectEqual(@as(u64, 20), try book.getVolume(.Buy, 99));
    try testing.expectEqual(@as(u64, 15), try book.getVolume(.Sell, 101));
    try testing.expectEqual(@as(u64, 25), try book.getVolume(.Sell, 102));

    // 2. Execute market order that partially fills
    const market_result = try book.executeMarketOrder(.Buy, 10);
    try testing.expectEqual(@as(u64, 10), market_result.filled_amount);
    try testing.expectEqual(@as(u64, 0), market_result.remaining_amount);
    try testing.expectEqual(@as(u64, 101), market_result.execution_price);

    // Verify state after market order
    try testing.expectEqual(@as(u64, 5), try book.getVolume(.Sell, 101));

    // 3. Place and execute TWAP order
    try book.placeTWAPOrder(.Buy, 101, 15, 5, 3, 1);

    // Simulate time passing for first interval
    const twap_order_key = orderbook.OrderKey{ .price = 101, .id = 5 };
    const shard_index = book.priceToShard(101);
    var twap_order = book.shards[shard_index].get(twap_order_key) orelse return error.OrderNotFound;

    const is_complete = try book.executeTWAPInterval(&twap_order);
    try testing.expect(!is_complete); // Should not be complete after first interval

    // Verify TWAP execution - should have executed one interval
    try testing.expectEqual(@as(u64, 5), try book.getVolume(.Buy, 101));

    // 4. Place iceberg order
    try book.placeIcebergOrder(.Sell, 100, 30, 10, 6);

    // Verify iceberg order initial state
    try testing.expectEqual(@as(u64, 10), try book.getVolume(.Sell, 100));

    // 5. Execute market order that hits the iceberg order
    const market_result2 = try book.executeMarketOrder(.Buy, 15);
    try testing.expectEqual(@as(u64, 15), market_result2.filled_amount);

    // Verify iceberg order replenished
    try testing.expectEqual(@as(u64, 10), try book.getVolume(.Sell, 100));

    // 6. Place stop order
    try book.placeStopOrder(.Sell, 95, 10, 7, 97);

    // 7. Place trailing stop order
    try book.placeTrailingStopOrder(.Buy, 105, 8, 8, 3);

    // 8. Place peg order
    try book.placePegOrder(.Buy, 12, .BestBid, 1, null, 9);

    // Verify peg order price (best bid is now 101 after TWAP execution, so 101 + 1 = 102)
    const actual_price = try book.getOrderPrice(9);
    try testing.expectEqual(@as(u64, 102), actual_price);

    // 9. Place conditional order
    try book.placeConditionalOrder(.Sell, 90, 5, 10, .Price, 95);

    // 10. Cancel an order
    try book.cancelOrder(2);

    // Verify cancellation
    try testing.expectEqual(@as(u64, 0), try book.getVolume(.Buy, 99));

    // 11. Execute another market order to trigger stop order
    _ = try book.executeMarketOrder(.Sell, 15);

    // Verify conditional order triggered and created volume at order price (90)
    try testing.expectEqual(@as(u64, 5), try book.getVolume(.Sell, 90));
}

// E2E test for high-frequency trading scenario
test "E2E - High Frequency Trading" {
    const allocator = testing.allocator;
    // Use fewer shards for CI to reduce memory usage
    var shard_count: u64 = 32;
    if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) shard_count = 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // 1. Setup initial tight spread
    try book.placeOrder(.Buy, 999, 100, 1);
    try book.placeOrder(.Sell, 1001, 100, 2);

    // 2. Rapid fire orders - simulate HFT activity (reduced for CI)
    const max_iterations = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 23 else 103;
    var i: u64 = 3;
    while (i < max_iterations) : (i += 1) {
        // Place and cancel orders rapidly
        try book.placeOrder(.Buy, 998, 1, i);
        try book.cancelOrder(i);

        // Place and execute small market orders
        try book.placeOrder(.Buy, 997, 1, i + 100);
        _ = try book.executeMarketOrder(.Sell, 1);
    }

    // 3. Burst of orders at same price level (reduced for CI)
    var orders = std.ArrayList(orderbook.CacheAlignedOrder).init(allocator);
    defer orders.deinit();

    const order_start = if (max_iterations < 50) 200 else 200;
    const order_end = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) order_start + 20 else 300;
    i = order_start;
    while (i < order_end) : (i += 1) {
        try orders.append(orderbook.CacheAlignedOrder.init(1000, 1, i, .Buy, .Limit, null));
    }

    try book.bulkInsertOrders(.Buy, 1000, orders.items);

    // 4. Verify final state after HFT activity (adjusted for reduced orders)
    const expected_volume = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 20 else 100;
    try testing.expectEqual(@as(u64, expected_volume), try book.getVolume(.Buy, 1000));
}

// E2E test for market stress scenario
test "E2E - Market Stress" {
    const allocator = testing.allocator;
    var shard_count: u64 = 16;
    if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) shard_count = 4;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // 1. Setup wide range of price levels (reduced for CI)
    const max_levels = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 25 else 100;
    var i: u64 = 0;
    while (i < max_levels) : (i += 1) {
        try book.placeOrder(.Buy, 900 + i, 10, i + 1);
        try book.placeOrder(.Sell, 1100 - i, 10, i + 1000);
    }

    // 2. Execute large market orders (reduced sizes for CI)
    const market_size = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 125 else 500;
    const buy_result = try book.executeMarketOrder(.Buy, market_size);
    try testing.expectEqual(@as(u64, market_size), buy_result.filled_amount);

    const sell_result = try book.executeMarketOrder(.Sell, market_size);
    try testing.expectEqual(@as(u64, market_size), sell_result.filled_amount);

    // 3. Cancel many orders (some may have been consumed by market orders) - reduced for CI
    const cancel_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 12 else 50;
    i = 0;
    while (i < cancel_count) : (i += 1) {
        book.cancelOrder(i + 1) catch |err| {
            // Ignore OrderNotFound errors since market orders may have consumed some orders
            if (err != orderbook.ShardedOrderbook.OrderError.OrderNotFound) {
                return err;
            }
        };
    }

    // 4. Verify state after stress
    var total_buy_volume: u64 = 0;
    i = 0;
    while (i < 100) : (i += 1) {
        total_buy_volume += try book.getVolume(.Buy, 900 + i);
    }

    try testing.expect(total_buy_volume < 1000); // Some volume should be consumed
}

// E2E test for advanced order types
test "E2E - Advanced Order Types" {
    const allocator = testing.allocator;
    var book = try orderbook.ShardedOrderbook.init(allocator, 8);
    defer book.deinit();

    // 1. Setup initial market state
    try book.placeOrder(.Buy, 98, 10, 1);
    try book.placeOrder(.Buy, 99, 20, 2);
    try book.placeOrder(.Sell, 101, 15, 3);
    try book.placeOrder(.Sell, 102, 25, 4);

    // 2. Place discretionary order
    try book.placeDiscretionaryOrder(.Buy, 100, 10, 5, 102);

    // 3. Place iceberg order
    try book.placeIcebergOrder(.Sell, 100, 30, 10, 6);

    // 4. Place TWAP order
    try book.placeTWAPOrder(.Buy, 101, 15, 7, 3, 1);

    // 5. Place trailing stop order
    try book.placeTrailingStopOrder(.Sell, 95, 10, 8, 3);

    // 6. Place peg order
    try book.placePegOrder(.Buy, 12, .BestBid, 1, null, 9);

    // 7. Place conditional order
    try book.placeConditionalOrder(.Sell, 90, 5, 10, .Price, 95);

    // 8. Execute market orders to interact with advanced orders
    _ = try book.executeMarketOrder(.Buy, 20);
    _ = try book.executeMarketOrder(.Sell, 20);

    // 9. Verify final state - check that sell volume exists at 100 (from iceberg order)
    try testing.expect(try book.getVolume(.Sell, 100) > 0);
}

// E2E test for edge cases
test "E2E - Edge Cases" {
    const allocator = testing.allocator;
    var book = try orderbook.ShardedOrderbook.init(allocator, 8);
    defer book.deinit();

    // 1. Zero amount orders (should fail)
    try testing.expectError(error.InvalidAmount, book.placeOrder(.Buy, 100, 0, 1));

    // 2. Duplicate order IDs
    try book.placeOrder(.Buy, 100, 10, 2);
    try testing.expectError(error.DuplicateOrder, book.placeOrder(.Buy, 101, 5, 2));

    // 3. Cancel non-existent order
    try testing.expectError(error.OrderNotFound, book.cancelOrder(999));

    // 4. Market order with no liquidity
    book.deinit();
    book = try orderbook.ShardedOrderbook.init(allocator, 8);

    const result = try book.executeMarketOrder(.Buy, 10);
    try testing.expectEqual(@as(u64, 0), result.filled_amount);
    try testing.expectEqual(@as(u64, 10), result.remaining_amount);

    // 5. Extremely large orders
    try book.placeOrder(.Sell, 100, 1000000, 3);
    const large_result = try book.executeMarketOrder(.Buy, 2000000);
    try testing.expectEqual(@as(u64, 1000000), large_result.filled_amount);
    try testing.expectEqual(@as(u64, 1000000), large_result.remaining_amount);

    // 6. Extremely small orders
    try book.placeOrder(.Buy, 100, 1, 4);
    try book.placeOrder(.Sell, 100, 1, 5);

    // 7. Maximum price
    try book.placeOrder(.Buy, std.math.maxInt(u64) - 1, 10, 6);
    try testing.expectEqual(@as(u64, 10), try book.getVolume(.Buy, std.math.maxInt(u64) - 1));
}

// E2E test for fee calculation
test "E2E - Fee Calculation" {
    const allocator = testing.allocator;
    var book = try orderbook.ShardedOrderbook.init(allocator, 8);
    defer book.deinit();

    // 1. Setup market with orders
    try book.placeOrder(.Buy, 100, 10, 1);
    try book.placeOrder(.Sell, 100, 10, 2);

    // 2. Calculate fees for a trade
    const trade_amount: u64 = 10;
    const trade_price: u64 = 100;
    const trade_value = trade_amount * trade_price;

    const maker_fee = fees.calculateMakerFee(trade_value);
    const taker_fee = fees.calculateTakerFee(trade_value);

    // 3. Verify fee calculation
    try testing.expect(maker_fee < taker_fee); // Maker fees should be lower than taker fees
    try testing.expect(maker_fee > 0); // Fees should be positive
}

// E2E test for market data snapshots
test "E2E - Market Data Snapshots" {
    const allocator = testing.allocator;
    var book = try orderbook.ShardedOrderbook.init(allocator, 8);
    defer book.deinit();

    // 1. Setup market with orders
    try book.placeOrder(.Buy, 98, 10, 1);
    try book.placeOrder(.Buy, 99, 20, 2);
    try book.placeOrder(.Sell, 101, 15, 3);
    try book.placeOrder(.Sell, 102, 25, 4);

    // 2. Take a snapshot of the orderbook
    var snapshot = try book.takeSnapshot();
    defer snapshot.deinit();

    // 3. Verify snapshot data
    try testing.expectEqual(@as(usize, 2), snapshot.bids.items.len);
    try testing.expectEqual(@as(usize, 2), snapshot.asks.items.len);

    try testing.expectEqual(@as(u64, 99), snapshot.bids.items[0].price);
    try testing.expectEqual(@as(u64, 20), snapshot.bids.items[0].amount);
    try testing.expectEqual(@as(u64, 98), snapshot.bids.items[1].price);
    try testing.expectEqual(@as(u64, 10), snapshot.bids.items[1].amount);

    try testing.expectEqual(@as(u64, 101), snapshot.asks.items[0].price);
    try testing.expectEqual(@as(u64, 15), snapshot.asks.items[0].amount);
    try testing.expectEqual(@as(u64, 102), snapshot.asks.items[1].price);
    try testing.expectEqual(@as(u64, 25), snapshot.asks.items[1].amount);

    // 4. Modify orderbook after snapshot
    try book.placeOrder(.Buy, 100, 30, 5);
    try book.cancelOrder(3);

    // 5. Verify snapshot remains unchanged
    try testing.expectEqual(@as(usize, 2), snapshot.bids.items.len);
    try testing.expectEqual(@as(usize, 2), snapshot.asks.items.len);

    // 6. Take a new snapshot and verify changes
    var new_snapshot = try book.takeSnapshot();
    defer new_snapshot.deinit();

    try testing.expectEqual(@as(usize, 3), new_snapshot.bids.items.len);
    try testing.expectEqual(@as(usize, 1), new_snapshot.asks.items.len);
}

// E2E test for cross-shard operations
test "E2E - Cross-Shard Operations" {
    const allocator = testing.allocator;
    var book = try orderbook.ShardedOrderbook.init(allocator, 16); // More shards to test cross-shard
    defer book.deinit();

    // 1. Place orders across different shards
    var i: u64 = 0;
    while (i < 16) : (i += 1) {
        const price = 100 + i * 100; // Ensure different shards
        try book.placeOrder(.Buy, price, 10, i + 1);
        try book.placeOrder(.Sell, price + 50, 10, i + 100);
    }

    // 2. Execute market order that crosses multiple shards
    const result = try book.executeMarketOrder(.Buy, 80);
    try testing.expectEqual(@as(u64, 80), result.filled_amount);

    // 3. Verify state after cross-shard operation
    var total_sell_volume: u64 = 0;
    i = 0;
    while (i < 16) : (i += 1) {
        const price = 100 + i * 100 + 50;
        total_sell_volume += try book.getVolume(.Sell, price);
    }

    try testing.expectEqual(@as(u64, 80), 160 - total_sell_volume);
}

// E2E test for performance characteristics
test "E2E - Performance Characteristics" {
    const allocator = testing.allocator;
    var book = try orderbook.ShardedOrderbook.init(allocator, 32);
    defer book.deinit();

    // 1. Measure time for bulk operations
    var timer = try std.time.Timer.start();

    // 2. Place many orders
    var i: u64 = 0;
    while (i < 1000) : (i += 1) {
        try book.placeOrder(.Buy, 100 + (i % 100), 10, i + 1);
    }

    const place_time = timer.lap();

    // 3. Execute market orders
    var j: u64 = 0;
    while (j < 10) : (j += 1) {
        _ = try book.executeMarketOrder(.Sell, 50);
    }

    const market_time = timer.lap();

    // 4. Cancel orders (only cancel if they exist)
    i = 0;
    while (i < 500) : (i += 1) {
        if (i % 2 == 0) {
            book.cancelOrder(i + 1) catch |err| {
                // Ignore OrderNotFound errors since market orders may have consumed some orders
                if (err != orderbook.ShardedOrderbook.OrderError.OrderNotFound) {
                    return err;
                }
            };
        }
    }

    const cancel_time = timer.read();

    // 5. Verify performance is within acceptable limits
    std.debug.print("\nPerformance metrics:\n", .{});
    std.debug.print("Place 1000 orders: {d} ns ({d} ns per order)\n", .{ place_time, place_time / 1000 });
    std.debug.print("Execute 10 market orders: {d} ns ({d} ns per order)\n", .{ market_time, market_time / 10 });
    std.debug.print("Cancel 250 orders: {d} ns ({d} ns per order)\n", .{ cancel_time, cancel_time / 250 });

    // Loose performance assertions - these will vary by hardware
    try testing.expect(place_time / 1000 < 10_000_000); // Less than 10ms per order
    try testing.expect(market_time / 10 < 10_000_000); // Less than 10ms per market order
    try testing.expect(cancel_time / 250 < 10_000_000); // Less than 10ms per cancel
}
