const std = @import("std");
const perf = @import("perf_monitor.zig");

// SVG generation constants
const SVG_WIDTH = 800;
const SVG_HEIGHT = 400;
const MARGIN = 50;
const PLOT_WIDTH = SVG_WIDTH - 2 * MARGIN;
const PLOT_HEIGHT = SVG_HEIGHT - 2 * MARGIN;
const ANIMATION_DURATION = 500; // Animation duration in milliseconds

// Animation configuration
const AnimationConfig = struct {
    duration_ms: u32 = ANIMATION_DURATION,
    delay_ms: u32 = 0,
    easing: []const u8 = "cubic-bezier(0.4, 0, 0.2, 1)",
};

pub const ChartType = enum {
    TimeSeries,
    BarChart,
    PieChart,
    Heatmap,
};

pub const ChartOptions = struct {
    title: []const u8,
    x_label: []const u8,
    y_label: []const u8,
    chart_type: ChartType,
    color_scheme: []const []const u8,
    animation: ?AnimationConfig = null,
};

const DataPoint = struct {
    x: f64,
    y: f64,
    label: ?[]const u8 = null,
};

pub const ChartData = struct {
    points: []const DataPoint,
    min_x: f64,
    max_x: f64,
    min_y: f64,
    max_y: f64,

    pub fn init(allocator: std.mem.Allocator, data: []const struct { x: f64, y: f64, label: ?[]const u8 }) !ChartData {
        var points = try allocator.alloc(DataPoint, data.len);
        var min_x = std.math.inf(f64);
        var max_x = -std.math.inf(f64);
        var min_y = std.math.inf(f64);
        var max_y = -std.math.inf(f64);

        for (data, 0..) |point, i| {
            points[i] = .{
                .x = point.x,
                .y = point.y,
                .label = point.label,
            };
            min_x = @min(min_x, point.x);
            max_x = @max(max_x, point.x);
            min_y = @min(min_y, point.y);
            max_y = @max(max_y, point.y);
        }

        return .{
            .points = points,
            .min_x = min_x,
            .max_x = max_x,
            .min_y = min_y,
            .max_y = max_y,
        };
    }

    pub fn deinit(self: *ChartData, allocator: std.mem.Allocator) void {
        allocator.free(self.points);
    }
};

fn mapToPixel(value: f64, min: f64, max: f64, pixel_min: f64, pixel_max: f64) f64 {
    const range = max - min;
    const pixel_range = pixel_max - pixel_min;
    return pixel_min + (value - min) * pixel_range / range;
}

fn writeAnimatedStyles(writer: anytype) !void {
    try writer.writeAll(
        \\<style>
        \\.title { 
        \\    font: bold 16px sans-serif;
        \\    opacity: 0;
        \\    animation: fadeIn 0.5s ease-out 0.1s forwards;
        \\}
        \\.axis-label { 
        \\    font: 12px sans-serif;
        \\    opacity: 0;
        \\    animation: fadeIn 0.5s ease-out 0.3s forwards;
        \\}
        \\.axis {
        \\    stroke-dasharray: 1000;
        \\    stroke-dashoffset: 1000;
        \\    animation: drawLine 1s ease-out 0.5s forwards;
        \\}
        \\.grid-line {
        \\    stroke: #e0e0e0;
        \\    stroke-width: 1;
        \\    stroke-dasharray: 5;
        \\    opacity: 0;
        \\    animation: fadeIn 0.3s ease-out forwards;
        \\}
        \\.data-point {
        \\    fill: #4CAF50;
        \\    opacity: 0;
        \\    animation: fadeIn 0.5s ease-out forwards;
        \\}
        \\.data-point:hover {
        \\    fill: #2E7D32;
        \\    r: 6;
        \\    transition: all 0.3s;
        \\}
        \\.tooltip {
        \\    opacity: 0;
        \\    pointer-events: none;
        \\    background: rgba(0, 0, 0, 0.8);
        \\    color: white;
        \\    padding: 8px;
        \\    border-radius: 4px;
        \\    font-size: 12px;
        \\    transition: opacity 0.3s;
        \\}
        \\.data-point:hover + .tooltip {
        \\    opacity: 1;
        \\}
        \\.line {
        \\    stroke: #2196F3;
        \\    stroke-width: 2;
        \\    fill: none;
        \\    stroke-dasharray: 1000;
        \\    stroke-dashoffset: 1000;
        \\    animation: drawLine 2s ease-out 1s forwards;
        \\}
        \\.bar {
        \\    fill: #2196F3;
        \\    transform-origin: bottom;
        \\    animation: growBar 0.8s ease-out forwards;
        \\}
        \\.bar:hover {
        \\    fill: #1976D2;
        \\    transition: fill 0.3s;
        \\}
        \\.value-label {
        \\    opacity: 0;
        \\    animation: fadeIn 0.5s ease-out forwards;
        \\    pointer-events: none;
        \\}
        \\@keyframes fadeIn {
        \\    from { opacity: 0; transform: scale(0.9); }
        \\    to { opacity: 1; transform: scale(1); }
        \\}
        \\@keyframes drawLine {
        \\    to { stroke-dashoffset: 0; }
        \\}
        \\@keyframes growBar {
        \\    from { transform: scaleY(0); }
        \\    to { transform: scaleY(1); }
        \\}
        \\@keyframes slideIn {
        \\    from { transform: translateY(20px); opacity: 0; }
        \\    to { transform: translateY(0); opacity: 1; }
        \\}
        \\</style>
    );
}

