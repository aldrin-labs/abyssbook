const std = @import("std");
const orderbook = @import("orderbook.zig");

pub const LoadTestConfig = struct {
    duration_seconds: u64 = 60,
    target_ops_per_second: usize = 100_000,
    burst_intensity: f64 = 2.0, // Multiplier for burst periods
    burst_duration_ms: u64 = 1000,
    burst_interval_ms: u64 = 10000,
    
    // Order mix percentages (must sum to 100)
    place_order_pct: u8 = 40,
    cancel_order_pct: u8 = 30,
    market_order_pct: u8 = 20,
    query_pct: u8 = 10,
    
    // Price and amount ranges
    price_min: u64 = 1000,
    price_max: u64 = 2000,
    amount_min: u64 = 1,
    amount_max: u64 = 1000,
    
    // Threading
    worker_threads: usize = 4,
    
    pub fn validate(self: *const LoadTestConfig) bool {
        return (self.place_order_pct + self.cancel_order_pct + self.market_order_pct + self.query_pct) == 100;
    }
};

pub const LoadTestResult = struct {
    total_operations: usize,
    successful_operations: usize,
    failed_operations: usize,
    
    total_duration_ns: u64,
    avg_latency_ns: u64,
    min_latency_ns: u64,
    max_latency_ns: u64,
    
    latency_p50: u64,
    latency_p95: u64,
    latency_p99: u64,
    latency_p999: u64,
    
    actual_ops_per_second: f64,
    target_ops_per_second: f64,
    
    // Operation-specific results
    place_order_results: OperationStats,
    cancel_order_results: OperationStats,
    market_order_results: OperationStats,
    query_results: OperationStats,
    
    // Resource utilization
    peak_memory_mb: f64,
    avg_cpu_percent: f64,
    
    pub fn printSummary(self: *const LoadTestResult) void {
        std.debug.print("\n" ++ "=" ** 80 ++ "\n");
        std.debug.print("LOAD TEST RESULTS\n");
        std.debug.print("=" ** 80 ++ "\n");
        
        std.debug.print("Overall Performance:\n");
        std.debug.print("  Total Operations: {d}\n", .{self.total_operations});
        std.debug.print("  Successful: {d} ({d:.1}%)\n", .{ 
            self.successful_operations, 
            @as(f64, @floatFromInt(self.successful_operations)) / @as(f64, @floatFromInt(self.total_operations)) * 100.0 
        });
        std.debug.print("  Failed: {d} ({d:.1}%)\n", .{ 
            self.failed_operations, 
            @as(f64, @floatFromInt(self.failed_operations)) / @as(f64, @floatFromInt(self.total_operations)) * 100.0 
        });
        std.debug.print("  Target Ops/sec: {d:.0}\n", .{self.target_ops_per_second});
        std.debug.print("  Actual Ops/sec: {d:.0}\n", .{self.actual_ops_per_second});
        std.debug.print("  Achievement: {d:.1}%\n", .{self.actual_ops_per_second / self.target_ops_per_second * 100.0});
        
        std.debug.print("\nLatency Distribution:\n");
        std.debug.print("  Avg: {d:.2} µs\n", .{@as(f64, @floatFromInt(self.avg_latency_ns)) / 1000.0});
        std.debug.print("  Min: {d:.2} µs\n", .{@as(f64, @floatFromInt(self.min_latency_ns)) / 1000.0});
        std.debug.print("  P50: {d:.2} µs\n", .{@as(f64, @floatFromInt(self.latency_p50)) / 1000.0});
        std.debug.print("  P95: {d:.2} µs\n", .{@as(f64, @floatFromInt(self.latency_p95)) / 1000.0});
        std.debug.print("  P99: {d:.2} µs\n", .{@as(f64, @floatFromInt(self.latency_p99)) / 1000.0});
        std.debug.print("  P99.9: {d:.2} µs\n", .{@as(f64, @floatFromInt(self.latency_p999)) / 1000.0});
        std.debug.print("  Max: {d:.2} µs\n", .{@as(f64, @floatFromInt(self.max_latency_ns)) / 1000.0});
        
        std.debug.print("\nOperation Breakdown:\n");
        std.debug.print("  Place Orders: {d} ops, {d:.2} µs avg\n", .{
            self.place_order_results.count,
            @as(f64, @floatFromInt(self.place_order_results.avg_latency_ns)) / 1000.0,
        });
        std.debug.print("  Cancel Orders: {d} ops, {d:.2} µs avg\n", .{
            self.cancel_order_results.count,
            @as(f64, @floatFromInt(self.cancel_order_results.avg_latency_ns)) / 1000.0,
        });
        std.debug.print("  Market Orders: {d} ops, {d:.2} µs avg\n", .{
            self.market_order_results.count,
            @as(f64, @floatFromInt(self.market_order_results.avg_latency_ns)) / 1000.0,
        });
        std.debug.print("  Queries: {d} ops, {d:.2} µs avg\n", .{
            self.query_results.count,
            @as(f64, @floatFromInt(self.query_results.avg_latency_ns)) / 1000.0,
        });
        
        std.debug.print("\nResource Utilization:\n");
        std.debug.print("  Peak Memory: {d:.2} MB\n", .{self.peak_memory_mb});
        std.debug.print("  Avg CPU: {d:.1}%\n", .{self.avg_cpu_percent});
        
        std.debug.print("\n" ++ "=" ** 80 ++ "\n");
    }
};

