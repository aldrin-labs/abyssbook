const std = @import("std");
const testing = std.testing;
const orderbook = @import("orderbook.zig");
const OrderSide = orderbook.OrderSide;

test "Basic Order Placement" {
    const allocator = testing.allocator;
    // Use fewer shards for CI to reduce memory usage
    const shard_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 4 else 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // Place buy order
    try book.placeOrder(.Buy, 100, 10, 1);
    try testing.expectEqual(@as(u64, 10), try book.getVolume(.Buy, 100));

    // Place sell order
    try book.placeOrder(.Sell, 100, 5, 2);
    try testing.expectEqual(@as(u64, 5), try book.getVolume(.Sell, 100));
    try testing.expectEqual(@as(u64, 5), try book.getVolume(.Buy, 100)); // After matching
}

test "Order Cancellation" {
    const allocator = testing.allocator;
    // Use fewer shards for CI to reduce memory usage
    const shard_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 4 else 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // Place orders
    try book.placeOrder(.Buy, 100, 5, 1);
    try book.placeOrder(.Buy, 100, 4, 2);
    try book.placeOrder(.Buy, 100, 3, 3);
    try book.placeOrder(.Buy, 100, 7, 4);

    // Cancel an order
    try book.cancelOrder(2);

    // Check volume
    try testing.expectEqual(@as(u64, 15), try book.getVolume(.Buy, 100));
}

test "Market Orders" {
    const allocator = testing.allocator;
    // Use fewer shards for CI to reduce memory usage
    const shard_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 4 else 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // Place limit orders
    try book.placeOrder(.Buy, 100, 5, 1);
    try book.placeOrder(.Buy, 101, 3, 2);
    try book.placeOrder(.Buy, 102, 2, 3);

    // Execute market sell order
    const result = try book.executeMarketOrder(.Sell, 8);
    try testing.expectEqual(@as(u64, 8), result.filled_amount);
    try testing.expectEqual(@as(u64, 0), result.remaining_amount);

    // Check volumes
    try testing.expectEqual(@as(u64, 2), try book.getVolume(.Buy, 100));
    try testing.expectEqual(@as(u64, 0), try book.getVolume(.Buy, 101));
    try testing.expectEqual(@as(u64, 0), try book.getVolume(.Buy, 102));
}

test "TWAP Orders" {
    const allocator = testing.allocator;
    const shard_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 4 else 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // Place a TWAP order with 5 intervals of 20 each
    try book.placeTWAPOrder(.Buy, 100, 100, 1, 5, 1);
    std.debug.print("Placed TWAP order\n", .{});

    // Place matching sell orders
    try book.placeOrder(.Sell, 100, 50, 2);
    std.debug.print("Placed matching sell order\n", .{});

    // Wait for interval
    std.time.sleep(2 * std.time.ns_per_s);
    std.debug.print("Waited for interval\n", .{});

    // Find and execute TWAP order
    const shard_index = book.priceToShard(100);
    std.debug.print("Shard index: {}\n", .{shard_index});

    const key = orderbook.OrderKey{ .price = 100, .id = 1 };
    std.debug.print("Looking for order with key: price={}, id={}\n", .{ key.price, key.id });

    // Debug: print all orders in the shard
    var it = book.shards[shard_index].iterator();
    while (it.next()) |entry| {
        std.debug.print("Found order: price={}, id={}, type={}\n", .{
            entry.key_ptr.price,
            entry.key_ptr.id,
            entry.value_ptr.order_type,
        });
    }

    var order = book.shards[shard_index].get(key) orelse {
        std.debug.print("Failed to find TWAP order\n", .{});
        return error.OrderNotFound;
    };

    std.debug.print("Found TWAP order: amount={}, total_amount={}, amount_per_interval={}\n", .{
        order.amount,
        order.twap_params.?.total_amount,
        order.twap_params.?.amount_per_interval,
    });

    const is_complete = try book.executeTWAPInterval(&order);
    try testing.expect(!is_complete); // Should not be complete after first interval

    // Check execution - should have executed one interval of 20
    const volume = try book.getVolume(.Buy, 100);
    std.debug.print("Volume at price 100: {}\n", .{volume});
    try testing.expectEqual(@as(u64, 20), volume);
}

