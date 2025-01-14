const std = @import("std");
const types = @import("../types.zig");
const order = @import("../order.zig");
const params = @import("../order_params.zig");
const core = @import("core.zig");
const basic_orders = @import("basic_orders.zig");

pub fn placeTWAPOrder(self: *core.ShardedOrderbook, side: types.OrderSide, price: u64, total_amount: u64, id: u64, num_intervals: u64, interval_seconds: u64) !void {
    const twap_params = try self.allocator.create(params.TWAPParams);
    errdefer self.allocator.destroy(twap_params);

    twap_params.* = .{
        .start_time = std.time.timestamp(),
        .interval_seconds = interval_seconds,
        .num_intervals = num_intervals,
        .intervals_executed = 0,
    };

    var new_order = order.CacheAlignedOrder.init(price, total_amount, id, side, .TWAP, null);
    new_order.twap_params = twap_params;
    new_order.flags.is_twap = true;

    try basic_orders.placeOrderWithType(self, new_order);
}

pub fn placeTrailingStopOrder(self: *core.ShardedOrderbook, side: types.OrderSide, price: u64, amount: u64, id: u64, distance: u64) !void {
    const trailing_params = try self.allocator.create(params.TrailingStopParams);
    errdefer self.allocator.destroy(trailing_params);

    const current_price = if (side == .Buy) self.getBestAsk() orelse price else self.getBestBid() orelse price;
    trailing_params.* = .{
        .distance = distance,
        .last_trigger_price = current_price,
        .current_stop_price = if (side == .Buy) current_price + distance else current_price - distance,
    };

    var new_order = order.CacheAlignedOrder.init(price, amount, id, side, .TrailingStop, null);
    new_order.trailing_params = trailing_params;
    new_order.flags.is_trailing_stop = true;

    try basic_orders.placeOrderWithType(self, new_order);
}

pub fn placeOSOOrder(self: *core.ShardedOrderbook, primary_order: order.CacheAlignedOrder, child_order: order.CacheAlignedOrder) !void {
    const oso_params = try self.allocator.create(params.OSOParams);
    errdefer self.allocator.destroy(oso_params);

    oso_params.* = .{
        .child_order = child_order,
        .is_child_placed = false,
    };

    var new_primary = primary_order;
    new_primary.oso_params = oso_params;
    new_primary.flags.is_oso = true;

    try basic_orders.placeOrderWithType(self, new_primary);
}

pub fn placeOCOOrder(self: *core.ShardedOrderbook, order1: order.CacheAlignedOrder, order2: order.CacheAlignedOrder) !void {
    const oco_params1 = try self.allocator.create(params.OCOParams);
    errdefer self.allocator.destroy(oco_params1);
    const oco_params2 = try self.allocator.create(params.OCOParams);
    errdefer self.allocator.destroy(oco_params2);

    oco_params1.* = .{
        .linked_order = order2,
        .is_cancelled = false,
    };
    oco_params2.* = .{
        .linked_order = order1,
        .is_cancelled = false,
    };

    var new_order1 = order1;
    var new_order2 = order2;
    new_order1.oco_params = oco_params1;
    new_order2.oco_params = oco_params2;
    new_order1.flags.is_oco = true;
    new_order2.flags.is_oco = true;

    try basic_orders.placeOrderWithType(self, new_order1);
    try basic_orders.placeOrderWithType(self, new_order2);
}

pub fn placePegOrder(self: *core.ShardedOrderbook, side: types.OrderSide, amount: u64, peg_type: params.PegType, offset: i64, limit_price: ?u64, id: u64) !void {
    const peg_params = try self.allocator.create(params.PegParams);
    errdefer self.allocator.destroy(peg_params);

    peg_params.* = .{
        .peg_type = peg_type,
        .offset = offset,
        .limit_price = limit_price,
    };

    const initial_price = switch (peg_type) {
        .BestBid => self.getBestBid() orelse return error.NoBestBid,
        .BestAsk => self.getBestAsk() orelse return error.NoBestAsk,
        .Midpoint => blk: {
            const bid = self.getBestBid() orelse return error.NoBestBid;
            const ask = self.getBestAsk() orelse return error.NoBestAsk;
            break :blk (bid + ask) / 2;
        },
        .LastTrade => return error.LastTradeNotImplemented,
    };

    const adjusted_price = if (offset >= 0)
        initial_price + @as(u64, @intCast(offset))
    else if (@as(u64, @intCast(-offset)) > initial_price)
        0
    else
        initial_price - @as(u64, @intCast(-offset));

    const final_price = if (limit_price) |limit|
        if (side == .Buy)
            @min(adjusted_price, limit)
        else
            @max(adjusted_price, limit)
    else
        adjusted_price;

    var new_order = order.CacheAlignedOrder.init(final_price, amount, id, side, .Peg, null);
    new_order.peg_params = peg_params;
    new_order.flags.is_peg = true;

    try basic_orders.placeOrderWithType(self, new_order);
}