pub const OperationStats = struct {
    count: usize = 0,
    total_latency_ns: u64 = 0,
    avg_latency_ns: u64 = 0,
    min_latency_ns: u64 = std.math.maxInt(u64),
    max_latency_ns: u64 = 0,
    errors: usize = 0,
    
    pub fn recordLatency(self: *OperationStats, latency_ns: u64) void {
        self.count += 1;
        self.total_latency_ns += latency_ns;
        self.min_latency_ns = @min(self.min_latency_ns, latency_ns);
        self.max_latency_ns = @max(self.max_latency_ns, latency_ns);
        self.avg_latency_ns = self.total_latency_ns / self.count;
    }
    
    pub fn recordError(self: *OperationStats) void {
        self.errors += 1;
    }
};

pub const LoadTester = struct {
    allocator: std.mem.Allocator,
    config: LoadTestConfig,
    orderbook: *orderbook.ShardedOrderbook,
    
    // Statistics
    total_operations: std.atomic.Value(usize),
    successful_operations: std.atomic.Value(usize),
    failed_operations: std.atomic.Value(usize),
    
    // Latency tracking
    latencies: std.ArrayList(u64),
    latencies_mutex: std.Thread.Mutex,
    
    // Operation-specific stats  
    place_order_stats: OperationStats,
    cancel_order_stats: OperationStats,
    market_order_stats: OperationStats,
    query_stats: OperationStats,
    stats_mutex: std.Thread.Mutex,
    
    // Test control
    start_time: i128,
    should_stop: std.atomic.Value(bool),
    
    // Order tracking for cancellations
    active_orders: std.ArrayList(u64),
    active_orders_mutex: std.Thread.Mutex,
    next_order_id: std.atomic.Value(u64),
    
    pub fn init(allocator: std.mem.Allocator, config: LoadTestConfig, book: *orderbook.ShardedOrderbook) !LoadTester {
        if (!config.validate()) {
            return error.InvalidConfig;
        }
        
        return LoadTester{
            .allocator = allocator,
            .config = config,
            .orderbook = book,
            .total_operations = std.atomic.Value(usize).init(0),
            .successful_operations = std.atomic.Value(usize).init(0),
            .failed_operations = std.atomic.Value(usize).init(0),
            .latencies = std.ArrayList(u64).init(allocator),
            .latencies_mutex = std.Thread.Mutex{},
            .place_order_stats = OperationStats{},
            .cancel_order_stats = OperationStats{},
            .market_order_stats = OperationStats{},
            .query_stats = OperationStats{},
            .stats_mutex = std.Thread.Mutex{},
            .start_time = 0,
            .should_stop = std.atomic.Value(bool).init(false),
            .active_orders = std.ArrayList(u64).init(allocator),
            .active_orders_mutex = std.Thread.Mutex{},
            .next_order_id = std.atomic.Value(u64).init(1),
        };
    }
    
    pub fn deinit(self: *LoadTester) void {
        self.latencies.deinit();
        self.active_orders.deinit();
    }
    
    pub fn run(self: *LoadTester) !LoadTestResult {
        std.debug.print("Starting load test...\n");
        std.debug.print("Duration: {d}s\n", .{self.config.duration_seconds});
        std.debug.print("Target: {d} ops/sec\n", .{self.config.target_ops_per_second});
        std.debug.print("Workers: {d} threads\n", .{self.config.worker_threads});
        std.debug.print("Operation mix: {}% place, {}% cancel, {}% market, {}% query\n", .{
            self.config.place_order_pct,
            self.config.cancel_order_pct,
            self.config.market_order_pct,
            self.config.query_pct,
        });
        
        self.start_time = std.time.nanoTimestamp();
        
        // Start worker threads
        var threads = try self.allocator.alloc(std.Thread, self.config.worker_threads);
        defer self.allocator.free(threads);
        
        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerThread, .{ self, i });
        }
        
        // Start monitoring thread
        const monitor_thread = try std.Thread.spawn(.{}, monitoringThread, .{self});
        
        // Wait for test duration
        std.time.sleep(self.config.duration_seconds * std.time.ns_per_s);
        
        // Signal stop
        self.should_stop.store(true, .seq_cst);
        
        // Wait for threads to finish
        for (threads) |thread| {
            thread.join();
        }
        monitor_thread.join();
        
        return self.generateResults();
    }
    
    fn workerThread(self: *LoadTester, worker_id: usize) void {
        var prng = std.rand.DefaultPrng.init(@as(u64, @intCast(worker_id)) + @as(u64, @intCast(std.time.timestamp())));
        const rng = prng.random();
        
        const ops_per_worker = self.config.target_ops_per_second / self.config.worker_threads;
        const ns_per_op = std.time.ns_per_s / ops_per_worker;
        
        var last_op_time = std.time.nanoTimestamp();
        
        while (!self.should_stop.load(.seq_cst)) {
            const current_time = std.time.nanoTimestamp();
            const elapsed_since_start = current_time - self.start_time;
            
            // Check if we're in a burst period
            const burst_cycle_ns = (self.config.burst_interval_ms + self.config.burst_duration_ms) * std.time.ns_per_ms;
            const cycle_position = @mod(@as(u64, @intCast(elapsed_since_start)), burst_cycle_ns);
            const is_burst = cycle_position < self.config.burst_duration_ms * std.time.ns_per_ms;
            
            const target_ns_per_op = if (is_burst)
                @as(u64, @intFromFloat(@as(f64, @floatFromInt(ns_per_op)) / self.config.burst_intensity))
            else
                ns_per_op;
            
            // Rate limiting
            const time_since_last_op = current_time - last_op_time;
            if (time_since_last_op < target_ns_per_op) {
                const sleep_time = target_ns_per_op - time_since_last_op;
                std.time.sleep(sleep_time);
            }
            
            // Execute operation
            self.executeRandomOperation(rng);
            last_op_time = std.time.nanoTimestamp();
        }
    }
    
    fn executeRandomOperation(self: *LoadTester, rng: std.rand.Random) void {
        const op_choice = rng.uintAtMost(u8, 99);
        var timer = std.time.Timer.start() catch return;
        
        const result = if (op_choice < self.config.place_order_pct) blk: {
            const success = self.executePlaceOrder(rng);
            const latency = timer.read();
            
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();
            
            if (success) {
                self.place_order_stats.recordLatency(latency);
            } else {
                self.place_order_stats.recordError();
            }
            
            break :blk success;
        } else if (op_choice < self.config.place_order_pct + self.config.cancel_order_pct) blk: {
            const success = self.executeCancelOrder(rng);
            const latency = timer.read();
            
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();
            
            if (success) {
                self.cancel_order_stats.recordLatency(latency);
            } else {
                self.cancel_order_stats.recordError();
            }
            
            break :blk success;
        } else if (op_choice < self.config.place_order_pct + self.config.cancel_order_pct + self.config.market_order_pct) blk: {
            const success = self.executeMarketOrder(rng);
            const latency = timer.read();
            
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();
            
            if (success) {
                self.market_order_stats.recordLatency(latency);
            } else {
                self.market_order_stats.recordError();
            }
            
            break :blk success;
        } else blk: {
            const success = self.executeQuery(rng);
            const latency = timer.read();
            
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();
            
            if (success) {
                self.query_stats.recordLatency(latency);
            } else {
                self.query_stats.recordError();
            }
            
            break :blk success;
        };
        
        const latency = timer.read();
        
        // Record overall statistics
        _ = self.total_operations.fetchAdd(1, .seq_cst);
        if (result) {
            _ = self.successful_operations.fetchAdd(1, .seq_cst);
        } else {
            _ = self.failed_operations.fetchAdd(1, .seq_cst);
        }
        
        // Sample latency (to avoid memory growth)
        if (self.total_operations.load(.seq_cst) % 100 == 0) {
            self.latencies_mutex.lock();
            defer self.latencies_mutex.unlock();
            
            if (self.latencies.items.len < 100_000) {
                self.latencies.append(latency) catch {};
            }
        }
    }
    
    fn executePlaceOrder(self: *LoadTester, rng: std.rand.Random) bool {
        const price = rng.intRangeAtMost(u64, self.config.price_min, self.config.price_max);
        const amount = rng.intRangeAtMost(u64, self.config.amount_min, self.config.amount_max);
        const side: orderbook.OrderSide = if (rng.boolean()) .Buy else .Sell;
        const id = self.next_order_id.fetchAdd(1, .seq_cst);
        
        self.orderbook.placeOrder(side, price, amount, id) catch return false;
        
        // Track order for potential cancellation
        self.active_orders_mutex.lock();
        defer self.active_orders_mutex.unlock();
        self.active_orders.append(id) catch {};
        
        return true;
    }
    
    fn executeCancelOrder(self: *LoadTester, rng: std.rand.Random) bool {
        self.active_orders_mutex.lock();
        defer self.active_orders_mutex.unlock();
        
        if (self.active_orders.items.len == 0) return false;
        
        const index = rng.uintAtMost(usize, self.active_orders.items.len - 1);
        const id = self.active_orders.swapRemove(index);
        
        self.orderbook.cancelOrder(id) catch return false;
        return true;
    }
    
    fn executeMarketOrder(self: *LoadTester, rng: std.rand.Random) bool {
        const amount = rng.intRangeAtMost(u64, self.config.amount_min, self.config.amount_max / 10);
        const side: orderbook.OrderSide = if (rng.boolean()) .Buy else .Sell;
        
        _ = self.orderbook.executeMarketOrder(side, amount) catch return false;
        return true;
    }
    
    fn executeQuery(self: *LoadTester, rng: std.rand.Random) bool {
        _ = rng;
        // Execute different types of queries
        _ = self.orderbook.getBestBid();
        _ = self.orderbook.getBestAsk();
        return true;
    }
    
    fn monitoringThread(self: *LoadTester) void {
        const print_interval = 5 * std.time.ns_per_s; // Print stats every 5 seconds
        var last_print = self.start_time;
        var last_ops = self.total_operations.load(.seq_cst);
        
        while (!self.should_stop.load(.seq_cst)) {
            std.time.sleep(std.time.ns_per_s); // Check every second
            
            const current_time = std.time.nanoTimestamp();
            if (current_time - last_print >= print_interval) {
                const current_ops = self.total_operations.load(.seq_cst);
                const ops_in_period = current_ops - last_ops;
                const time_period_s = @as(f64, @floatFromInt(current_time - last_print)) / std.time.ns_per_s;
                const current_rate = @as(f64, @floatFromInt(ops_in_period)) / time_period_s;
                
                const elapsed_s = @as(f64, @floatFromInt(current_time - self.start_time)) / std.time.ns_per_s;
                
                std.debug.print("[{d:.0}s] Ops: {d}, Rate: {d:.0}/s, Target: {d}/s\n", .{
                    elapsed_s,
                    current_ops,
                    current_rate,
                    self.config.target_ops_per_second,
                });
                
                last_print = current_time;
                last_ops = current_ops;
            }
        }
    }
    
    fn generateResults(self: *LoadTester) LoadTestResult {
        const end_time = std.time.nanoTimestamp();
        const total_duration_ns = @as(u64, @intCast(end_time - self.start_time));
        
        const total_ops = self.total_operations.load(.seq_cst);
        const successful_ops = self.successful_operations.load(.seq_cst);
        const failed_ops = self.failed_operations.load(.seq_cst);
        
        const actual_ops_per_second = @as(f64, @floatFromInt(total_ops)) / (@as(f64, @floatFromInt(total_duration_ns)) / std.time.ns_per_s);
        
        // Calculate latency percentiles
        self.latencies_mutex.lock();
        defer self.latencies_mutex.unlock();
        
        std.sort.heap(u64, self.latencies.items, {}, std.sort.asc(u64));
        
        const len = self.latencies.items.len;
        const latency_p50 = if (len > 0) self.latencies.items[len * 50 / 100] else 0;
        const latency_p95 = if (len > 0) self.latencies.items[len * 95 / 100] else 0;
        const latency_p99 = if (len > 0) self.latencies.items[len * 99 / 100] else 0;
        const latency_p999 = if (len > 0) self.latencies.items[@min(len * 999 / 1000, len - 1)] else 0;
        
        var total_latency: u64 = 0;
        var min_latency: u64 = std.math.maxInt(u64);
        var max_latency: u64 = 0;
        
        for (self.latencies.items) |latency| {
            total_latency += latency;
            min_latency = @min(min_latency, latency);
            max_latency = @max(max_latency, latency);
        }
        
        const avg_latency = if (len > 0) total_latency / len else 0;
        
        return LoadTestResult{
            .total_operations = total_ops,
            .successful_operations = successful_ops,
            .failed_operations = failed_ops,
            .total_duration_ns = total_duration_ns,
            .avg_latency_ns = avg_latency,
            .min_latency_ns = if (min_latency == std.math.maxInt(u64)) 0 else min_latency,
            .max_latency_ns = max_latency,
            .latency_p50 = latency_p50,
            .latency_p95 = latency_p95,
            .latency_p99 = latency_p99,
            .latency_p999 = latency_p999,
            .actual_ops_per_second = actual_ops_per_second,
            .target_ops_per_second = @as(f64, @floatFromInt(self.config.target_ops_per_second)),
            .place_order_results = self.place_order_stats,
            .cancel_order_results = self.cancel_order_stats,
            .market_order_results = self.market_order_stats,
            .query_results = self.query_stats,
            .peak_memory_mb = 0.0, // TODO: Implement memory monitoring
            .avg_cpu_percent = 0.0, // TODO: Implement CPU monitoring
        };
    }
};

