const std = @import("std");
const orderbook = @import("orderbook.zig");

/// Performance regression test that validates against historical baselines
pub const RegressionTester = struct {
    allocator: std.mem.Allocator,
    baseline_file: []const u8,
    tolerance_pct: f64,
    
    pub const RegressionResult = struct {
        operation: []const u8,
        baseline_latency_p99: u64,
        current_latency_p99: u64,
        baseline_throughput: f64,
        current_throughput: f64,
        latency_regression_pct: f64,
        throughput_regression_pct: f64,
        passed: bool,
    };
    
    pub fn init(allocator: std.mem.Allocator, baseline_file: []const u8, tolerance_pct: f64) RegressionTester {
        return .{
            .allocator = allocator,
            .baseline_file = baseline_file,
            .tolerance_pct = tolerance_pct,
        };
    }
    
    pub fn runRegressionTest(self: *RegressionTester) ![]RegressionResult {
        // Load baseline results
        const baseline = try self.loadBaseline();
        defer self.allocator.free(baseline);
        
        // Run current benchmarks (simplified version)
        const current = try self.runCurrentBenchmarks();
        defer self.allocator.free(current);
        
        // Compare results
        var results = std.ArrayList(RegressionResult).init(self.allocator);
        
        for (baseline) |base| {
            for (current) |curr| {
                if (std.mem.eql(u8, base.operation, curr.operation)) {
                    const latency_regression = if (base.latency_p99 > 0)
                        (@as(f64, @floatFromInt(curr.latency_p99)) - @as(f64, @floatFromInt(base.latency_p99))) / @as(f64, @floatFromInt(base.latency_p99)) * 100.0
                    else
                        0.0;
                    
                    const throughput_regression = if (base.throughput > 0)
                        (curr.throughput - base.throughput) / base.throughput * 100.0
                    else
                        0.0;
                    
                    const passed = latency_regression <= self.tolerance_pct and throughput_regression >= -self.tolerance_pct;
                    
                    try results.append(RegressionResult{
                        .operation = try self.allocator.dupe(u8, base.operation),
                        .baseline_latency_p99 = base.latency_p99,
                        .current_latency_p99 = curr.latency_p99,
                        .baseline_throughput = base.throughput,
                        .current_throughput = curr.throughput,
                        .latency_regression_pct = latency_regression,
                        .throughput_regression_pct = throughput_regression,
                        .passed = passed,
                    });
                    break;
                }
            }
        }
        
        return results.toOwnedSlice();
    }
    
    const BaselineResult = struct {
        operation: []const u8,
        latency_p99: u64,
        throughput: f64,
    };
    
    fn loadBaseline(self: *RegressionTester) ![]BaselineResult {
        // For now, return hardcoded baseline values
        // In a real implementation, this would load from JSON file
        const baseline_data = [_]BaselineResult{
            .{ .operation = "Place Orders", .latency_p99 = 5000, .throughput = 200000 },
            .{ .operation = "Cancel Orders", .latency_p99 = 4000, .throughput = 250000 },
            .{ .operation = "Market Orders", .latency_p99 = 10000, .throughput = 100000 },
            .{ .operation = "Burst Orders", .latency_p99 = 3000, .throughput = 500000 },
        };
        
        var results = std.ArrayList(BaselineResult).init(self.allocator);
        for (baseline_data) |item| {
            try results.append(.{
                .operation = try self.allocator.dupe(u8, item.operation),
                .latency_p99 = item.latency_p99,
                .throughput = item.throughput,
            });
        }
        
        return results.toOwnedSlice();
    }
    
    fn runCurrentBenchmarks(self: *RegressionTester) ![]BaselineResult {
        // Run a simplified benchmark suite
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();
        
        var book = try orderbook.ShardedOrderbook.init(allocator, 8);
        defer book.deinit();
        
        var results = std.ArrayList(BaselineResult).init(self.allocator);
        
        // Simple place order benchmark
        const place_result = try self.benchmarkPlaceOrders(&book);
        try results.append(.{
            .operation = try self.allocator.dupe(u8, "Place Orders"),
            .latency_p99 = place_result.latency_p99,
            .throughput = place_result.throughput,
        });
        
        // Add more benchmarks as needed...
        
        return results.toOwnedSlice();
    }
    
    const SimpleBenchResult = struct {
        latency_p99: u64,
        throughput: f64,
    };
    
    fn benchmarkPlaceOrders(self: *RegressionTester, book: *orderbook.ShardedOrderbook) !SimpleBenchResult {
        _ = self;
        const iterations = 10000;
        var latencies = std.ArrayList(u64).init(self.allocator);
        defer latencies.deinit();
        
        var timer = try std.time.Timer.start();
        const start_time = timer.read();
        
        var prng = std.rand.DefaultPrng.init(42);
        const rng = prng.random();
        
        for (0..iterations) |i| {
            timer.reset();
            const price = rng.uintAtMost(u64, 1000) + 1;
            const amount = rng.uintAtMost(u64, 100) + 1;
            book.placeOrder(.Buy, price, amount, i + 1) catch continue;
            
            const latency = timer.read();
            try latencies.append(latency);
        }
        
        const total_time = timer.read() - start_time;
        const throughput = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        std.sort.heap(u64, latencies.items, {}, std.sort.asc(u64));
        const latency_p99 = latencies.items[latencies.items.len * 99 / 100];
        
        return SimpleBenchResult{
            .latency_p99 = latency_p99,
            .throughput = throughput,
        };
    }
    
    pub fn printResults(results: []const RegressionResult) void {
        std.debug.print("\n" ++ "=".** 80 ++ "\n");
        std.debug.print("PERFORMANCE REGRESSION TEST RESULTS\n");
        std.debug.print("=".** 80 ++ "\n");
        
        var passed_count: usize = 0;
        var failed_count: usize = 0;
        
        for (results) |result| {
            if (result.passed) {
                passed_count += 1;
            } else {
                failed_count += 1;
            }
            
            const status = if (result.passed) "PASS" else "FAIL";
            std.debug.print("\n{s}: {s}\n", .{ result.operation, status });
            std.debug.print("  Latency P99:\n");
            std.debug.print("    Baseline: {d:.2} µs\n", .{@as(f64, @floatFromInt(result.baseline_latency_p99)) / 1000.0});
            std.debug.print("    Current:  {d:.2} µs\n", .{@as(f64, @floatFromInt(result.current_latency_p99)) / 1000.0});
            std.debug.print("    Change:   {d:+.1}%\n", .{result.latency_regression_pct});
            
            std.debug.print("  Throughput:\n");
            std.debug.print("    Baseline: {d:.0} ops/sec\n", .{result.baseline_throughput});
            std.debug.print("    Current:  {d:.0} ops/sec\n", .{result.current_throughput});
            std.debug.print("    Change:   {d:+.1}%\n", .{result.throughput_regression_pct});
        }
        
        std.debug.print("\n" ++ "-".** 80 ++ "\n");
        std.debug.print("Summary: {d} passed, {d} failed\n", .{ passed_count, failed_count });
        
        if (failed_count == 0) {
            std.debug.print("✅ All performance regression tests PASSED\n");
        } else {
            std.debug.print("❌ Performance regression detected!\n");
        }
        std.debug.print("=".** 80 ++ "\n");
    }
};

// CI-friendly test that exits with appropriate codes
pub fn runCIRegressionTest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var tester = RegressionTester.init(allocator, "baseline.json", 10.0); // 10% tolerance
    const results = try tester.runRegressionTest();
    defer {
        for (results) |result| {
            allocator.free(result.operation);
        }
        allocator.free(results);
    }
    
    RegressionTester.printResults(results);
    
    // Check if any tests failed
    for (results) |result| {
        if (!result.passed) {
            std.process.exit(1); // Exit with error code for CI
        }
    }
    
    std.process.exit(0); // Success
}

pub fn main() !void {
    try runCIRegressionTest();
}