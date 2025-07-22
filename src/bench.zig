const std = @import("std");
const orderbook = @import("orderbook.zig");
const order_params = @import("orderbook/order_params.zig");

const BenchmarkResult = struct {
    operation: []const u8,
    iterations: usize,
    total_time_ns: u64,
    avg_time_ns: u64,
    throughput: f64,
    latency_p50: u64 = 0,
    latency_p95: u64 = 0,
    latency_p99: u64 = 0,
};

const BenchmarkConfig = struct {
    num_shards: usize = 32,
    iterations: usize = 100_000,
    order_count: usize = 10_000,
    price_range: u64 = 1000,
    amount_range: u64 = 100,
    burst_size: usize = 1000,
    num_price_levels: usize = 100,
};

// Global order ID counter to ensure uniqueness across all benchmarks
var global_order_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

fn runBenchmark(
    comptime operation: []const u8,
    iterations: usize,
    func: anytype,
    args: anytype,
) !BenchmarkResult {
    var latencies = std.ArrayList(u64).init(std.heap.page_allocator);
    defer latencies.deinit();
    try latencies.ensureTotalCapacity(iterations);

    var total_time: u64 = 0;
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        timer.reset();
        try @call(.auto, func, args);
        const elapsed = timer.read();
        try latencies.append(elapsed);
        total_time += elapsed;
    }

    // Sort latencies for percentile calculation
    std.sort.heap(u64, latencies.items, {}, std.sort.asc(u64));

    const avg_time = total_time / iterations;
    const throughput = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);

    return BenchmarkResult{
        .operation = operation,
        .iterations = iterations,
        .total_time_ns = total_time,
        .avg_time_ns = avg_time,
        .throughput = throughput,
        .latency_p50 = latencies.items[iterations * 50 / 100],
        .latency_p95 = latencies.items[iterations * 95 / 100],
        .latency_p99 = latencies.items[iterations * 99 / 100],
    };
}

fn generateRandomOrder(rng: std.rand.Random, config: BenchmarkConfig, side: orderbook.OrderSide) orderbook.CacheAlignedOrder {
    const price = rng.uintAtMost(u64, config.price_range - 1) + 1;
    const amount = rng.uintAtMost(u64, config.amount_range - 1) + 1;
    const id = global_order_id.fetchAdd(1, .seq_cst); // Ensure unique IDs

    return orderbook.CacheAlignedOrder.init(
        price,
        amount,
        id,
        side,
        .Limit,
        null,
    );
}

fn benchPlaceOrders(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    const order_data = generateRandomOrder(rng, config, .Buy);
    try book.placeOrder(order_data.side, order_data.price, order_data.amount, order_data.id);
}

fn benchBurstOrders(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Create array of orders at same price level
    var orders = try std.ArrayList(orderbook.CacheAlignedOrder).initCapacity(std.heap.page_allocator, config.burst_size);
    defer orders.deinit();

    const price = rng.uintAtMost(u64, config.price_range - 1) + 1;
    var i: usize = 0;
    while (i < config.burst_size) : (i += 1) {
        const amount = rng.uintAtMost(u64, config.amount_range - 1) + 1;
        const id = global_order_id.fetchAdd(1, .seq_cst); // Use global counter
        const order_data = orderbook.CacheAlignedOrder.init(
            price,
            amount,
            id,
            .Buy,
            .Limit,
            null,
        );
        try orders.append(order_data);
    }

    // Bulk insert orders
    try book.bulkInsertOrders(.Buy, price, orders.items);
}

fn benchPriceLevelStress(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Create many price levels with few orders each
    var i: usize = 0;
    while (i < config.num_price_levels) : (i += 1) {
        const order_data = generateRandomOrder(rng, config, .Buy);
        try book.placeOrder(order_data.side, order_data.price, order_data.amount, order_data.id);
    }
}

fn benchCancelOrders(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    const order_data = generateRandomOrder(rng, config, .Buy);
    try book.placeOrder(order_data.side, order_data.price, order_data.amount, order_data.id);
    try book.cancelOrder(order_data.id);
}