fn writeAnimationScript(writer: anytype) !void {
    try writer.writeAll(
        \\<script type="text/javascript">
        \\<![CDATA[
        \\function animateValue(element, start, end, duration) {
        \\    let startTimestamp = null;
        \\    const step = (timestamp) => {
        \\        if (!startTimestamp) startTimestamp = timestamp;
        \\        const progress = Math.min((timestamp - startTimestamp) / duration, 1);
        \\        const current = Math.floor(progress * (end - start) + start);
        \\        element.textContent = current.toLocaleString();
        \\        if (progress < 1) {
        \\            window.requestAnimationFrame(step);
        \\        }
        \\    };
        \\    window.requestAnimationFrame(step);
        \\}
        \\]]>
        \\</script>
    );
}

pub fn generateTimeSeries(writer: anytype, data: ChartData, options: ChartOptions) !void {
    try writer.print(
        \\<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        \\<svg width="{d}" height="{d}" xmlns="http://www.w3.org/2000/svg">
    , .{ SVG_WIDTH, SVG_HEIGHT });

    try writeAnimatedStyles(writer);
    try writeAnimationScript(writer);

    // Draw background grid
    const grid_steps = 10;
    const x_step = PLOT_WIDTH / @as(f64, @floatFromInt(grid_steps));
    const y_step = PLOT_HEIGHT / @as(f64, @floatFromInt(grid_steps));

    // Draw vertical grid lines
    for (0..grid_steps + 1) |i| {
        const x = MARGIN + i * x_step;
        const delay = 400 + i * 50;
        try writer.print(
            \\<line x1="{d}" y1="{d}" x2="{d}" y2="{d}" class="grid-line" style="animation-delay: {d}ms"/>
        , .{ x, MARGIN, x, SVG_HEIGHT - MARGIN, delay });
    }

    // Draw horizontal grid lines
    for (0..grid_steps + 1) |i| {
        const y = MARGIN + i * y_step;
        const delay = 400 + (grid_steps + i) * 50;
        try writer.print(
            \\<line x1="{d}" y1="{d}" x2="{d}" y2="{d}" class="grid-line" style="animation-delay: {d}ms"/>
        , .{ MARGIN, y, SVG_WIDTH - MARGIN, y, delay });
    }

    // Draw title with slide-in animation
    try writer.print(
        \\<text x="{d}" y="25" text-anchor="middle" class="title" style="animation: slideIn 0.5s ease-out 0.1s forwards">{s}</text>
    , .{ SVG_WIDTH / 2, options.title });

    // Draw axes with progressive animation
    try writer.print(
        \\<line x1="{d}" y1="{d}" x2="{d}" y2="{d}" class="axis"/>
        \\<line x1="{d}" y1="{d}" x2="{d}" y2="{d}" class="axis"/>
    , .{
        MARGIN,             SVG_HEIGHT - MARGIN,
        SVG_WIDTH - MARGIN, SVG_HEIGHT - MARGIN,
        MARGIN,             MARGIN,
        MARGIN,             SVG_HEIGHT - MARGIN,
    });

    // Draw axis labels with slide-in animation
    try writer.print(
        \\<text x="{d}" y="{d}" text-anchor="middle" class="axis-label" style="animation: slideIn 0.5s ease-out 0.6s forwards">{s}</text>
        \\<text x="{d}" y="{d}" text-anchor="middle" transform="rotate(-90,{d},{d})" class="axis-label" style="animation: slideIn 0.5s ease-out 0.7s forwards">{s}</text>
    , .{
        SVG_WIDTH / 2,   SVG_HEIGHT - 5,
        options.x_label, 25,
        SVG_HEIGHT / 2,  25,
        SVG_HEIGHT / 2,  options.y_label,
    });

    // Generate path data for line with progressive animation
    try writer.writeAll("<path class=\"line\" d=\"M");
    for (data.points, 0..) |point, i| {
        const x = mapToPixel(point.x, data.min_x, data.max_x, MARGIN, SVG_WIDTH - MARGIN);
        const y = mapToPixel(point.y, data.min_y, data.max_y, SVG_HEIGHT - MARGIN, MARGIN);
        if (i == 0) {
            try writer.print("{d},{d}", .{ x, y });
        } else {
            try writer.print(" L{d},{d}", .{ x, y });
        }
    }
    try writer.writeAll("\"/>\n");

    // Draw data points with progressive reveal
    for (data.points, 0..) |point, i| {
        const x = mapToPixel(point.x, data.min_x, data.max_x, MARGIN, SVG_WIDTH - MARGIN);
        const y = mapToPixel(point.y, data.min_y, data.max_y, SVG_HEIGHT - MARGIN, MARGIN);
        const base_delay = if (options.animation) |anim| anim.delay_ms else 0;
        const point_delay = base_delay + 1200 + i * 100;

        // Data point with tooltip
        try writer.print(
            \\<g>
            \\  <circle cx="{d}" cy="{d}" r="4" class="data-point" style="animation-delay: {d}ms">
            \\    <title>{d:.2}</title>
            \\  </circle>
            \\  <foreignObject x="{d}" y="{d}" width="120" height="40" class="tooltip" style="animation-delay: {d}ms">
            \\    <div xmlns="http://www.w3.org/1999/xhtml" style="background: rgba(0,0,0,0.8); color: white; padding: 4px; border-radius: 4px;">
            \\      <div>Value: {d:.2}</div>
            \\      {s}
            \\    </div>
            \\  </foreignObject>
            \\</g>
        , .{
            x,                                      y,      point_delay,       point.y,
            x - 60,                                 y - 45, point_delay + 100, point.y,
            if (point.label) |label| label else "",
        });

        if (point.label) |label| {
            try writer.print(
                \\<text x="{d}" y="{d}" dx="8" dy="-8" class="axis-label" style="animation: slideIn 0.5s ease-out {d}ms forwards">{s}</text>
            , .{ x, y, point_delay + 200, label });
        }
    }

    try writer.writeAll("</svg>");
}

