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
    latency_p999: u64 = 0,
    min_latency: u64 = 0,
    max_latency: u64 = 0,
    std_deviation: f64 = 0,
    
    pub fn isWithinTarget(self: *const BenchmarkResult, target: PerformanceTarget) bool {
        return self.latency_p99 <= target.max_p99_latency_ns and
               self.throughput >= target.min_throughput_ops_sec;
    }
    
    pub fn printSummary(self: *const BenchmarkResult) void {
        std.debug.print("=== {s} Performance Summary ===\n", .{self.operation});
        std.debug.print("  Iterations: {d}\n", .{self.iterations});
        std.debug.print("  Total Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0});
        std.debug.print("  Latency Stats (µs):\n");
        std.debug.print("    Min: {d:.2}\n", .{@as(f64, @floatFromInt(self.min_latency)) / 1000.0});
        std.debug.print("    Avg: {d:.2}\n", .{@as(f64, @floatFromInt(self.avg_time_ns)) / 1000.0});
        std.debug.print("    P50: {d:.2}\n", .{@as(f64, @floatFromInt(self.latency_p50)) / 1000.0});
        std.debug.print("    P95: {d:.2}\n", .{@as(f64, @floatFromInt(self.latency_p95)) / 1000.0});
        std.debug.print("    P99: {d:.2}\n", .{@as(f64, @floatFromInt(self.latency_p99)) / 1000.0});
        std.debug.print("    P99.9: {d:.2}\n", .{@as(f64, @floatFromInt(self.latency_p999)) / 1000.0});
        std.debug.print("    Max: {d:.2}\n", .{@as(f64, @floatFromInt(self.max_latency)) / 1000.0});
        std.debug.print("    StdDev: {d:.2}\n", .{self.std_deviation / 1000.0});
        std.debug.print("  Throughput: {d:.0} ops/sec\n", .{self.throughput});
        std.debug.print("\n");
    }
};

const PerformanceTarget = struct {
    max_p99_latency_ns: u64,
    min_throughput_ops_sec: f64,
};

const BenchmarkConfig = struct {
    num_shards: usize = 32,
    iterations: usize = 100_000,
    order_count: usize = 10_000,
    price_range: u64 = 1000,
    amount_range: u64 = 100,
    burst_size: usize = 1000,
    num_price_levels: usize = 100,

    // CI-optimized configuration with reduced memory usage
    fn forCI() BenchmarkConfig {
        return BenchmarkConfig{
            .num_shards = 4, // Reduced from 32
            .iterations = 1_000, // Reduced from 100_000
            .order_count = 1_000, // Reduced from 10_000
            .price_range = 100, // Reduced from 1000
            .amount_range = 50, // Reduced from 100
            .burst_size = 100, // Reduced from 1000
            .num_price_levels = 20, // Reduced from 100
        };
    }

    fn getConfig() BenchmarkConfig {
        // Check if running in CI environment
        const ci_env = std.process.getEnvVarOwned(std.heap.page_allocator, "CI") catch null;
        defer if (ci_env) |env| std.heap.page_allocator.free(env);

        const github_actions = std.process.getEnvVarOwned(std.heap.page_allocator, "GITHUB_ACTIONS") catch null;
        defer if (github_actions) |env| std.heap.page_allocator.free(env);

        if (ci_env != null or github_actions != null) {
            return BenchmarkConfig.forCI();
        }

        return BenchmarkConfig{};
    }
    
    fn getPerformanceTargets(self: *const BenchmarkConfig) PerformanceTargets {
        const is_ci = self.num_shards < 32;
        
        return PerformanceTargets{
            .place_orders = .{
                .max_p99_latency_ns = if (is_ci) 20_000 else 5_000, // 20µs CI, 5µs production
                .min_throughput_ops_sec = if (is_ci) 10_000 else 200_000,
            },
            .cancel_orders = .{
                .max_p99_latency_ns = if (is_ci) 15_000 else 4_000, // 15µs CI, 4µs production
                .min_throughput_ops_sec = if (is_ci) 15_000 else 250_000,
            },
            .market_orders = .{
                .max_p99_latency_ns = if (is_ci) 50_000 else 10_000, // 50µs CI, 10µs production
                .min_throughput_ops_sec = if (is_ci) 5_000 else 100_000,
            },
            .bulk_operations = .{
                .max_p99_latency_ns = if (is_ci) 10_000 else 3_000, // 10µs CI, 3µs production per order
                .min_throughput_ops_sec = if (is_ci) 20_000 else 500_000,
            },
        };
    }
};

