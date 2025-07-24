const std = @import("std");
const BlockchainClient = @import("../blockchain/client.zig").BlockchainClient;
const TUIService = @import("../services/tui.zig").TUIService;

/// Main TUI application
pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize the TUI service with API credentials
    // In a production environment, these would be loaded from a secure configuration
    const api_key = "YOUR_API_KEY";
    const base_url = "https://ny.solana.dex.blxrbdn.com";

    var tui_service = try TUIService.init(allocator, api_key, base_url);
    defer tui_service.deinit();

    std.debug.print("Starting Abyssbook TUI...\n", .{});

    // Clear screen
    std.debug.print("\x1B[2J\x1B[H", .{});

    // Display header
    std.debug.print("\x1B[1;36m===== ABYSSBOOK ORDERBOOK MONITOR =====\x1B[0m\n\n", .{});

    // Get real orderbook data from blockchain
    var orderbook = try tui_service.getOrderbook();
    defer orderbook.deinit(allocator);

    // Display orderbook data
    displayOrderbook(orderbook);

    // Calculate and display spread
    const spread = try tui_service.calculateSpread(orderbook);
    std.debug.print("\n\x1B[1;33mSPREAD: {d:.2}\x1B[0m\n\n", .{spread});

    // Display controls
    std.debug.print("\n\x1B[1;33mControls:\x1B[0m\n", .{});
    std.debug.print("  q - Quit\n", .{});
    std.debug.print("  r - Refresh data\n", .{});
    std.debug.print("  h - Toggle help\n\n", .{});

    // Get current time for uptime calculation
    const current_time = std.time.timestamp();
    const start_time = current_time - 60 * 60; // Simulate 1 hour uptime
    const uptime_seconds = current_time - start_time;
    const hours = @divFloor(uptime_seconds, 3600);
    const minutes = @divFloor(@rem(uptime_seconds, 3600), 60);
    const seconds = @rem(uptime_seconds, 60);

    // Display status bar with real data
    std.debug.print("\x1B[1;44m STATUS: Running | Orders: {d} | Market: {s} | Uptime: {:0>2}:{:0>2}:{:0>2} \x1B[0m\n", .{
        orderbook.bids.len + orderbook.asks.len,
        orderbook.market,
        hours,
        minutes,
        seconds,
    });

    // In a real implementation, we would handle keyboard input and update the display
    // For now, we'll just wait for a keypress to exit
    std.debug.print("\nPress any key to exit...\n", .{});

    // Wait for input (simplified for this example)
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readByte();

    std.debug.print("Exiting TUI...\n", .{});
}

/// Display orderbook data
fn displayOrderbook(orderbook: anytype) void {
    // Display buy orders (green)
    std.debug.print("\x1B[1;32mBUY ORDERS\x1B[0m\n", .{});
    std.debug.print("+-----------+------------+------------+\n", .{});
    std.debug.print("| Price     | Size       | Total      |\n", .{});
    std.debug.print("+-----------+------------+------------+\n", .{});

    for (orderbook.bids) |bid| {
        const total = bid.price * bid.size;
        std.debug.print("| {d:9.2} | {d:10.2} | {d:10.2} |\n", .{ bid.price, bid.size, total });
    }

    std.debug.print("+-----------+------------+------------+\n", .{});

    // Display sell orders (red)
    std.debug.print("\x1B[1;31mSELL ORDERS\x1B[0m\n", .{});
    std.debug.print("+-----------+------------+------------+\n", .{});
    std.debug.print("| Price     | Size       | Total      |\n", .{});
    std.debug.print("+-----------+------------+------------+\n", .{});

    for (orderbook.asks) |ask| {
        const total = ask.price * ask.size;
        std.debug.print("| {d:9.2} | {d:10.2} | {d:10.2} |\n", .{ ask.price, ask.size, total });
    }

    std.debug.print("+-----------+------------+------------+\n", .{});
}