// Run comprehensive load test
pub fn runLoadTest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize orderbook
    var book = try orderbook.ShardedOrderbook.init(allocator, 16);
    defer book.deinit();
    
    // Configure load test
    const config = LoadTestConfig{
        .duration_seconds = 30,
        .target_ops_per_second = 50_000,
        .worker_threads = 4,
        .burst_intensity = 3.0,
        .burst_duration_ms = 2000,
        .burst_interval_ms = 10000,
    };
    
    var load_tester = try LoadTester.init(allocator, config, &book);
    defer load_tester.deinit();
    
    const result = try load_tester.run();
    result.printSummary();
    
    // Validate performance targets
    const success_rate = @as(f64, @floatFromInt(result.successful_operations)) / @as(f64, @floatFromInt(result.total_operations)) * 100.0;
    const throughput_achievement = result.actual_ops_per_second / result.target_ops_per_second * 100.0;
    
    std.debug.print("\nPerformance Assessment:\n");
    std.debug.print("  Success Rate: {d:.1}% (Target: >99%)\n", .{success_rate});
    std.debug.print("  Throughput Achievement: {d:.1}% (Target: >90%)\n", .{throughput_achievement});
    std.debug.print("  P99 Latency: {d:.2} µs (Target: <10µs)\n", .{@as(f64, @floatFromInt(result.latency_p99)) / 1000.0});
    
    const overall_pass = success_rate > 99.0 and throughput_achievement > 90.0 and result.latency_p99 < 10_000;
    std.debug.print("  Overall Result: {s}\n", .{if (overall_pass) "PASS" else "FAIL"});
}

pub fn main() !void {
    try runLoadTest();
}