fn benchMarketOrders(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Place some limit orders first
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const order_data = generateRandomOrder(rng, config, .Sell);
        try book.placeOrder(order_data.side, order_data.price, order_data.amount, order_data.id);
    }

    // Execute market order
    const market_order = generateRandomOrder(rng, config, .Buy);
    _ = try book.executeMarketOrder(.Buy, market_order.amount);
}

fn benchLargeMarketOrder(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Place many limit orders at different price levels
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const order_data = generateRandomOrder(rng, config, .Sell);
        try book.placeOrder(order_data.side, order_data.price, order_data.amount, order_data.id);
    }

    // Execute large market order that will match against many price levels
    const large_amount = config.amount_range * 100;
    _ = try book.executeMarketOrder(.Buy, large_amount);
}

fn benchMixedWorkload(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // 60% place, 30% cancel, 10% market orders
    const op = rng.uintAtMost(u64, 99);
    if (op < 60) {
        try benchPlaceOrders(book, config);
    } else if (op < 90) {
        try benchCancelOrders(book, config);
    } else {
        try benchMarketOrders(book, config);
    }
}

fn benchHighFrequencyWorkload(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Simulate HFT pattern: place+cancel or place+market
    const is_cancel = rng.boolean();
    const order_data = generateRandomOrder(rng, config, .Buy);
    try book.placeOrder(order_data.side, order_data.price, order_data.amount, order_data.id);

    if (is_cancel) {
        try book.cancelOrder(order_data.id);
    } else {
        _ = try book.executeMarketOrder(.Sell, order_data.amount);
    }
}

fn benchTWAPOrders(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Create TWAP order that executes over multiple intervals
    const total_amount = rng.uintAtMost(u64, config.amount_range * 10);
    const num_intervals = 5;
    const interval_seconds = 1;
    const id = global_order_id.fetchAdd(1, .seq_cst); // Use global counter

    try book.placeTWAPOrder(.Buy, config.price_range / 2, total_amount, id, num_intervals, interval_seconds);
}

fn benchStopOrders(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Place a stop order
    const price = rng.uintAtMost(u64, config.price_range - 1) + 1;
    const amount = rng.uintAtMost(u64, config.amount_range - 1) + 1;
    const id = global_order_id.fetchAdd(1, .seq_cst); // Use global counter
    const stop_price = price + rng.uintAtMost(u64, 100);

    try book.placeStopOrder(.Buy, price, amount, id, stop_price);
}

fn benchTrailingStopOrders(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Place a trailing stop order
    const price = rng.uintAtMost(u64, config.price_range - 1) + 1;
    const amount = rng.uintAtMost(u64, config.amount_range - 1) + 1;
    const id = global_order_id.fetchAdd(1, .seq_cst); // Use global counter
    const distance = rng.uintAtMost(u64, 50);

    try book.placeTrailingStopOrder(.Buy, price, amount, id, distance);
}

fn benchPegOrders(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Place a peg order
    const amount = rng.uintAtMost(u64, config.amount_range - 1) + 1;
    const id = global_order_id.fetchAdd(1, .seq_cst); // Use global counter
    const offset: i64 = @intCast(rng.uintAtMost(u64, 10));

    try book.placePegOrder(.Buy, amount, .BestBid, offset, null, id);
}

fn benchHFTBurstPattern(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Create array of orders at same price level with tight spreads
    var orders = try std.ArrayList(orderbook.CacheAlignedOrder).initCapacity(std.heap.page_allocator, config.burst_size);
    defer orders.deinit();

    const base_price = rng.uintAtMost(u64, config.price_range - 1) + 1;
    var i: usize = 0;
    while (i < config.burst_size) : (i += 1) {
        const price = base_price + rng.uintAtMost(u64, 5); // Tight spread
        const amount = rng.uintAtMost(u64, config.amount_range - 1) + 1;
        const id = global_order_id.fetchAdd(1, .seq_cst); // Use global counter
        const order_data = orderbook.CacheAlignedOrder.init(
            price,
            amount,
            id,
            .Buy,
            .Limit,
            null,
        );
        try orders.append(order_data);
    }

    // Bulk insert orders
    try book.bulkInsertOrders(.Buy, base_price, orders.items);
}