pub fn generateBarChart(writer: anytype, data: ChartData, options: ChartOptions) !void {
    const bar_width = (PLOT_WIDTH - data.points.len * 10) / @as(f64, @floatFromInt(data.points.len));

    try writer.print(
        \\<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        \\<svg width="{d}" height="{d}" xmlns="http://www.w3.org/2000/svg">
    , .{ SVG_WIDTH, SVG_HEIGHT });

    try writeAnimatedStyles(writer);
    try writeAnimationScript(writer);

    // Draw title and axes
    try writer.print(
        \\<text x="{d}" y="25" text-anchor="middle" class="title">{s}</text>
    , .{ SVG_WIDTH / 2, options.title });

    // Draw animated bars
    for (data.points, 0..) |point, i| {
        const x = MARGIN + i * (bar_width + 10);
        const height = mapToPixel(point.y, 0, data.max_y, 0, PLOT_HEIGHT);
        const y = SVG_HEIGHT - MARGIN - height;
        const delay = if (options.animation) |anim|
            anim.delay_ms + @divTrunc(anim.duration_ms * @as(u32, @intCast(i)), @as(u32, @intCast(data.points.len)))
        else
            0;

        try writer.print(
            \\<g style="animation-delay: {d}ms">
            \\<rect x="{d}" y="{d}" width="{d}" height="{d}" class="bar">
            \\<title>{d:.2}</title>
            \\</rect>
        , .{ delay, x, y, bar_width, height, point.y });

        // Animated value display
        try writer.print(
            \\<text x="{d}" y="{d}" text-anchor="middle" class="value-label" style="opacity: 0; animation: fadeIn 0.5s ease-out {d}ms forwards">{d}</text>
        , .{ x + bar_width / 2, y - 5, delay + 100, @round(point.y) });

        if (point.label) |label| {
            try writer.print(
                \\<text x="{d}" y="{d}" text-anchor="middle" transform="rotate(-45,{d},{d})" class="axis-label" style="opacity: 0; animation: fadeIn 0.5s ease-out {d}ms forwards">{s}</text>
            , .{
                x + bar_width / 2,
                SVG_HEIGHT - MARGIN + 20,
                x + bar_width / 2,
                SVG_HEIGHT - MARGIN + 20,
                delay + 200,
                label,
            });
        }

        try writer.writeAll("</g>\n");
    }

    try writer.writeAll("</svg>");
}