pub fn placeDiscretionaryOrder(self: *core.ShardedOrderbook, side: types.OrderSide, base_price: u64, amount: u64, id: u64, discretionary_price: u64) !void {
    const disc_params = try self.allocator.create(params.DiscretionaryParams);
    errdefer self.allocator.destroy(disc_params);

    disc_params.* = .{
        .base_price = base_price,
        .discretionary_price = discretionary_price,
        .last_executed_price = null,
    };

    var new_order = order.CacheAlignedOrder.init(base_price, amount, id, side, .Discretionary, null);
    new_order.discretionary_params = disc_params;
    new_order.flags.is_discretionary = true;

    try basic_orders.placeOrderWithType(self, new_order);
}

pub fn placeConditionalOrder(self: *core.ShardedOrderbook, side: types.OrderSide, price: u64, amount: u64, id: u64, condition_type: params.ConditionalType, target_value: u64) !void {
    const cond_params = try self.allocator.create(params.ConditionalParams);
    errdefer self.allocator.destroy(cond_params);

    cond_params.* = .{
        .condition_type = condition_type,
        .target_value = target_value,
        .reference_symbol = null,
        .is_condition_met = false,
    };

    var new_order = order.CacheAlignedOrder.init(price, amount, id, side, .Conditional, null);
    new_order.conditional_params = cond_params;
    new_order.flags.is_conditional = true;

    try basic_orders.placeOrderWithType(self, new_order);
}

pub fn updateTrailingStops(self: *core.ShardedOrderbook) !void {
    for (0..self.shard_count) |i| {
        var it = self.shards[i].iterator();
        while (it.next()) |entry| {
            const order_data = entry.value_ptr;
            if (!order_data.flags.is_trailing_stop) continue;

            const trailing_params = order_data.trailing_params.?;
            const current_price = if (order_data.side == .Buy)
                self.getBestAsk() orelse continue
            else
                self.getBestBid() orelse continue;

            const should_update = if (order_data.side == .Buy)
                current_price < trailing_params.last_trigger_price
            else
                current_price > trailing_params.last_trigger_price;

            if (should_update) {
                const new_stop_price = if (order_data.side == .Buy)
                    current_price + trailing_params.distance
                else if (trailing_params.distance > current_price)
                    0
                else
                    current_price - trailing_params.distance;

                try basic_orders.cancelOrder(self, order_data.id);
                var new_order = order_data.*;
                new_order.price = new_stop_price;
                try basic_orders.placeOrderWithType(self, new_order);
            }
        }
    }
}

pub fn updatePegOrders(self: *core.ShardedOrderbook) !void {
    for (0..self.shard_count) |i| {
        var it = self.shards[i].iterator();
        while (it.next()) |entry| {
            const order_data = entry.value_ptr;
            if (!order_data.flags.is_peg) continue;

            const peg_params = order_data.peg_params.?;
            const new_price = switch (peg_params.peg_type) {
                .BestBid => self.getBestBid() orelse continue,
                .BestAsk => self.getBestAsk() orelse continue,
                .Midpoint => blk: {
                    const bid = self.getBestBid() orelse continue;
                    const ask = self.getBestAsk() orelse continue;
                    break :blk (bid + ask) / 2;
                },
                .LastTrade => continue, // Not implemented
            };

            const adjusted_price = if (peg_params.offset >= 0)
                new_price + @as(u64, @intCast(peg_params.offset))
            else if (@as(u64, @intCast(-peg_params.offset)) > new_price)
                0
            else
                new_price - @as(u64, @intCast(-peg_params.offset));

            if (adjusted_price != order_data.price) {
                try basic_orders.cancelOrder(self, order_data.id);
                var new_order = order_data.*;
                new_order.price = adjusted_price;
                try basic_orders.placeOrderWithType(self, new_order);
            }
        }
    }
}

pub fn checkConditionalOrders(self: *core.ShardedOrderbook) !void {
    for (0..self.shard_count) |i| {
        var it = self.shards[i].iterator();
        while (it.next()) |entry| {
            const order_data = entry.value_ptr;
            if (!order_data.flags.is_conditional) continue;

            const conditional_params = order_data.conditional_params.?;
            if (conditional_params.is_condition_met) continue;

            const is_met = switch (conditional_params.condition_type) {
                .PriceAbove => if (self.getBestBid()) |bid| bid >= conditional_params.target_value else false,
                .PriceBelow => if (self.getBestAsk()) |ask| ask <= conditional_params.target_value else false,
                .SpreadWidth => if (self.getBestAsk()) |ask|
                    if (self.getBestBid()) |bid|
                        ask - bid >= conditional_params.target_value
                    else
                        false
                else
                    false,
                .VolumeThreshold => false, // Not implemented
            };

            if (is_met) {
                conditional_params.is_condition_met = true;
                try basic_orders.placeOrderWithType(self, order_data.*);
            }
        }
    }
}