const PerformanceTargets = struct {
    place_orders: PerformanceTarget,
    cancel_orders: PerformanceTarget,
    market_orders: PerformanceTarget,
    bulk_operations: PerformanceTarget,
    
    fn getTargetForOperation(self: *const PerformanceTargets, operation: []const u8) ?PerformanceTarget {
        if (std.mem.eql(u8, operation, "Place Orders")) return self.place_orders;
        if (std.mem.eql(u8, operation, "Cancel Orders")) return self.cancel_orders;
        if (std.mem.eql(u8, operation, "Market Orders")) return self.market_orders;
        if (std.mem.eql(u8, operation, "Burst Orders")) return self.bulk_operations;
        if (std.mem.eql(u8, operation, "HFT Burst Pattern")) return self.bulk_operations;
        return null;
    }
};

// Global order ID counter to ensure uniqueness across all benchmarks
var global_order_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

fn runBenchmark(
    comptime operation: []const u8,
    iterations: usize,
    func: anytype,
    args: anytype,
) !BenchmarkResult {
    // Use arena allocator for temporary memory management
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // For large iteration counts, sample only a subset for percentile calculation
    const sample_size = @min(iterations, 10_000);
    const sample_interval = @max(1, iterations / sample_size);

    var latencies = std.ArrayList(u64).init(allocator);
    try latencies.ensureTotalCapacity(sample_size);

    var total_time: u64 = 0;
    var min_latency: u64 = std.math.maxInt(u64);
    var max_latency: u64 = 0;
    var timer = try std.time.Timer.start();

    // Warmup phase - 10% of iterations or 100, whichever is smaller
    const warmup_iterations = @min(iterations / 10, 100);
    var warmup_i: usize = 0;
    while (warmup_i < warmup_iterations) : (warmup_i += 1) {
        timer.reset();
        try @call(.auto, func, args);
        _ = timer.read(); // Discard warmup results
    }

    // Actual benchmark measurement
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        timer.reset();
        try @call(.auto, func, args);
        const elapsed = timer.read();

        min_latency = @min(min_latency, elapsed);
        max_latency = @max(max_latency, elapsed);

        // Only collect latency samples at intervals to reduce memory usage
        if (i % sample_interval == 0) {
            try latencies.append(elapsed);
        }
        total_time += elapsed;
    }

    // Sort latencies for percentile calculation
    std.sort.heap(u64, latencies.items, {}, std.sort.asc(u64));

    const avg_time = total_time / iterations;
    const throughput = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);

    // Calculate standard deviation
    var variance_sum: f64 = 0;
    for (latencies.items) |latency| {
        const diff = @as(f64, @floatFromInt(latency)) - @as(f64, @floatFromInt(avg_time));
        variance_sum += diff * diff;
    }
    const variance = variance_sum / @as(f64, @floatFromInt(latencies.items.len));
    const std_deviation = @sqrt(variance);

    const sample_count = latencies.items.len;
    return BenchmarkResult{
        .operation = operation,
        .iterations = iterations,
        .total_time_ns = total_time,
        .avg_time_ns = avg_time,
        .throughput = throughput,
        .latency_p50 = if (sample_count > 0) latencies.items[sample_count * 50 / 100] else 0,
        .latency_p95 = if (sample_count > 0) latencies.items[sample_count * 95 / 100] else 0,
        .latency_p99 = if (sample_count > 0) latencies.items[sample_count * 99 / 100] else 0,
        .latency_p999 = if (sample_count > 0) latencies.items[@min(sample_count * 999 / 1000, sample_count - 1)] else 0,
        .min_latency = min_latency,
        .max_latency = max_latency,
        .std_deviation = std_deviation,
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

    // Use arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create smaller array of orders at same price level
    var orders = try std.ArrayList(orderbook.CacheAlignedOrder).initCapacity(allocator, config.burst_size);

    const price = rng.uintAtMost(u64, config.price_range - 1) + 1;
    var i: usize = 0;
    while (i < config.burst_size) : (i += 1) {
        const amount = rng.uintAtMost(u64, config.amount_range - 1) + 1;
        const id = global_order_id.fetchAdd(1, .seq_cst);
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

    // Use arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create smaller array of orders at same price level with tight spreads
    var orders = try std.ArrayList(orderbook.CacheAlignedOrder).initCapacity(allocator, config.burst_size);

    const base_price = rng.uintAtMost(u64, config.price_range - 1) + 1;
    var i: usize = 0;
    while (i < config.burst_size) : (i += 1) {
        const price = base_price + rng.uintAtMost(u64, 5); // Tight spread
        const amount = rng.uintAtMost(u64, config.amount_range - 1) + 1;
        const id = global_order_id.fetchAdd(1, .seq_cst);
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
    const config = BenchmarkConfig.getConfig(); // Use CI-optimized config when detected
    const targets = config.getPerformanceTargets();
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize orderbook with reduced shards for CI
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

    // Print header with CI status
    const ci_detected = config.num_shards < 32;
    std.debug.print("\nAbyssbook Orderbook Benchmark Results{s}:\n", .{if (ci_detected) " (CI Optimized)" else ""});
    std.debug.print("=".** 60 ++ "\n");
    std.debug.print("Configuration:\n");
    std.debug.print("  Shards: {d}\n", .{config.num_shards});
    std.debug.print("  Iterations: {d}\n", .{config.iterations});
    std.debug.print("  Order Count: {d}\n", .{config.order_count});
    std.debug.print("  Burst Size: {d}\n", .{config.burst_size});
    std.debug.print("  Price Levels: {d}\n", .{config.num_price_levels});
    std.debug.print("  Environment: {s}\n", .{if (ci_detected) "CI/Testing" else "Production"});
    std.debug.print("\n");

    // Print table header
    std.debug.print("{s:<25} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>10}\n", .{ 
        "Operation", "Avg (µs)", "P50 (µs)", "P95 (µs)", "P99 (µs)", "Ops/sec", "Total (ms)", "Status" 
    });
    std.debug.print("-".** 105 ++ "\n");

    var results = std.ArrayList(BenchmarkResult).init(allocator);
    defer results.deinit();
    
    var passed_count: usize = 0;
    var failed_count: usize = 0;

    // Run and print results with memory cleanup between benchmarks
    inline for (benchmarks) |bench| {
        // Reset orderbook state before each benchmark to limit memory growth
        // Use clearRetainingCapacity to preserve allocated memory while clearing data
        for (0..book.shards.len) |i| {
            book.shards[i].clearRetainingCapacity();
            book.bid_levels[i].clearRetainingCapacity();
            book.ask_levels[i].clearRetainingCapacity();
            book.stop_orders[i].clearRetainingCapacity();
        }
        book.best_bid_cache = null;
        book.best_ask_cache = null;
        global_order_id.store(1, .seq_cst);

        const result = try runBenchmark(
            bench.name,
            config.iterations,
            bench.func,
            .{ &book, config },
        );

        try results.append(result);

        // Check against performance targets
        const target = targets.getTargetForOperation(bench.name);
        const status = if (target) |t| 
            if (result.isWithinTarget(t)) "PASS" else "FAIL"
        else 
            "N/A";
            
        if (target != null and result.isWithinTarget(target.?)) {
            passed_count += 1;
        } else if (target != null) {
            failed_count += 1;
        }

        std.debug.print("{s:<25} {d:>12.2} {d:>12.2} {d:>12.2} {d:>12.2} {d:>12.0} {d:>12.2} {s:>10}\n", .{
            result.operation,
            @as(f64, @floatFromInt(result.avg_time_ns)) / 1000.0,
            @as(f64, @floatFromInt(result.latency_p50)) / 1000.0,
            @as(f64, @floatFromInt(result.latency_p95)) / 1000.0,
            @as(f64, @floatFromInt(result.latency_p99)) / 1000.0,
            result.throughput,
            @as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000.0,
            status,
        });
    }
    
    // Print summary
    std.debug.print("\n" ++ "=".** 60 ++ "\n");
    std.debug.print("Benchmark Summary:\n");
    std.debug.print("  Total benchmarks: {d}\n", .{benchmarks.len});
    std.debug.print("  Passed targets: {d}\n", .{passed_count});
    std.debug.print("  Failed targets: {d}\n", .{failed_count});
    std.debug.print("  Success rate: {d:.1}%\n", .{@as(f64, @floatFromInt(passed_count)) / @as(f64, @floatFromInt(passed_count + failed_count)) * 100.0});
    
    // Print detailed results for failed benchmarks
    if (failed_count > 0) {
        std.debug.print("\nDetailed Analysis for Failed Benchmarks:\n");
        std.debug.print("-".** 60 ++ "\n");
        for (results.items) |result| {
            if (targets.getTargetForOperation(result.operation)) |target| {
                if (!result.isWithinTarget(target)) {
                    result.printSummary();
                    std.debug.print("  Target P99: {d:.2} µs (Actual: {d:.2} µs)\n", .{
                        @as(f64, @floatFromInt(target.max_p99_latency_ns)) / 1000.0,
                        @as(f64, @floatFromInt(result.latency_p99)) / 1000.0,
                    });
                    std.debug.print("  Target Throughput: {d:.0} ops/sec (Actual: {d:.0} ops/sec)\n", .{
                        target.min_throughput_ops_sec,
                        result.throughput,
                    });
                    std.debug.print("\n");
                }
            }
        }
    }
    
    // Export results for CI integration (future enhancement)
    try exportBenchmarkResults(allocator, results.items, config);
}

// Export benchmark results for CI integration and historical tracking
fn exportBenchmarkResults(allocator: std.mem.Allocator, results: []const BenchmarkResult, config: BenchmarkConfig) !void {
    // Create results directory if it doesn't exist
    std.fs.cwd().makeDir("benchmark_results") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            std.log.err("Failed to create benchmark_results directory: {}", .{err});
            return err;
        }
    };
    
    // Generate timestamp for filename
    const timestamp = std.time.timestamp();
    const filename = try std.fmt.allocPrint(allocator, "benchmark_results/results_{d}.json", .{timestamp});
    defer allocator.free(filename);
    
    const file = std.fs.cwd().createFile(filename, .{}) catch |err| {
        std.log.err("Failed to create benchmark results file {s}: {}", .{filename, err});
        return err;
    };
    defer file.close();
    
    var writer = file.writer();
    
    // Write JSON with proper error handling
    writeJSON(&writer, results, config, timestamp) catch |err| {
        std.log.err("Failed to write JSON to {s}: {}", .{filename, err});
        return err;
    };
    
    std.debug.print("Benchmark results exported to: {s}\n", .{filename});
}

