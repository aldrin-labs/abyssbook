const std = @import("std");
const types = @import("../types.zig");
const order = @import("../order.zig");
const price_level = @import("price_level.zig");
const core = @import("core.zig");

pub fn placeOrder(self: *core.ShardedOrderbook, side: types.OrderSide, price: u64, amount: u64, id: u64) types.OrderError!void {
    const new_order = order.CacheAlignedOrder.init(price, amount, id, side, .Limit, null);
    try placeOrderWithType(self, new_order);
}

pub fn placeOrderWithType(self: *core.ShardedOrderbook, order_data: order.CacheAlignedOrder) !void {
    const shard_index = self.priceToShard(order_data.price);
    const key = types.OrderKey{ .price = order_data.price, .id = order_data.id };

    // Set current order context for matching
    self.current_order = &order_data;
    self.current_order_flags = order_data.flags;
    defer {
        self.current_order = null;
        self.current_order_flags = .{};
    }

    // Handle stop orders
    if (order_data.flags.is_stop) {
        try self.stop_orders[shard_index].put(key, order_data);
        return;
    }

    // For IOC or FOK orders, try to match immediately
    if (order_data.flags.is_ioc or order_data.flags.is_fok) {
        const result = try self.matchOrder(order_data.side, order_data.price, order_data.amount);
        if (result.remaining_amount > 0) {
            // IOC and FOK orders don't place remaining amount
            return;
        }
    }

    // For Post-Only orders, check if would match
    if (order_data.flags.is_post_only) {
        const would_match = if (order_data.side == .Buy)
            if (self.getBestAsk()) |ask| ask <= order_data.price else false
        else if (self.getBestBid()) |bid| bid >= order_data.price else false;

        if (would_match) {
            return;
        }
    }

    // For GTD orders, check if already expired
    if (order_data.flags.is_gtd) {
        const current_time = std.time.timestamp();
        if (order_data.expiry_time.? <= current_time) {
            return;
        }
    }

    // Regular limit order handling
    const levels = if (order_data.side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];

    // For iceberg orders, only show the display amount
    const display_amount = if (order_data.flags.is_iceberg)
        order_data.display_amount orelse order_data.amount
    else
        order_data.amount;

    try price_level.updatePriceLevel(levels, order_data.price, @as(i64, @intCast(display_amount)), 1);
    try self.shards[shard_index].put(key, order_data);

    // Update best bid/ask cache
    if (order_data.side == .Buy) {
        self.best_bid_cache = if (self.best_bid_cache) |current_best|
            @max(current_best, order_data.price)
        else
            order_data.price;
    } else {
        self.best_ask_cache = if (self.best_ask_cache) |current_best|
            @min(current_best, order_data.price)
        else
            order_data.price;
    }

    // Check if this order triggers any stop orders
    try self.checkStopOrders(order_data.price);
}

pub fn cancelOrder(self: *core.ShardedOrderbook, id: u64) types.OrderError!void {
    // Search all shards for the order
    for (0..self.shard_count) |i| {
        var it = self.shards[i].iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.*.id == id) {
                const order_data = entry.value_ptr.*;
                const levels = if (order_data.side == .Buy) &self.bid_levels[i] else &self.ask_levels[i];

                // Update price level
                try price_level.updatePriceLevel(levels, order_data.price, -@as(i64, @intCast(order_data.amount)), -1);

                // Remove order
                _ = self.shards[i].swapRemove(entry.key_ptr.*);

                // Update best bid/ask cache
                if (order_data.side == .Buy) {
                    self.best_bid_cache = null;
                } else {
                    self.best_ask_cache = null;
                }

                return;
            }
        }

        // Also check stop orders
        var stop_it = self.stop_orders[i].iterator();
        while (stop_it.next()) |entry| {
            if (entry.value_ptr.*.id == id) {
                _ = self.stop_orders[i].orderedRemove(entry.key_ptr.*);
                return;
            }
        }
    }
    return types.OrderError.OrderNotFound;
}

pub fn checkStopOrders(self: *core.ShardedOrderbook, price: u64) types.OrderError!void {
    // Check all shards for stop orders that should be triggered
    for (0..self.shard_count) |i| {
        var it = self.stop_orders[i].iterator();
        var index: usize = 0;
        while (it.next()) |entry| : (index += 1) {
            const stop_order = entry.value_ptr.*;

            const should_trigger = if (stop_order.side == .Buy)
                price >= stop_order.stop_price.?
            else
                price <= stop_order.stop_price.?;

            if (should_trigger) {
                // Remove from stop orders
                _ = self.stop_orders[i].orderedRemove(entry.key_ptr.*);

                // Place as regular order
                self.placeOrder(stop_order.side, stop_order.price, stop_order.amount, stop_order.id) catch |err| {
                    // If placing fails, put the order back in stop orders
                    self.stop_orders[i].put(entry.key_ptr.*, stop_order) catch {
                        // If we can't put it back, we're in a bad state
                        return types.OrderError.OutOfMemory;
                    };
                    return err;
                };
            }
        }
    }
}
