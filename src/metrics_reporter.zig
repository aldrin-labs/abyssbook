const std = @import("std");

/// Flexible metrics reporting interface supporting multiple output formats
pub const MetricsReporter = struct {
    allocator: std.mem.Allocator,
    
    pub const ReportFormat = enum {
        console,
        json,
        csv,
        prometheus,
    };
    
    pub const MetricEntry = struct {
        operation: []const u8,
        timestamp: i64,
        iterations: usize,
        avg_time_ns: u64,
        latency_p50: u64,
        latency_p95: u64,
        latency_p99: u64,
        latency_p999: u64,
        min_latency: u64,
        max_latency: u64,
        std_deviation: f64,
        throughput: f64,
        metadata: std.StringHashMap([]const u8),
        
        pub fn init(allocator: std.mem.Allocator) MetricEntry {
            return .{
                .operation = "",
                .timestamp = 0,
                .iterations = 0,
                .avg_time_ns = 0,
                .latency_p50 = 0,
                .latency_p95 = 0,
                .latency_p99 = 0,
                .latency_p999 = 0,
                .min_latency = 0,
                .max_latency = 0,
                .std_deviation = 0,
                .throughput = 0,
                .metadata = std.StringHashMap([]const u8).init(allocator),
            };
        }
        
        pub fn deinit(self: *MetricEntry) void {
            self.metadata.deinit();
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) MetricsReporter {
        return .{
            .allocator = allocator,
        };
    }
    
    pub fn report(self: *MetricsReporter, entries: []const MetricEntry, format: ReportFormat, writer: anytype) !void {
        switch (format) {
            .console => try self.reportConsole(entries, writer),
            .json => try self.reportJSON(entries, writer),
            .csv => try self.reportCSV(entries, writer),
            .prometheus => try self.reportPrometheus(entries, writer),
        }
    }
    
    fn reportConsole(self: *MetricsReporter, entries: []const MetricEntry, writer: anytype) !void {
        _ = self;
        
        try writer.print("{s:<25} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n", .{
            "Operation", "Avg (µs)", "P50 (µs)", "P95 (µs)", "P99 (µs)", "Ops/sec", "StdDev (µs)"
        });
        try writer.writeAll("-" ** 105 ++ "\n");
        
        for (entries) |entry| {
            try writer.print("{s:<25} {d:>12.2} {d:>12.2} {d:>12.2} {d:>12.2} {d:>12.0} {d:>12.2}\n", .{
                entry.operation,
                @as(f64, @floatFromInt(entry.avg_time_ns)) / 1000.0,
                @as(f64, @floatFromInt(entry.latency_p50)) / 1000.0,
                @as(f64, @floatFromInt(entry.latency_p95)) / 1000.0,
                @as(f64, @floatFromInt(entry.latency_p99)) / 1000.0,
                entry.throughput,
                entry.std_deviation / 1000.0,
            });
        }
    }
    
    fn reportJSON(self: *MetricsReporter, entries: []const MetricEntry, writer: anytype) !void {
        _ = self;
        
        try writer.writeAll("{\n");
        try writer.print("  \"timestamp\": {d},\n", .{std.time.timestamp()});
        try writer.writeAll("  \"format_version\": \"1.0\",\n");
        try writer.writeAll("  \"metrics\": [\n");
        
        for (entries, 0..) |entry, i| {
            try writer.writeAll("    {\n");
            try writer.print("      \"operation\": \"{s}\",\n", .{entry.operation});
            try writer.print("      \"timestamp\": {d},\n", .{entry.timestamp});
            try writer.print("      \"iterations\": {d},\n", .{entry.iterations});
            try writer.print("      \"avg_time_ns\": {d},\n", .{entry.avg_time_ns});
            try writer.print("      \"latency_p50\": {d},\n", .{entry.latency_p50});
            try writer.print("      \"latency_p95\": {d},\n", .{entry.latency_p95});
            try writer.print("      \"latency_p99\": {d},\n", .{entry.latency_p99});
            try writer.print("      \"latency_p999\": {d},\n", .{entry.latency_p999});
            try writer.print("      \"min_latency\": {d},\n", .{entry.min_latency});
            try writer.print("      \"max_latency\": {d},\n", .{entry.max_latency});
            try writer.print("      \"std_deviation\": {d:.2},\n", .{entry.std_deviation});
            try writer.print("      \"throughput\": {d:.2}\n", .{entry.throughput});
            
            if (i < entries.len - 1) {
                try writer.writeAll("    },\n");
            } else {
                try writer.writeAll("    }\n");
            }
        }
        
        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");
    }
    
    fn reportCSV(self: *MetricsReporter, entries: []const MetricEntry, writer: anytype) !void {
        _ = self;
        
        // CSV header
        try writer.writeAll("operation,timestamp,iterations,avg_time_ns,latency_p50,latency_p95,latency_p99,latency_p999,min_latency,max_latency,std_deviation,throughput\n");
        
        // CSV data
        for (entries) |entry| {
            try writer.print("\"{s}\",{d},{d},{d},{d},{d},{d},{d},{d},{d},{d:.2},{d:.2}\n", .{
                entry.operation,
                entry.timestamp,
                entry.iterations,
                entry.avg_time_ns,
                entry.latency_p50,
                entry.latency_p95,
                entry.latency_p99,
                entry.latency_p999,
                entry.min_latency,
                entry.max_latency,
                entry.std_deviation,
                entry.throughput,
            });
        }
    }
    
    fn reportPrometheus(self: *MetricsReporter, entries: []const MetricEntry, writer: anytype) !void {
        _ = self;
        
        try writer.writeAll("# HELP orderbook_operation_duration_nanoseconds Latency of orderbook operations in nanoseconds\n");
        try writer.writeAll("# TYPE orderbook_operation_duration_nanoseconds histogram\n");
        
        try writer.writeAll("# HELP orderbook_operation_throughput_ops_per_second Throughput of orderbook operations per second\n");
        try writer.writeAll("# TYPE orderbook_operation_throughput_ops_per_second gauge\n");
        
        for (entries) |entry| {
            const timestamp_ms = entry.timestamp * 1000;
            const operation_label = entry.operation;
            
            // Latency histogram buckets
            try writer.print("orderbook_operation_duration_nanoseconds{{operation=\"{s}\",quantile=\"0.50\"}} {d} {d}\n", 
                .{ operation_label, entry.latency_p50, timestamp_ms });
            try writer.print("orderbook_operation_duration_nanoseconds{{operation=\"{s}\",quantile=\"0.95\"}} {d} {d}\n", 
                .{ operation_label, entry.latency_p95, timestamp_ms });
            try writer.print("orderbook_operation_duration_nanoseconds{{operation=\"{s}\",quantile=\"0.99\"}} {d} {d}\n", 
                .{ operation_label, entry.latency_p99, timestamp_ms });
            try writer.print("orderbook_operation_duration_nanoseconds{{operation=\"{s}\",quantile=\"0.999\"}} {d} {d}\n", 
                .{ operation_label, entry.latency_p999, timestamp_ms });
            
            // Throughput gauge
            try writer.print("orderbook_operation_throughput_ops_per_second{{operation=\"{s}\"}} {d:.2} {d}\n", 
                .{ operation_label, entry.throughput, timestamp_ms });
            
            // Additional metrics
            try writer.print("orderbook_operation_iterations_total{{operation=\"{s}\"}} {d} {d}\n", 
                .{ operation_label, entry.iterations, timestamp_ms });
            try writer.print("orderbook_operation_stddev_nanoseconds{{operation=\"{s}\"}} {d:.2} {d}\n", 
                .{ operation_label, entry.std_deviation, timestamp_ms });
        }
    }
    
    /// Export metrics to file in specified format
    pub fn exportToFile(self: *MetricsReporter, entries: []const MetricEntry, format: ReportFormat, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();
        
        var writer = file.writer();
        try self.report(entries, format, &writer);
        
        std.log.info("Metrics exported to {s} in {} format", .{ filename, format });
    }
};

/// Convert BenchmarkResult to MetricEntry for reporting
pub fn benchmarkResultToMetricEntry(allocator: std.mem.Allocator, result: anytype) !MetricsReporter.MetricEntry {
    var entry = MetricsReporter.MetricEntry.init(allocator);
    
    entry.operation = try allocator.dupe(u8, result.operation);
    entry.timestamp = std.time.timestamp();
    entry.iterations = result.iterations;
    entry.avg_time_ns = result.avg_time_ns;
    entry.latency_p50 = result.latency_p50;
    entry.latency_p95 = result.latency_p95;
    entry.latency_p99 = result.latency_p99;
    entry.latency_p999 = if (@hasField(@TypeOf(result), "latency_p999")) result.latency_p999 else 0;
    entry.min_latency = if (@hasField(@TypeOf(result), "min_latency")) result.min_latency else 0;
    entry.max_latency = if (@hasField(@TypeOf(result), "max_latency")) result.max_latency else 0;
    entry.std_deviation = if (@hasField(@TypeOf(result), "std_deviation")) result.std_deviation else 0;
    entry.throughput = result.throughput;
    
    return entry;
}

// Test the metrics reporter
pub fn testMetricsReporter() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var reporter = MetricsReporter.init(allocator);
    
    // Create sample metrics
    var entries = [_]MetricsReporter.MetricEntry{
        .{
            .operation = "Place Orders",
            .timestamp = std.time.timestamp(),
            .iterations = 10000,
            .avg_time_ns = 1500,
            .latency_p50 = 1200,
            .latency_p95 = 2500,
            .latency_p99 = 4000,
            .latency_p999 = 8000,
            .min_latency = 500,
            .max_latency = 15000,
            .std_deviation = 800,
            .throughput = 666666.7,
            .metadata = std.StringHashMap([]const u8).init(allocator),
        },
        .{
            .operation = "Cancel Orders",
            .timestamp = std.time.timestamp(),
            .iterations = 8000,
            .avg_time_ns = 1100,
            .latency_p50 = 900,
            .latency_p95 = 2000,
            .latency_p99 = 3200,
            .latency_p999 = 6000,
            .min_latency = 400,
            .max_latency = 12000,
            .std_deviation = 600,
            .throughput = 909090.9,
            .metadata = std.StringHashMap([]const u8).init(allocator),
        },
    };
    defer for (&entries) |*entry| entry.deinit();
    
    std.debug.print("\n=== Console Format ===\n");
    try reporter.report(&entries, .console, std.debug.print);
    
    std.debug.print("\n=== CSV Format ===\n");
    try reporter.report(&entries, .csv, std.debug.print);
    
    std.debug.print("\n=== JSON Format ===\n");
    try reporter.report(&entries, .json, std.debug.print);
    
    std.debug.print("\n=== Prometheus Format ===\n");
    try reporter.report(&entries, .prometheus, std.debug.print);
    
    // Test file export
    try reporter.exportToFile(&entries, .json, "test_metrics.json");
    try reporter.exportToFile(&entries, .csv, "test_metrics.csv");
}

pub fn main() !void {
    try testMetricsReporter();
}