pub fn generatePerformanceReport(monitor: *const perf.PerformanceMonitor, writer: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(monitor.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Generate animated time series for SIMD metrics
    var simd_data = try allocator.alloc(struct { x: f64, y: f64, label: ?[]const u8 }, monitor.samples.items.len);
    for (monitor.samples.items, 0..) |sample, i| {
        simd_data[i] = .{
            .x = @floatFromInt(i),
            .y = sample.value,
            .label = sample.metric_type,
        };
    }

    const simd_chart_data = try ChartData.init(allocator, simd_data);
    defer simd_chart_data.deinit(allocator);

    try generateTimeSeries(writer, simd_chart_data, .{
        .title = "SIMD Performance Over Time",
        .x_label = "Sample",
        .y_label = "Value",
        .chart_type = .TimeSeries,
        .color_scheme = &.{ "#2196F3", "#4CAF50" },
        .animation = .{
            .duration_ms = 1000,
            .delay_ms = 200,
            .easing = "cubic-bezier(0.4, 0, 0.2, 1)",
        },
    });

    // Generate animated bar chart for batch metrics
    var batch_data = [_]struct { x: f64, y: f64, label: ?[]const u8 }{
        .{ .x = 0, .y = @floatFromInt(monitor.batch_metrics.full_batches), .label = "Full" },
        .{ .x = 1, .y = @floatFromInt(monitor.batch_metrics.partial_batches), .label = "Partial" },
    };

    const batch_chart_data = try ChartData.init(allocator, &batch_data);
    defer batch_chart_data.deinit(allocator);

    try writer.writeAll("\n\n");
    try generateBarChart(writer, batch_chart_data, .{
        .title = "Batch Distribution",
        .x_label = "Batch Type",
        .y_label = "Count",
        .chart_type = .BarChart,
        .color_scheme = &.{"#2196F3"},
        .animation = .{
            .duration_ms = 800,
            .delay_ms = 300,
            .easing = "cubic-bezier(0.4, 0, 0.2, 1)",
        },
    });
}

pub fn visualizeMetrics(monitor: *const perf.PerformanceMonitor, output_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    var buffered_writer = std.io.bufferedWriter(file.writer());
    try generatePerformanceReport(monitor, buffered_writer.writer());
    try buffered_writer.flush();
}
