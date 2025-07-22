const std = @import("std");
const testing = std.testing;
const Thread = std.Thread;
const orderbook = @import("../orderbook.zig");
const logging = @import("../logging.zig");

/// Enhanced concurrency stress tests under real workload scenarios
pub const ConcurrencyStressTests = struct {
    const WorkloadConfig = struct {
        thread_count: u32 = 8,
        operations_per_thread: u32 = 10000,
        order_mix: OrderMix = .{},
        price_range: PriceRange = .{ .min = 90.0, .max = 110.0 },
        duration_seconds: u32 = 30,
        memory_pressure: bool = false,
    };

    const OrderMix = struct {
        market_orders: f32 = 0.3,
        limit_orders: f32 = 0.5,
        stop_orders: f32 = 0.1,
        cancel_orders: f32 = 0.1,
    };

    const PriceRange = struct {
        min: f64,
        max: f64,
    };

    const WorkerContext = struct {
        thread_id: u32,
        orderbook_ref: *orderbook.OrderBook,
        config: WorkloadConfig,
        orders_processed: std.atomic.Value(u64),
        errors_encountered: std.atomic.Value(u64),
        latency_samples: std.ArrayList(u64),
        allocator: std.mem.Allocator,
        random: std.rand.Random,
        should_stop: *std.atomic.Value(bool),

        pub fn init(allocator: std.mem.Allocator, thread_id: u32, ob: *orderbook.OrderBook, config: WorkloadConfig, should_stop: *std.atomic.Value(bool)) !WorkerContext {
            var prng = std.rand.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())) + thread_id);

            return WorkerContext{
                .thread_id = thread_id,
                .orderbook_ref = ob,
                .config = config,
                .orders_processed = std.atomic.Value(u64).init(0),
                .errors_encountered = std.atomic.Value(u64).init(0),
                .latency_samples = std.ArrayList(u64).init(allocator),
                .allocator = allocator,
                .random = prng.random(),
                .should_stop = should_stop,
            };
        }

        pub fn deinit(self: *WorkerContext) void {
            self.latency_samples.deinit();
        }
    };

    /// High-frequency trading simulation
    pub fn testHighFrequencyTrading() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var ob = try orderbook.OrderBook.init(allocator);
        defer ob.deinit();

        const config = WorkloadConfig{
            .thread_count = 16,
            .operations_per_thread = 50000,
            .order_mix = .{
                .market_orders = 0.6, // High market order ratio
                .limit_orders = 0.3,
                .stop_orders = 0.05,
                .cancel_orders = 0.05,
            },
            .price_range = .{ .min = 99.0, .max = 101.0 }, // Tight spread
            .duration_seconds = 10,
        };

        try runConcurrencyTest(allocator, &ob, config, "High-Frequency Trading");
    }

    /// Market maker simulation with continuous liquidity provision
    pub fn testMarketMakerWorkload() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var ob = try orderbook.OrderBook.init(allocator);
        defer ob.deinit();

        const config = WorkloadConfig{
            .thread_count = 4,
            .operations_per_thread = 25000,
            .order_mix = .{
                .market_orders = 0.1, // Low market order ratio
                .limit_orders = 0.8, // High limit order ratio for liquidity
                .stop_orders = 0.05,
                .cancel_orders = 0.05,
            },
            .price_range = .{ .min = 95.0, .max = 105.0 }, // Wide spread for market making
            .duration_seconds = 15,
        };

        try runConcurrencyTest(allocator, &ob, config, "Market Maker Workload");
    }

    /// Stress test with memory pressure
    pub fn testMemoryPressureScenario() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var ob = try orderbook.OrderBook.init(allocator);
        defer ob.deinit();

        const config = WorkloadConfig{
            .thread_count = 12,
            .operations_per_thread = 30000,
            .order_mix = .{
                .market_orders = 0.2,
                .limit_orders = 0.7,
                .stop_orders = 0.05,
                .cancel_orders = 0.05,
            },
            .price_range = .{ .min = 80.0, .max = 120.0 }, // Wide range for more order levels
            .duration_seconds = 20,
            .memory_pressure = true,
        };

        try runConcurrencyTest(allocator, &ob, config, "Memory Pressure Scenario");
    }

    /// Mixed workload simulation (realistic trading scenario)
    pub fn testMixedWorkloadScenario() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var ob = try orderbook.OrderBook.init(allocator);
        defer ob.deinit();

        const config = WorkloadConfig{
            .thread_count = 8,
            .operations_per_thread = 40000,
            .order_mix = .{
                .market_orders = 0.25,
                .limit_orders = 0.55,
                .stop_orders = 0.1,
                .cancel_orders = 0.1,
            },
            .price_range = .{ .min = 90.0, .max = 110.0 },
            .duration_seconds = 25,
        };

        try runConcurrencyTest(allocator, &ob, config, "Mixed Workload Scenario");
    }

    /// Core concurrency test runner
    fn runConcurrencyTest(allocator: std.mem.Allocator, ob: *orderbook.OrderBook, config: WorkloadConfig, test_name: []const u8) !void {
        std.debug.print("\n=== {s} Concurrency Test ===\n", .{test_name});
        std.debug.print("Threads: {d}, Ops/Thread: {d}, Duration: {d}s\n", .{ config.thread_count, config.operations_per_thread, config.duration_seconds });

        var should_stop = std.atomic.Value(bool).init(false);
        var threads = try allocator.alloc(Thread, config.thread_count);
        defer allocator.free(threads);

        var workers = try allocator.alloc(WorkerContext, config.thread_count);
        defer {
            for (workers) |*worker| {
                worker.deinit();
            }
            allocator.free(workers);
        }

        // Initialize workers
        for (workers, 0..) |*worker, i| {
            worker.* = try WorkerContext.init(allocator, @as(u32, @intCast(i)), ob, config, &should_stop);
        }

        const start_time = std.time.milliTimestamp();

        // Spawn worker threads
        for (threads, 0..) |*thread, i| {
            thread.* = try Thread.spawn(.{}, workerThread, .{&workers[i]});
        }

        // Let test run for specified duration
        std.time.sleep(@as(u64, config.duration_seconds) * std.time.ns_per_s);

        // Signal stop
        should_stop.store(true, .seq_cst);

        // Wait for all threads to complete
        for (threads) |thread| {
            thread.join();
        }

        const end_time = std.time.milliTimestamp();
        const duration_ms = end_time - start_time;

        // Collect and analyze results
        try analyzeResults(workers, duration_ms, test_name);
    }

    /// Worker thread function
    fn workerThread(worker: *WorkerContext) void {
        var global_order_id = std.atomic.Value(u64).init(worker.thread_id * 1000000);

        while (!worker.should_stop.load(.acquire)) {
            const start_ns = std.time.nanoTimestamp();

            const operation_type = worker.random.float(f32);
            var success = false;

            if (operation_type < worker.config.order_mix.market_orders) {
                success = processMarketOrder(worker, &global_order_id);
            } else if (operation_type < worker.config.order_mix.market_orders + worker.config.order_mix.limit_orders) {
                success = processLimitOrder(worker, &global_order_id);
            } else if (operation_type < worker.config.order_mix.market_orders + worker.config.order_mix.limit_orders + worker.config.order_mix.stop_orders) {
                success = processStopOrder(worker, &global_order_id);
            } else {
                success = processCancelOrder(worker);
            }

            const end_ns = std.time.nanoTimestamp();
            const latency_ns = end_ns - start_ns;

            // Sample latency (store every 100th sample to avoid memory issues)
            if (worker.orders_processed.load(.acquire) % 100 == 0) {
                worker.latency_samples.append(@as(u64, @intCast(latency_ns))) catch {};
            }

            if (success) {
                _ = worker.orders_processed.fetchAdd(1, .acq_rel);
            } else {
                _ = worker.errors_encountered.fetchAdd(1, .acq_rel);
            }

            // Add memory pressure if configured
            if (worker.config.memory_pressure and worker.orders_processed.load(.acquire) % 1000 == 0) {
                const temp_buffer = worker.allocator.alloc(u8, 64 * 1024) catch continue;
                defer worker.allocator.free(temp_buffer);
                std.time.sleep(1 * std.time.ns_per_ms); // Brief pause
            }
        }
    }

    fn processMarketOrder(worker: *WorkerContext, global_order_id: *std.atomic.Value(u64)) bool {
        const order_id = global_order_id.fetchAdd(1, .acq_rel);
        const is_buy = worker.random.boolean();
        const quantity = worker.random.intRangeAtMost(u64, 1, 1000);

        worker.orderbook_ref.placeMarketOrder(order_id, is_buy, quantity) catch return false;
        return true;
    }

    fn processLimitOrder(worker: *WorkerContext, global_order_id: *std.atomic.Value(u64)) bool {
        const order_id = global_order_id.fetchAdd(1, .acq_rel);
        const is_buy = worker.random.boolean();
        const quantity = worker.random.intRangeAtMost(u64, 1, 1000);
        const price_range = worker.config.price_range.max - worker.config.price_range.min;
        const price = worker.config.price_range.min + worker.random.float(f64) * price_range;

        worker.orderbook_ref.placeLimitOrder(order_id, is_buy, quantity, price) catch return false;
        return true;
    }

    fn processStopOrder(worker: *WorkerContext, global_order_id: *std.atomic.Value(u64)) bool {
        const order_id = global_order_id.fetchAdd(1, .acq_rel);
        const is_buy = worker.random.boolean();
        const quantity = worker.random.intRangeAtMost(u64, 1, 1000);
        const price_range = worker.config.price_range.max - worker.config.price_range.min;
        const stop_price = worker.config.price_range.min + worker.random.float(f64) * price_range;

        worker.orderbook_ref.placeStopOrder(order_id, is_buy, quantity, stop_price) catch return false;
        return true;
    }

    fn processCancelOrder(worker: *WorkerContext) bool {
        // Try to cancel a random order (simplified)
        const random_order_id = worker.random.intRangeAtMost(u64, 1, 1000);
        worker.orderbook_ref.cancelOrder(random_order_id) catch return false;
        return true;
    }

    /// Analyze and report test results
    fn analyzeResults(workers: []WorkerContext, duration_ms: i64, test_name: []const u8) !void {
        var total_operations: u64 = 0;
        var total_errors: u64 = 0;
        var min_latency: u64 = std.math.maxInt(u64);
        var max_latency: u64 = 0;
        var total_latency: u64 = 0;
        var sample_count: u64 = 0;

        for (workers) |worker| {
            const ops = worker.orders_processed.load(.acquire);
            const errors = worker.errors_encountered.load(.acquire);

            total_operations += ops;
            total_errors += errors;

            // Analyze latency samples
            for (worker.latency_samples.items) |latency| {
                min_latency = @min(min_latency, latency);
                max_latency = @max(max_latency, latency);
                total_latency += latency;
                sample_count += 1;
            }
        }

        const throughput = (total_operations * 1000) / @as(u64, @intCast(duration_ms));
        const error_rate = if (total_operations > 0) (@as(f64, @floatFromInt(total_errors)) / @as(f64, @floatFromInt(total_operations))) * 100.0 else 0.0;
        const avg_latency = if (sample_count > 0) total_latency / sample_count else 0;

        std.debug.print("\n=== {s} Results ===\n", .{test_name});
        std.debug.print("Duration: {d}ms\n", .{duration_ms});
        std.debug.print("Total Operations: {d}\n", .{total_operations});
        std.debug.print("Total Errors: {d}\n", .{total_errors});
        std.debug.print("Throughput: {d} ops/sec\n", .{throughput});
        std.debug.print("Error Rate: {d:.2}%\n", .{error_rate});
        std.debug.print("Latency - Min: {d}ns, Max: {d}ns, Avg: {d}ns\n", .{ min_latency, max_latency, avg_latency });
        std.debug.print("Latency - Min: {d:.2}μs, Max: {d:.2}μs, Avg: {d:.2}μs\n", .{ @as(f64, @floatFromInt(min_latency)) / 1000.0, @as(f64, @floatFromInt(max_latency)) / 1000.0, @as(f64, @floatFromInt(avg_latency)) / 1000.0 });

        // Log results for monitoring
        logging.infoGlobalWithContext("concurrency_test", "Stress test completed", .{
            .test_name = test_name,
            .duration_ms = duration_ms,
            .total_operations = total_operations,
            .throughput_ops_per_sec = throughput,
            .error_rate_percent = error_rate,
            .avg_latency_ns = avg_latency,
        });

        // Assert basic performance criteria
        try testing.expect(error_rate < 5.0); // Less than 5% error rate
        try testing.expect(throughput > 1000); // At least 1000 ops/sec
        try testing.expect(avg_latency < 100000); // Average latency under 100μs
    }
};

// Test exports
test "High-Frequency Trading Concurrency" {
    try ConcurrencyStressTests.testHighFrequencyTrading();
}

test "Market Maker Workload Concurrency" {
    try ConcurrencyStressTests.testMarketMakerWorkload();
}

test "Memory Pressure Scenario" {
    try ConcurrencyStressTests.testMemoryPressureScenario();
}

test "Mixed Workload Scenario" {
    try ConcurrencyStressTests.testMixedWorkloadScenario();
}