fn writeJSON(writer: anytype, results: []const BenchmarkResult, config: BenchmarkConfig, timestamp: i64) !void {
    try writer.writeAll("{\n");
    try writer.print("  \"timestamp\": {d},\n", .{timestamp});
    try writer.print("  \"config\": {{\n");
    try writer.print("    \"num_shards\": {d},\n", .{config.num_shards});
    try writer.print("    \"iterations\": {d},\n", .{config.iterations});
    try writer.print("    \"order_count\": {d},\n", .{config.order_count});
    try writer.print("    \"price_range\": {d},\n", .{config.price_range});
    try writer.print("    \"amount_range\": {d},\n", .{config.amount_range});
    try writer.print("    \"burst_size\": {d},\n", .{config.burst_size});
    try writer.print("    \"num_price_levels\": {d}\n", .{config.num_price_levels});
    try writer.writeAll("  },\n");
    try writer.writeAll("  \"results\": [\n");
    
    // Write benchmark results
    for (results, 0..) |result, i| {
        try writer.writeAll("    {\n");
        try writer.print("      \"operation\": \"{s}\",\n", .{result.operation});
        try writer.print("      \"iterations\": {d},\n", .{result.iterations});
        try writer.print("      \"total_time_ns\": {d},\n", .{result.total_time_ns});
        try writer.print("      \"avg_time_ns\": {d},\n", .{result.avg_time_ns});
        try writer.print("      \"throughput\": {d:.2},\n", .{result.throughput});
        try writer.print("      \"latency_p50\": {d},\n", .{result.latency_p50});
        try writer.print("      \"latency_p95\": {d},\n", .{result.latency_p95});
        try writer.print("      \"latency_p99\": {d},\n", .{result.latency_p99});
        try writer.print("      \"latency_p999\": {d},\n", .{result.latency_p999});
        try writer.print("      \"min_latency\": {d},\n", .{result.min_latency});
        try writer.print("      \"max_latency\": {d},\n", .{result.max_latency});
        try writer.print("      \"std_deviation\": {d:.2}\n", .{result.std_deviation});
        if (i < results.len - 1) {
            try writer.writeAll("    },\n");
        } else {
            try writer.writeAll("    }\n");
        }
    }
    
    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");
}