fn benchHFTSpreadPattern(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Place multiple orders at different price levels with tight spreads
    const base_price = rng.uintAtMost(u64, config.price_range - 1) + 1;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const price = base_price + i;
        const amount = rng.uintAtMost(u64, config.amount_range - 1) + 1;
        const id = global_order_id.fetchAdd(1, .seq_cst); // Use global counter
        try book.placeOrder(.Buy, price, amount, id);
    }

    // Execute market order to test spread crossing
    const market_amount = rng.uintAtMost(u64, config.amount_range * 5);
    _ = try book.executeMarketOrder(.Sell, market_amount);
}

fn benchICEPattern(book: *orderbook.ShardedOrderbook, config: BenchmarkConfig) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rng = prng.random();

    // Place iceberg order
    const price = rng.uintAtMost(u64, config.price_range - 1) + 1;
    const total_amount = rng.uintAtMost(u64, config.amount_range * 10);
    const display_amount = total_amount / 10;
    const id = global_order_id.fetchAdd(1, .seq_cst); // Use global counter

    try book.placeIcebergOrder(.Buy, price, total_amount, display_amount, id);
}

pub fn main() !void {
    try runBenchmarks();
}

pub fn runBenchmarks() !void {
    const config = BenchmarkConfig{};
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize orderbook
    var book = try orderbook.ShardedOrderbook.init(allocator, config.num_shards);
    defer book.deinit();

    // Reset global order ID counter for consistent benchmarking
    global_order_id.store(1, .seq_cst);

    // Run benchmarks
    const benchmarks = comptime [_]struct {
        name: []const u8,
        func: fn (*orderbook.ShardedOrderbook, BenchmarkConfig) anyerror!void,
    }{
        .{ .name = "Place Orders", .func = benchPlaceOrders },
        .{ .name = "Burst Orders", .func = benchBurstOrders },
        .{ .name = "Price Level Stress", .func = benchPriceLevelStress },
        .{ .name = "Cancel Orders", .func = benchCancelOrders },
        .{ .name = "Market Orders", .func = benchMarketOrders },
        .{ .name = "Large Market Orders", .func = benchLargeMarketOrder },
        .{ .name = "Mixed Workload", .func = benchMixedWorkload },
        .{ .name = "HFT Workload", .func = benchHighFrequencyWorkload },
        .{ .name = "TWAP Orders", .func = benchTWAPOrders },
        .{ .name = "Stop Orders", .func = benchStopOrders },
        .{ .name = "Trailing Stop Orders", .func = benchTrailingStopOrders },
        .{ .name = "Peg Orders", .func = benchPegOrders },
        .{ .name = "HFT Burst Pattern", .func = benchHFTBurstPattern },
        .{ .name = "HFT Spread Pattern", .func = benchHFTSpreadPattern },
        .{ .name = "ICE Pattern", .func = benchICEPattern },
    };

    // Print header
    std.debug.print("\nOrderbook Benchmark Results:\n", .{});
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  Shards: {d}\n", .{config.num_shards});
    std.debug.print("  Iterations: {d}\n", .{config.iterations});
    std.debug.print("  Order Count: {d}\n", .{config.order_count});
    std.debug.print("  Burst Size: {d}\n", .{config.burst_size});
    std.debug.print("  Price Levels: {d}\n", .{config.num_price_levels});
    std.debug.print("\n{s:<25} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n", .{ "Operation", "Avg (µs)", "P50 (µs)", "P95 (µs)", "P99 (µs)", "Ops/sec", "Total (ms)" });

    // Run and print results
    inline for (benchmarks) |bench| {
        const result = try runBenchmark(
            bench.name,
            config.iterations,
            bench.func,
            .{ &book, config },
        );

        std.debug.print("{s:<25} {d:>12.2} {d:>12.2} {d:>12.2} {d:>12.2} {d:>12.2} {d:>12.2}\n", .{
            result.operation,
            @as(f64, @floatFromInt(result.avg_time_ns)) / 1000.0,
            @as(f64, @floatFromInt(result.latency_p50)) / 1000.0,
            @as(f64, @floatFromInt(result.latency_p95)) / 1000.0,
            @as(f64, @floatFromInt(result.latency_p99)) / 1000.0,
            result.throughput,
            @as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000.0,
        });
    }
}
