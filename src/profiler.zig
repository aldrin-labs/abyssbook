const std = @import("std");
const orderbook = @import("orderbook.zig");

pub const ProfilerResult = struct {
    function_name: []const u8,
    total_time_ns: u64,
    call_count: usize,
    avg_time_ns: u64,
    percentage: f64,
};

pub const Profiler = struct {
    allocator: std.mem.Allocator,
    profiles: std.StringHashMap(ProfileData),
    start_time: i128,
    total_duration: i128,
    
    const ProfileData = struct {
        total_time: u64,
        call_count: usize,
        start_time: i128,
    };
    
    pub fn init(allocator: std.mem.Allocator) Profiler {
        return .{
            .allocator = allocator,
            .profiles = std.StringHashMap(ProfileData).init(allocator),
            .start_time = std.time.nanoTimestamp(),
            .total_duration = 0,
        };
    }
    
    pub fn deinit(self: *Profiler) void {
        self.profiles.deinit();
    }
    
    pub fn startFunction(self: *Profiler, function_name: []const u8) !void {
        const current_time = std.time.nanoTimestamp();
        
        if (self.profiles.getPtr(function_name)) |data| {
            data.start_time = current_time;
        } else {
            try self.profiles.put(function_name, ProfileData{
                .total_time = 0,
                .call_count = 0,
                .start_time = current_time,
            });
        }
    }
    
    pub fn endFunction(self: *Profiler, function_name: []const u8) !void {
        const current_time = std.time.nanoTimestamp();
        
        if (self.profiles.getPtr(function_name)) |data| {
            const elapsed = @as(u64, @intCast(current_time - data.start_time));
            data.total_time += elapsed;
            data.call_count += 1;
        } else {
            std.log.warn("endFunction called for unknown function: {s}", .{function_name});
        }
    }
    
    pub fn generateReport(self: *Profiler) ![]ProfilerResult {
        self.total_duration = std.time.nanoTimestamp() - self.start_time;
        
        var results = std.ArrayList(ProfilerResult).init(self.allocator);
        var it = self.profiles.iterator();
        
        while (it.next()) |entry| {
            const data = entry.value_ptr.*;
            const avg_time = if (data.call_count > 0) data.total_time / data.call_count else 0;
            const percentage = @as(f64, @floatFromInt(data.total_time)) / @as(f64, @floatFromInt(@as(u64, @intCast(self.total_duration)))) * 100.0;
            
            try results.append(ProfilerResult{
                .function_name = entry.key_ptr.*,
                .total_time_ns = data.total_time,
                .call_count = data.call_count,
                .avg_time_ns = avg_time,
                .percentage = percentage,
            });
        }
        
        // Sort by total time descending
        std.sort.heap(ProfilerResult, results.items, {}, struct {
            fn lessThan(_: void, a: ProfilerResult, b: ProfilerResult) bool {
                return a.total_time_ns > b.total_time_ns;
            }
        }.lessThan);
        
        return results.toOwnedSlice();
    }
    
    pub fn printReport(self: *Profiler) !void {
        const results = try self.generateReport();
        defer self.allocator.free(results);
        
        std.debug.print("\n=== Performance Profile Report ===\n");
        std.debug.print("Total Duration: {d:.2} ms\n", .{@as(f64, @floatFromInt(@as(u64, @intCast(self.total_duration)))) / 1_000_000.0});
        std.debug.print("\n{s:<30} {s:>12} {s:>12} {s:>12} {s:>8}\n", .{
            "Function", "Total (ms)", "Calls", "Avg (µs)", "% Time"
        });
        std.debug.print("-" ** 76 ++ "\n");
        
        for (results) |result| {
            std.debug.print("{s:<30} {d:>12.2} {d:>12} {d:>12.2} {d:>7.1}%\n", .{
                result.function_name,
                @as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000.0,
                result.call_count,
                @as(f64, @floatFromInt(result.avg_time_ns)) / 1000.0,
                result.percentage,
            });
        }
        std.debug.print("\n");
    }
};

// Macro for easy profiling with proper error handling
pub fn ProfiledCall(profiler: *Profiler, comptime function_name: []const u8, function: anytype, args: anytype) !@TypeOf(@call(.auto, function, args)) {
    try profiler.startFunction(function_name);
    defer profiler.endFunction(function_name) catch |err| {
        std.log.warn("Failed to end profiling for {s}: {}", .{function_name, err});
    };
    return try @call(.auto, function, args);
}