test "Trailing Stop Orders" {
    const allocator = testing.allocator;
    const shard_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 4 else 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // Place a trailing stop order with distance 5
    try book.placeTrailingStopOrder(.Buy, 105, 5, 1, 5);

    // Place orders to test trailing
    try book.placeOrder(.Sell, 103, 1, 2);
    try book.placeOrder(.Sell, 102, 1, 3);

    // Get the order and update its stop price
    var order = book.stop_orders[book.priceToShard(105)].get(.{ .price = 105, .id = 1 }) orelse {
        std.debug.print("Failed to find trailing stop order\n", .{});
        return error.OrderNotFound;
    };
    std.debug.print("Found trailing stop order: price={}, stop_price={}, distance={}\n", .{
        order.price,
        order.stop_price.?,
        order.trailing_params.?.distance,
    });

    try book.executeTrailingStopOrder(&order);

    // Check if stop price adjusted - should be current market price (102) + distance (5) = 107
    const stop_price = book.getStopPrice(1) orelse {
        std.debug.print("Failed to get stop price\n", .{});
        return error.OrderNotFound;
    };
    std.debug.print("Stop price after update: {}\n", .{stop_price});
    try testing.expectEqual(@as(u64, 107), stop_price);
}

test "Peg Orders" {
    const allocator = testing.allocator;
    const shard_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 4 else 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // Place some orders to establish best bid/ask
    try book.placeOrder(.Buy, 98, 1, 1);
    try book.placeOrder(.Sell, 102, 1, 2);

    // Place a peg order
    try book.placePegOrder(.Buy, 10, .BestBid, 1, null, 3);

    // Check if pegged correctly
    try testing.expectEqual(@as(u64, 99), try book.getOrderPrice(3));
}

test "Discretionary Orders" {
    const allocator = testing.allocator;
    const shard_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 4 else 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // Place a discretionary order with base price 100 and discretionary price 102
    try book.placeDiscretionaryOrder(.Buy, 100, 10, 1, 102);

    // Place matching sell orders
    try book.placeOrder(.Sell, 101, 5, 2);

    // Get the order and execute it
    const order = book.shards[book.priceToShard(100)].get(.{ .price = 100, .id = 1 }) orelse {
        std.debug.print("Failed to find discretionary order\n", .{});
        return error.OrderNotFound;
    };
    std.debug.print("Found discretionary order: base_price={}, discretionary_price={}, amount={}\n", .{
        order.price,
        order.discretionary_params.?.discretionary_price,
        order.amount,
    });

    // Set current order context
    book.current_order = &order;
    book.current_order_flags = order.flags;
    defer {
        book.current_order = null;
        book.current_order_flags = .{};
    }

    // Execute the discretionary order
    const result = try book.matchOrder(order.side, order.price, order.amount);
    std.debug.print("Match result: filled={}, remaining={}, price={}\n", .{
        result.filled_amount,
        result.remaining_amount,
        result.execution_price,
    });

    // Update the order in the book
    if (result.filled_amount > 0) {
        const key = orderbook.OrderKey{ .price = order.price, .id = order.id };
        const shard_index = book.priceToShard(order.price);
        const levels = if (order.side == .Buy) &book.bid_levels[shard_index] else &book.ask_levels[shard_index];

        if (result.remaining_amount == 0) {
            try book.updatePriceLevel(levels, order.price, -@as(i64, @intCast(order.amount)), -1);
            _ = book.shards[shard_index].swapRemove(key);
        } else {
            var updated_order = order;
            updated_order.amount = result.remaining_amount;
            try book.updatePriceLevel(levels, order.price, -@as(i64, @intCast(result.filled_amount)), 0);
            try book.shards[shard_index].put(key, updated_order);
        }
    }

    // Check execution - should have matched 5 at discretionary price
    const volume = try book.getVolume(.Buy, 100);
    std.debug.print("Volume at price 100: {}\n", .{volume});
    try testing.expectEqual(@as(u64, 5), volume);
}

test "Conditional Orders" {
    const allocator = testing.allocator;
    const shard_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 4 else 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // Place a conditional order
    try book.placeConditionalOrder(.Buy, 100, 10, 1, .Price, 102);

    // Place orders to test condition
    try book.placeOrder(.Sell, 101, 5, 2);
    try book.placeOrder(.Buy, 103, 1, 3);

    // Check execution
    try testing.expectEqual(@as(u64, 10), try book.getVolume(.Buy, 100));
}

test "Iceberg Orders" {
    const allocator = testing.allocator;
    const shard_count = if (std.process.getEnvVarOwned(allocator, "CI") catch null != null) 4 else 8;
    var book = try orderbook.ShardedOrderbook.init(allocator, shard_count);
    defer book.deinit();

    // Place an iceberg order
    try book.placeIcebergOrder(.Buy, 100, 100, 10, 1);

    // Check visible amount
    try testing.expectEqual(@as(u64, 10), try book.getVolume(.Buy, 100));
}
