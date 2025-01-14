const std = @import("std");

pub const SIMDMetrics = struct {
    vector_operations: usize = 0,
    scalar_operations: usize = 0,
    cache_misses: usize = 0,
    start_time: i128 = 0,
    end_time: i128 = 0,

    pub fn startTimer(self: *SIMDMetrics) void {
        self.start_time = std.time.nanoTimestamp();
    }

    pub fn stopTimer(self: *SIMDMetrics) void {
        self.end_time = std.time.nanoTimestamp();
    }

    pub fn getElapsedNanos(self: *const SIMDMetrics) i128 {
        return self.end_time - self.start_time;
    }

    pub fn getVectorUtilization(self: *const SIMDMetrics) f64 {
        const total_ops = @as(f64, @floatFromInt(self.vector_operations + self.scalar_operations));
        if (total_ops == 0) return 0;
        return @as(f64, @floatFromInt(self.vector_operations)) / total_ops;
    }
};

pub const SortMetrics = struct {
    comparisons: usize = 0,
    swaps: usize = 0,
    start_time: i128 = 0,
    end_time: i128 = 0,

    pub fn startTimer(self: *SortMetrics) void {
        self.start_time = std.time.nanoTimestamp();
    }

    pub fn stopTimer(self: *SortMetrics) void {
        self.end_time = std.time.nanoTimestamp();
    }

    pub fn getElapsedNanos(self: *const SortMetrics) i128 {
        return self.end_time - self.start_time;
    }
};

pub const BatchMetrics = struct {
    total_batches: usize = 0,
    full_batches: usize = 0,
    partial_batches: usize = 0,
    total_orders: usize = 0,
    start_time: i128 = 0,
    end_time: i128 = 0,

    pub fn startTimer(self: *BatchMetrics) void {
        self.start_time = std.time.nanoTimestamp();
    }

    pub fn stopTimer(self: *BatchMetrics) void {
        self.end_time = std.time.nanoTimestamp();
    }

    pub fn getElapsedNanos(self: *const BatchMetrics) i128 {
        return self.end_time - self.start_time;
    }

    pub fn getBatchEfficiency(self: *const BatchMetrics) f64 {
        if (self.total_batches == 0) return 0;
        return @as(f64, @floatFromInt(self.full_batches)) / @as(f64, @floatFromInt(self.total_batches));
    }
};

const MetricSample = struct {
    metric_type: []const u8,
    value: f64,
    timestamp: i128,
};

pub const PerformanceMonitor = struct {
    allocator: std.mem.Allocator,
    simd_metrics: SIMDMetrics = .{},
    sort_metrics: SortMetrics = .{},
    batch_metrics: BatchMetrics = .{},
    samples: std.ArrayList(MetricSample),

    pub fn init(allocator: std.mem.Allocator) PerformanceMonitor {
        return .{
            .allocator = allocator,
            .samples = std.ArrayList(MetricSample).init(allocator),
        };
    }

    pub fn deinit(self: *PerformanceMonitor) void {
        self.samples.deinit();
    }

    pub fn recordMetric(self: *PerformanceMonitor, metric_type: []const u8, value: f64) !void {
        try self.samples.append(.{
            .metric_type = metric_type,
            .value = value,
            .timestamp = std.time.nanoTimestamp(),
        });
    }

    pub fn generateReport(self: *const PerformanceMonitor, writer: anytype) !void {
        try writer.print(
            \\Performance Report:
            \\SIMD Operations:
            \\  Vector Operations: {d}
            \\  Scalar Operations: {d}
            \\  Cache Misses: {d}
            \\  Vector Utilization: {d:.2}%
            \\
            \\Batch Processing:
            \\  Total Batches: {d}
            \\  Full Batches: {d}
            \\  Partial Batches: {d}
            \\  Batch Efficiency: {d:.2}%
            \\
            \\Sort Performance:
            \\  Comparisons: {d}
            \\  Swaps: {d}
            \\  Sort Time: {d}ns
            \\
        , .{
            self.simd_metrics.vector_operations,
            self.simd_metrics.scalar_operations,
            self.simd_metrics.cache_misses,
            self.simd_metrics.getVectorUtilization() * 100,
            self.batch_metrics.total_batches,
            self.batch_metrics.full_batches,
            self.batch_metrics.partial_batches,
            self.batch_metrics.getBatchEfficiency() * 100,
            self.sort_metrics.comparisons,
            self.sort_metrics.swaps,
            self.sort_metrics.getElapsedNanos(),
        });
    }
};