// Comprehensive profiling benchmark
pub fn runProfilingBenchmark() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();
    
    // Initialize orderbook
    var book = try orderbook.ShardedOrderbook.init(allocator, 8);
    defer book.deinit();
    
    std.debug.print("Running comprehensive profiling benchmark...\n");
    
    // Test various operations with profiling
    const iterations = 10_000;
    var prng = std.rand.DefaultPrng.init(42);
    const rng = prng.random();
    
    // Profile order placement
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const price = rng.uintAtMost(u64, 1000) + 1;
        const amount = rng.uintAtMost(u64, 100) + 1;
        const id = i + 1;
        
        _ = try ProfiledCall(&profiler, "placeOrder", orderbook.ShardedOrderbook.placeOrder, .{ &book, .Buy, price, amount, id });
    }
    
    // Profile order cancellation
    i = 1;
    while (i <= iterations / 2) : (i += 1) {
        _ = try ProfiledCall(&profiler, "cancelOrder", orderbook.ShardedOrderbook.cancelOrder, .{ &book, i });
    }
    
    // Profile market orders
    i = 0;
    while (i < 100) : (i += 1) {
        const amount = rng.uintAtMost(u64, 50) + 1;
        _ = try ProfiledCall(&profiler, "executeMarketOrder", orderbook.ShardedOrderbook.executeMarketOrder, .{ &book, .Sell, amount });
    }
    
    // Profile best bid/ask queries
    i = 0;
    while (i < 1000) : (i += 1) {
        _ = ProfiledCall(&profiler, "getBestBid", orderbook.ShardedOrderbook.getBestBid, .{&book}) catch null;
        _ = ProfiledCall(&profiler, "getBestAsk", orderbook.ShardedOrderbook.getBestAsk, .{&book}) catch null;
    }
    
    try profiler.printReport();
}

// Memory profiling utilities
pub const MemoryProfiler = struct {
    allocator: std.mem.Allocator,
    initial_memory: usize,
    peak_memory: usize,
    current_memory: usize,
    allocations: usize,
    
    pub fn init(allocator: std.mem.Allocator) MemoryProfiler {
        return .{
            .allocator = allocator,
            .initial_memory = 0,
            .peak_memory = 0,
            .current_memory = 0,
            .allocations = 0,
        };
    }
    
    pub fn startProfiling(self: *MemoryProfiler) void {
        // This would ideally hook into the allocator to track memory usage
        // For now, we'll use a simple estimation
        self.initial_memory = 0;
        self.current_memory = 0;
        self.peak_memory = 0;
        self.allocations = 0;
    }
    
    pub fn recordAllocation(self: *MemoryProfiler, size: usize) void {
        self.current_memory += size;
        self.peak_memory = @max(self.peak_memory, self.current_memory);
        self.allocations += 1;
    }
    
    pub fn recordDeallocation(self: *MemoryProfiler, size: usize) void {
        self.current_memory = if (size > self.current_memory) 0 else self.current_memory - size;
    }
    
    pub fn printReport(self: *const MemoryProfiler) void {
        std.debug.print("\n=== Memory Profile Report ===\n");
        std.debug.print("Initial Memory: {d} bytes\n", .{self.initial_memory});
        std.debug.print("Peak Memory: {d} bytes ({d:.2} MB)\n", .{ self.peak_memory, @as(f64, @floatFromInt(self.peak_memory)) / 1_048_576.0 });
        std.debug.print("Current Memory: {d} bytes\n", .{self.current_memory});
        std.debug.print("Total Allocations: {d}\n", .{self.allocations});
        std.debug.print("Memory Efficiency: {d:.1}%\n", .{@as(f64, @floatFromInt(self.current_memory)) / @as(f64, @floatFromInt(self.peak_memory)) * 100.0});
        std.debug.print("\n");
    }
};

// Cache analysis utilities
pub const CacheProfiler = struct {
    l1_hits: usize = 0,
    l1_misses: usize = 0,
    l2_hits: usize = 0,
    l2_misses: usize = 0,
    l3_hits: usize = 0,
    l3_misses: usize = 0,
    
    pub fn getL1HitRatio(self: *const CacheProfiler) f64 {
        const total = self.l1_hits + self.l1_misses;
        return if (total > 0) @as(f64, @floatFromInt(self.l1_hits)) / @as(f64, @floatFromInt(total)) * 100.0 else 0.0;
    }
    
    pub fn getL2HitRatio(self: *const CacheProfiler) f64 {
        const total = self.l2_hits + self.l2_misses;
        return if (total > 0) @as(f64, @floatFromInt(self.l2_hits)) / @as(f64, @floatFromInt(total)) * 100.0 else 0.0;
    }
    
    pub fn getL3HitRatio(self: *const CacheProfiler) f64 {
        const total = self.l3_hits + self.l3_misses;
        return if (total > 0) @as(f64, @floatFromInt(self.l3_hits)) / @as(f64, @floatFromInt(total)) * 100.0 else 0.0;
    }
    
    pub fn printReport(self: *const CacheProfiler) void {
        std.debug.print("\n=== Cache Profile Report ===\n");
        std.debug.print("L1 Cache: {d} hits, {d} misses ({d:.1}% hit ratio)\n", .{ self.l1_hits, self.l1_misses, self.getL1HitRatio() });
        std.debug.print("L2 Cache: {d} hits, {d} misses ({d:.1}% hit ratio)\n", .{ self.l2_hits, self.l2_misses, self.getL2HitRatio() });
        std.debug.print("L3 Cache: {d} hits, {d} misses ({d:.1}% hit ratio)\n", .{ self.l3_hits, self.l3_misses, self.getL3HitRatio() });
        std.debug.print("\n");
    }
};

pub fn main() !void {
    try runProfilingBenchmark();
}
