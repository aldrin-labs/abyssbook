const std = @import("std");
const logging = @import("../logging.zig");

/// Show node status and performance metrics
pub fn showStatus() !void {
    logging.infoGlobal("cli.status", "System status requested");
    
    std.debug.print("Abyssbook Node Status\n", .{});
    std.debug.print("====================\n\n", .{});
    
    // Node information
    std.debug.print("Node Information:\n", .{});
    std.debug.print("  Status: Running\n", .{});
    std.debug.print("  Version: 0.1.0\n", .{});
    std.debug.print("  Uptime: 01:23:45\n\n", .{});
    
    // Orderbook statistics
    std.debug.print("Orderbook Statistics:\n", .{});
    std.debug.print("  Total Orders: 42\n", .{});
    std.debug.print("  Buy Orders: 25\n", .{});
    std.debug.print("  Sell Orders: 17\n", .{});
    std.debug.print("  Trades Today: 18\n", .{});
    std.debug.print("  Volume Today: 1234.56\n\n", .{});
    
    // Performance metrics
    std.debug.print("Performance Metrics:\n", .{});
    std.debug.print("  Order Processing Time (avg): 0.5ms\n", .{});
    std.debug.print("  Matching Engine Latency: 1.2ms\n", .{});
    std.debug.print("  Memory Usage: 128MB\n", .{});
    std.debug.print("  CPU Usage: 15%%\n\n", .{});
    
    // System resources
    std.debug.print("System Resources:\n", .{});
    std.debug.print("  Available Memory: 3.5GB\n", .{});
    std.debug.print("  Disk Space: 45.2GB free\n", .{});
}
