const std = @import("std");
const orderbook = @import("orderbook.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize book
    var book = try orderbook.ShardedOrderbook.init(allocator, 32);
    defer book.deinit();

    const order_count = 1_000_000;
    var timer = try std.time.Timer.start();
    var rng = std.rand.DefaultPrng.init(0);
    const random = rng.random();

    // Benchmark order placement
    {
        timer.reset();
        for (0..order_count) |i| {
            const side = if (random.boolean()) orderbook.OrderSide.Buy else orderbook.OrderSide.Sell;
            const price = random.uintLessThan(u64, 1000) + 9000; // Price range 9000-10000
            const amount = random.uintLessThan(u64, 100) + 1;
            try book.placeOrder(side, price, amount, i);
        }
        const elapsed = timer.read();
        const ops_per_sec = @as(f64, @floatFromInt(order_count)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
        std.debug.print("Order placement: {d:.2} ops/sec\n", .{ops_per_sec});
    }

    // Benchmark order cancellation
    {
        timer.reset();
        for (0..order_count) |i| {
            if (random.boolean()) {
                _ = book.cancelOrder(i) catch {};
            }
        }
        const elapsed = timer.read();
        const ops_per_sec = @as(f64, @floatFromInt(order_count)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
        std.debug.print("Order cancellation: {d:.2} ops/sec\n", .{ops_per_sec});
    }

    // Benchmark market orders
    {
        timer.reset();
        const market_order_count = order_count / 10;
        for (0..market_order_count) |_| {
            const side = if (random.boolean()) orderbook.OrderSide.Buy else orderbook.OrderSide.Sell;
            const amount = random.uintLessThan(u64, 100) + 1;
            _ = try book.executeMarketOrder(side, amount);
        }
        const elapsed = timer.read();
        const ops_per_sec = @as(f64, @floatFromInt(market_order_count)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
        std.debug.print("Market orders: {d:.2} ops/sec\n", .{ops_per_sec});
    }

    // Benchmark stop orders
    {
        timer.reset();
        const stop_order_count = order_count / 10;
        for (0..stop_order_count) |i| {
            const side = if (random.boolean()) orderbook.OrderSide.Buy else orderbook.OrderSide.Sell;
            const price = random.uintLessThan(u64, 1000) + 9000;
            const amount = random.uintLessThan(u64, 100) + 1;
            const stop_price = if (side == .Buy)
                price + random.uintLessThan(u64, 100)
            else
                price - random.uintLessThan(u64, 100);
            try book.placeStopOrder(side, price, amount, order_count + i, stop_price);
        }
        const elapsed = timer.read();
        const ops_per_sec = @as(f64, @floatFromInt(stop_order_count)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
        std.debug.print("Stop orders: {d:.2} ops/sec\n", .{ops_per_sec});
    }

    // Benchmark order matching
    {
        timer.reset();
        const match_count = order_count / 10;
        for (0..match_count) |_| {
            const side = if (random.boolean()) orderbook.OrderSide.Buy else orderbook.OrderSide.Sell;
            const price = random.uintLessThan(u64, 1000) + 9000;
            const amount = random.uintLessThan(u64, 100) + 1;
            _ = try book.matchOrder(side, price, amount);
        }
        const elapsed = timer.read();
        const ops_per_sec = @as(f64, @floatFromInt(match_count)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
        std.debug.print("Order matching: {d:.2} ops/sec\n", .{ops_per_sec});
    }

    // Benchmark volume queries
    {
        timer.reset();
        const query_count = order_count;
        for (0..query_count) |_| {
            const side = if (random.boolean()) orderbook.OrderSide.Buy else orderbook.OrderSide.Sell;
            const price = random.uintLessThan(u64, 1000) + 9000;
            _ = try book.getVolume(side, price);
        }
        const elapsed = timer.read();
        const ops_per_sec = @as(f64, @floatFromInt(query_count)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
        std.debug.print("Volume queries: {d:.2} ops/sec\n", .{ops_per_sec});
    }

    // Benchmark best bid/ask queries
    {
        timer.reset();
        const query_count = order_count;
        for (0..query_count) |_| {
            _ = book.getBestBid();
            _ = book.getBestAsk();
        }
        const elapsed = timer.read();
        const ops_per_sec = @as(f64, @floatFromInt(query_count * 2)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
        std.debug.print("Best bid/ask queries: {d:.2} ops/sec\n", .{ops_per_sec});
    }

    // Benchmark depth queries
    {
        timer.reset();
        const query_count = order_count / 100;
        for (0..query_count) |_| {
            const depth = book.getDepth(10);
            allocator.free(depth.bids);
            allocator.free(depth.asks);
        }
        const elapsed = timer.read();
        const ops_per_sec = @as(f64, @floatFromInt(query_count)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
        std.debug.print("Depth queries: {d:.2} ops/sec\n", .{ops_per_sec});
    }
}
