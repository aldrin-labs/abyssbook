const std = @import("std");
const order_params = @import("orderbook/order_params.zig");

pub const CacheAlignedOrder = struct {
    price: u64,
    amount: u64,
    id: u64,
    side: OrderSide,
    order_type: OrderType,
    stop_price: ?u64,
    flags: OrderFlags,
    expiry_time: ?i64 = null, // For GTD orders
    display_amount: ?u64 = null, // For iceberg orders
    twap_params: ?*TWAPParams = null,
    trailing_params: ?*TrailingStopParams = null,
    oso_params: ?*OSOParams = null,
    oco_params: ?*OCOParams = null,
    peg_params: ?*PegParams = null,
    discretionary_params: ?*DiscretionaryParams = null,
    conditional_params: ?*ConditionalParams = null,
    padding: [8]u8,

    pub fn init(price: u64, amount: u64, id: u64, side: OrderSide, order_type: OrderType, stop_price: ?u64) CacheAlignedOrder {
        return .{
            .price = price,
            .amount = amount,
            .id = id,
            .side = side,
            .order_type = order_type,
            .stop_price = stop_price,
            .flags = .{
                .is_stop = order_type == .Stop or order_type == .StopLimit,
                .is_ioc = order_type == .IOC,
                .is_fok = order_type == .FOK,
                .is_post_only = order_type == .PostOnly,
                .is_gtd = order_type == .GTD,
                .is_iceberg = order_type == .Iceberg,
                .is_oco = order_type == .OCO,
                .is_twap = order_type == .TWAP,
                .is_oso = order_type == .OSO,
                .is_trailing_stop = order_type == .TrailingStop,
                .is_peg = order_type == .Peg,
                .is_midpoint_peg = order_type == .MidpointPeg,
                .is_discretionary = order_type == .Discretionary,
                .is_conditional = order_type == .Conditional,
            },
            .expiry_time = null,
            .display_amount = null,
            .twap_params = null,
            .trailing_params = null,
            .oso_params = null,
            .oco_params = null,
            .peg_params = null,
            .discretionary_params = null,
            .conditional_params = null,
            .padding = [_]u8{0} ** 8,
        };
    }

    pub fn deinit(self: *CacheAlignedOrder, allocator: std.mem.Allocator) void {
        if (self.twap_params) |params| {
            allocator.destroy(params);
        }
        if (self.trailing_params) |params| {
            allocator.destroy(params);
        }
        if (self.oso_params) |params| {
            allocator.destroy(params);
        }
        if (self.oco_params) |params| {
            allocator.destroy(params);
        }
        if (self.peg_params) |params| {
            allocator.destroy(params);
        }
        if (self.discretionary_params) |params| {
            allocator.destroy(params);
        }
        if (self.conditional_params) |params| {
            if (params.reference_symbol) |symbol| {
                allocator.free(symbol);
            }
            allocator.destroy(params);
        }
    }
};

pub const OrderKey = struct {
    price: u64,
    id: u64,
};

pub const PriceLevel = struct {
    total_volume: u64,
    order_count: usize,
};

pub const OrderMap = std.AutoArrayHashMap(OrderKey, CacheAlignedOrder);
pub const PriceLevelMap = struct {
    levels: std.AutoArrayHashMap(u64, PriceLevel),
    sorted_prices: std.ArrayList(u64),
    is_sorted: bool,

    pub fn init(allocator: std.mem.Allocator) PriceLevelMap {
        return .{
            .levels = std.AutoArrayHashMap(u64, PriceLevel).init(allocator),
            .sorted_prices = std.ArrayList(u64).init(allocator),
            .is_sorted = false,
        };
    }

    pub fn deinit(self: *PriceLevelMap) void {
        self.levels.deinit();
        self.sorted_prices.deinit();
    }

    pub fn put(self: *PriceLevelMap, price: u64, level: PriceLevel) !void {
        try self.levels.put(price, level);
        self.is_sorted = false;
    }

    pub fn get(self: *const PriceLevelMap, price: u64) ?PriceLevel {
        return self.levels.get(price);
    }

    pub fn getPtr(self: *PriceLevelMap, price: u64) ?*PriceLevel {
        return self.levels.getPtr(price);
    }

    pub fn swapRemove(self: *PriceLevelMap, price: u64) bool {
        const removed = self.levels.swapRemove(price);
        if (removed) {
            self.is_sorted = false;
        }
        return removed;
    }

    pub fn count(self: *const PriceLevelMap) usize {
        return self.levels.count();
    }

    pub fn iterator(self: *const PriceLevelMap) std.AutoArrayHashMap(u64, PriceLevel).Iterator {
        return self.levels.iterator();
    }

    pub fn ensureSorted(self: *PriceLevelMap) !void {
        if (self.is_sorted) return;

        self.sorted_prices.clearRetainingCapacity();
        var it = self.levels.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.order_count > 0) {
                try self.sorted_prices.append(entry.key_ptr.*);
            }
        }

        std.mem.sort(u64, self.sorted_prices.items, {}, std.sort.desc(u64));
        self.is_sorted = true;
    }

    pub fn getBestPrice(self: *PriceLevelMap, is_bid: bool) !?u64 {
        try self.ensureSorted();
        if (self.sorted_prices.items.len == 0) return null;
        return if (is_bid)
            self.sorted_prices.items[0]
        else
            self.sorted_prices.items[self.sorted_prices.items.len - 1];
    }

    pub fn getNextPrice(self: *PriceLevelMap, current_price: u64, is_bid: bool) !?u64 {
        try self.ensureSorted();
        if (self.sorted_prices.items.len == 0) return null;

        const prices = self.sorted_prices.items;
        if (is_bid) {
            // Find next lower price
            for (prices) |price| {
                if (price < current_price) return price;
            }
        } else {
            // Find next higher price
            var i = prices.len;
            while (i > 0) : (i -= 1) {
                if (prices[i - 1] > current_price) return prices[i - 1];
            }
        }
        return null;
    }
};

pub const OrderSide = enum {
    Buy,
    Sell,
};

pub const MatchResult = struct {
    filled_amount: u64,
    remaining_amount: u64,
    execution_price: u64,
};

pub const OrderType = enum {
    Limit,
    Market,
    Stop,
    StopLimit,
    IOC,
    FOK,
    PostOnly,
    GTD,
    Iceberg,
    OCO, // One-Cancels-Other
    TWAP, // Time-Weighted Average Price
    OSO, // One-Sends-Other
    TrailingStop, // Trailing Stop
    Peg, // Pegged to best bid/ask
    MidpointPeg, // Pegged to spread midpoint
    Discretionary, // Limit order with discretionary price
    Conditional, // Executes based on custom conditions
};

pub const OrderFlags = packed struct {
    is_stop: bool = false,
    is_ioc: bool = false,
    is_fok: bool = false,
    is_post_only: bool = false,
    is_gtd: bool = false,
    is_iceberg: bool = false,
    is_oco: bool = false,
    is_twap: bool = false,
    is_oso: bool = false,
    is_trailing_stop: bool = false,
    is_peg: bool = false,
    is_midpoint_peg: bool = false,
    is_discretionary: bool = false,
    is_conditional: bool = false,
    padding: u2 = 0,
};

pub const TWAPParams = struct {
    total_amount: u64,
    interval_seconds: u64,
    num_intervals: u64,
    start_time: i64,
    amount_per_interval: u64,
    intervals_executed: u64 = 0,
};

pub const TrailingStopParams = struct {
    distance: u64, // Fixed distance from market price
    last_trigger_price: u64, // Last price that updated the stop price
    current_stop_price: u64, // Current stop price
};

pub const OSOParams = struct {
    child_order: CacheAlignedOrder,
    is_child_placed: bool = false,
};

pub const OCOParams = struct {
    linked_order: CacheAlignedOrder,
    is_cancelled: bool = false,
};

pub const OrderModification = struct {
    new_price: ?u64 = null,
    new_amount: ?u64 = null,
};

pub const PriceLevelStats = struct {
    total_volume: u64,
    order_count: usize,
    min_amount: u64,
    max_amount: u64,
    avg_amount: u64,
};

pub const StopOrderMap = std.AutoArrayHashMap(OrderKey, CacheAlignedOrder);

pub const OrderSnapshot = struct {
    price: u64,
    amount: u64,
    id: u64,
    side: OrderSide,
    order_type: OrderType,
    stop_price: ?u64,
};

pub const BookSnapshot = struct {
    bids: std.ArrayList(OrderSnapshot),
    asks: std.ArrayList(OrderSnapshot),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const BookSnapshot) void {
        self.bids.deinit();
        self.asks.deinit();
    }
};

const OrderEntry = struct { key: OrderKey, order: CacheAlignedOrder };

pub const ShardedOrderbook = struct {
    shards: []OrderMap,
    bid_levels: []PriceLevelMap,
    ask_levels: []PriceLevelMap,
    stop_orders: []StopOrderMap, // Stop orders waiting to be triggered
    shard_count: usize,
    allocator: std.mem.Allocator,
    current_order: ?*const CacheAlignedOrder = null, // Current order being processed
    current_order_flags: OrderFlags = .{}, // Flags of the current order
    best_bid_cache: ?u64 = null, // Cache for best bid price
    best_ask_cache: ?u64 = null, // Cache for best ask price

    pub fn init(allocator: std.mem.Allocator, shard_count: usize) !ShardedOrderbook {
        const shards = try allocator.alloc(OrderMap, shard_count);
        const bid_levels = try allocator.alloc(PriceLevelMap, shard_count);
        const ask_levels = try allocator.alloc(PriceLevelMap, shard_count);
        const stop_orders = try allocator.alloc(StopOrderMap, shard_count);

        for (0..shard_count) |i| {
            shards[i] = OrderMap.init(allocator);
            bid_levels[i] = PriceLevelMap.init(allocator);
            ask_levels[i] = PriceLevelMap.init(allocator);
            stop_orders[i] = StopOrderMap.init(allocator);
        }

        return ShardedOrderbook{
            .shards = shards,
            .bid_levels = bid_levels,
            .ask_levels = ask_levels,
            .stop_orders = stop_orders,
            .shard_count = shard_count,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ShardedOrderbook) void {
        for (0..self.shard_count) |i| {
            // Clean up orders and their allocated memory
            var order_it = self.shards[i].iterator();
            while (order_it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }

            // Clean up stop orders and their allocated memory
            var stop_it = self.stop_orders[i].iterator();
            while (stop_it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }

            self.shards[i].deinit();
            self.bid_levels[i].deinit();
            self.ask_levels[i].deinit();
            self.stop_orders[i].deinit();
        }
        self.allocator.free(self.shards);
        self.allocator.free(self.bid_levels);
        self.allocator.free(self.ask_levels);
        self.allocator.free(self.stop_orders);
    }

    pub const PriceLevelUpdate = struct {
        price: u64,
        volume_delta: i64,
        count_delta: i64,
    };

    fn updateBestPrices(self: *ShardedOrderbook, price: u64, side: OrderSide) void {
        if (side == .Buy) {
            self.best_bid_cache = if (self.best_bid_cache) |current_best|
                @max(current_best, price)
            else
                price;
        } else {
            self.best_ask_cache = if (self.best_ask_cache) |current_best|
                @min(current_best, price)
            else
                price;
        }
    }

    pub fn updatePriceLevels(self: *ShardedOrderbook, levels: *PriceLevelMap, updates: []const PriceLevelUpdate) !void {
        const BATCH_SIZE = 8;
        var max_price: ?u64 = null;
        var min_price: ?u64 = null;

        // Pre-allocate vectors for batch processing
        var volume_vec: [BATCH_SIZE]i64 align(32) = undefined;
        var count_vec: [BATCH_SIZE]i64 align(32) = undefined;
        var price_vec: [BATCH_SIZE]u64 align(32) = undefined;
        var level_ptrs: [BATCH_SIZE]?*PriceLevel = undefined;

        // Process updates in batches
        var i: usize = 0;
        while (i < updates.len) {
            const batch_end = @min(i + BATCH_SIZE, updates.len);
            const batch_size = batch_end - i;

            // Load batch data
            for (0..batch_size) |j| {
                const update = updates[i + j];
                volume_vec[j] = update.volume_delta;
                count_vec[j] = update.count_delta;
                price_vec[j] = update.price;

                // Track price range for cache update
                max_price = if (max_price) |p| @max(p, update.price) else update.price;
                min_price = if (min_price) |p| @min(p, update.price) else update.price;

                // Get or create price level
                level_ptrs[j] = levels.getPtr(update.price) orelse blk: {
                    try levels.put(update.price, .{ .total_volume = 0, .order_count = 0 });
                    break :blk levels.getPtr(update.price).?;
                };
            }

            // Process batch
            for (0..batch_size) |j| {
                if (level_ptrs[j]) |level| {
                    // Use saturating arithmetic for safer updates
                    if (volume_vec[j] < 0) {
                        level.total_volume = if (@as(u64, @intCast(@abs(volume_vec[j]))) > level.total_volume)
                            0
                        else
                            level.total_volume - @as(u64, @intCast(@abs(volume_vec[j])));
                    } else {
                        level.total_volume +|= @as(u64, @intCast(volume_vec[j]));
                    }

                    if (count_vec[j] < 0) {
                        level.order_count = if (@as(usize, @intCast(@abs(count_vec[j]))) > level.order_count)
                            0
                        else
                            level.order_count - @as(usize, @intCast(@abs(count_vec[j])));
                    } else {
                        level.order_count +|= @as(usize, @intCast(count_vec[j]));
                    }

                    if (level.order_count == 0) {
                        _ = levels.swapRemove(price_vec[j]);
                    }
                }
            }

            i = batch_end;
        }

        // Update best bid/ask cache if needed
        if (max_price != null or min_price != null) {
            // Update cache based on level type
            if (levels == &self.bid_levels[0] or levels == &self.bid_levels[1]) {
                self.updateBestPrices(max_price.?, .Buy);
            } else if (levels == &self.ask_levels[0] or levels == &self.ask_levels[1]) {
                self.updateBestPrices(min_price.?, .Sell);
            }
        }
    }

    pub fn updatePriceLevel(self: *ShardedOrderbook, levels: *PriceLevelMap, price: u64, volume_delta: i64, count_delta: i64) !void {
        const update = PriceLevelUpdate{
            .price = price,
            .volume_delta = volume_delta,
            .count_delta = count_delta,
        };
        try self.updatePriceLevels(levels, &[_]PriceLevelUpdate{update});
    }

    pub const OrderError = error{
        OutOfMemory,
        InvalidPrice,
        InvalidAmount,
        OrderNotFound,
        DuplicateOrder,
        NoBestBid,
        NoBestAsk,
        LastTradeNotImplemented,
    };

    pub const MatchError = OrderError;

    pub fn placeOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64) OrderError!void {
        if (amount == 0) {
            return OrderError.InvalidAmount;
        }

        // Check for duplicate order ID across all shards
        const key = OrderKey{ .price = price, .id = id };
        for (0..self.shard_count) |i| {
            if (self.shards[i].contains(OrderKey{ .price = 0, .id = id })) {
                return OrderError.DuplicateOrder;
            }
            // Also check all possible prices for this ID (since we don't know the price of existing orders)
            var it = self.shards[i].iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.id == id) {
                    return OrderError.DuplicateOrder;
                }
            }
        }

        const order = CacheAlignedOrder.init(price, amount, id, side, .Limit, null);
        const shard_index = self.priceToShard(price);

        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];
        try self.updatePriceLevel(levels, price, @as(i64, @intCast(amount)), 1);

        try self.shards[shard_index].put(key, order);
    }

    pub fn placeMarketOrder(self: *ShardedOrderbook, side: OrderSide, amount: u64, _: u64) !MatchResult {
        if (amount == 0) {
            return OrderError.InvalidAmount;
        }
        const price: u64 = if (side == .Buy) std.math.maxInt(u64) else 0;
        return self.matchOrder(side, price, amount);
    }

    pub fn placeOrderWithType(self: *ShardedOrderbook, order: CacheAlignedOrder) OrderError!void {
        const key = OrderKey{ .price = order.price, .id = order.id };

        // Handle stop orders
        if (order.flags.is_stop) {
            try self.stop_orders[self.priceToShard(order.price)].put(key, order);
            return;
        }

        // Regular limit order handling
        const levels = if (order.side == .Buy) &self.bid_levels[self.priceToShard(order.price)] else &self.ask_levels[self.priceToShard(order.price)];

        // For iceberg orders, only show the display amount
        const display_amount = if (order.display_amount) |amount|
            @min(amount, order.amount)
        else
            order.amount;

        try self.updatePriceLevel(levels, order.price, @as(i64, @intCast(display_amount)), 1);
        try self.shards[self.priceToShard(order.price)].put(key, order);

        // Only match certain order types immediately
        const should_match = switch (order.order_type) {
            .Stop, .StopLimit => true, // Stop orders should trigger matching
            .Limit => true, // Regular limit orders should match
            .TWAP, .Iceberg => false, // TWAP and Iceberg orders shouldn't match immediately
            else => true,
        };

        if (should_match) {
            _ = try self.matchOrder(order.side, order.price, order.amount);
        }
    }

    // Helper functions for different order types
    pub fn placeStopOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64, stop_price: u64) !void {
        const order = CacheAlignedOrder.init(price, amount, id, side, .Stop, stop_price);
        try self.placeOrderWithType(order);
    }

    pub fn placeStopLimitOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64, stop_price: u64) !void {
        const order = CacheAlignedOrder.init(price, amount, id, side, .StopLimit, stop_price);
        try self.placeOrderWithType(order);
    }

    pub fn placeIOCOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64) OrderError!void {
        const order = CacheAlignedOrder.init(price, amount, id, side, .IOC, null);
        try self.placeOrderWithType(order);
    }

    pub fn placeFOKOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64) OrderError!void {
        const order = CacheAlignedOrder.init(price, amount, id, side, .FOK, null);
        try self.placeOrderWithType(order);
    }

    pub fn placePostOnlyOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64) OrderError!void {
        const order = CacheAlignedOrder.init(price, amount, id, side, .PostOnly, null);
        try self.placeOrderWithType(order);
    }

    pub fn placeGTDOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64, expiry_time: i64) OrderError!void {
        var order = CacheAlignedOrder.init(price, amount, id, side, .GTD, null);
        order.expiry_time = expiry_time;
        try self.placeOrderWithType(order);
    }

    pub fn placeIcebergOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, total_amount: u64, display_amount: u64, id: u64) OrderError!void {
        var order = CacheAlignedOrder.init(price, total_amount, id, side, .Iceberg, null);
        order.display_amount = display_amount;
        try self.placeOrderWithType(order);
    }

    pub fn placeOCOOrder(self: *ShardedOrderbook, order1: CacheAlignedOrder, order2: CacheAlignedOrder) !void {
        const oco_params1 = try self.allocator.create(OCOParams);
        errdefer self.allocator.destroy(oco_params1);

        const oco_params2 = try self.allocator.create(OCOParams);
        errdefer self.allocator.destroy(oco_params2);

        // Link the orders to each other
        oco_params1.* = .{ .linked_order = order2, .is_cancelled = false };
        oco_params2.* = .{ .linked_order = order1, .is_cancelled = false };

        var order1_mod = order1;
        var order2_mod = order2;
        order1_mod.order_type = .OCO;
        order2_mod.order_type = .OCO;
        order1_mod.oco_params = oco_params1;
        order2_mod.oco_params = oco_params2;

        try self.placeOrderWithType(order1_mod);
        try self.placeOrderWithType(order2_mod);
    }

    pub fn placeTWAPOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, total_amount: u64, id: u64, num_intervals: u64, interval_seconds: u64) !void {
        const twap_params = try self.allocator.create(TWAPParams);
        errdefer self.allocator.destroy(twap_params);

        const amount_per_interval = @divFloor(total_amount, num_intervals);
        twap_params.* = .{
            .total_amount = total_amount,
            .interval_seconds = interval_seconds,
            .num_intervals = num_intervals,
            .start_time = std.time.timestamp(),
            .amount_per_interval = amount_per_interval,
            .intervals_executed = 0,
        };

        var order = CacheAlignedOrder.init(price, amount_per_interval, id, side, .TWAP, null);
        order.twap_params = twap_params;
        order.flags.is_twap = true;

        self.placeOrderWithType(order) catch |err| {
            // Clean up memory if placement fails
            self.allocator.destroy(twap_params);
            return err;
        };
    }

    pub fn placeOSOOrder(self: *ShardedOrderbook, primary_order: CacheAlignedOrder, child_order: CacheAlignedOrder) !void {
        const oso_params = try self.allocator.create(OSOParams);
        errdefer self.allocator.destroy(oso_params);

        oso_params.* = .{
            .child_order = child_order,
            .is_child_placed = false,
        };

        var parent_mod = primary_order;
        parent_mod.order_type = .OSO;
        parent_mod.oso_params = oso_params;
        try self.placeOrderWithType(parent_mod);
    }

    pub fn placeTrailingStopOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64, distance: u64) OrderError!void {
        const trailing_params = try self.allocator.create(TrailingStopParams);
        errdefer self.allocator.destroy(trailing_params);

        const current_price = if (side == .Buy) self.getBestAsk() orelse price else self.getBestBid() orelse price;
        const current_stop_price = if (side == .Buy) current_price + distance else current_price - distance;

        trailing_params.* = .{
            .distance = distance,
            .last_trigger_price = current_price,
            .current_stop_price = current_stop_price,
        };

        var order = CacheAlignedOrder.init(price, amount, id, side, .TrailingStop, current_stop_price);
        order.trailing_params = trailing_params;
        order.flags.is_trailing_stop = true;

        // Add to stop_orders instead of regular orders
        const shard_index = self.priceToShard(price);
        const key = OrderKey{ .price = price, .id = id };
        try self.stop_orders[shard_index].put(key, order);
    }

    pub fn placePegOrder(self: *ShardedOrderbook, side: OrderSide, amount: u64, peg_type: PegType, offset: i64, limit_price: ?u64, id: u64) OrderError!void {
        const peg_params = try self.allocator.create(PegParams);
        errdefer self.allocator.destroy(peg_params);

        peg_params.* = .{
            .peg_type = peg_type,
            .offset = offset,
            .limit_price = limit_price,
        };

        const initial_price = switch (peg_type) {
            .BestBid => self.getBestBid() orelse return error.InvalidPrice,
            .BestAsk => self.getBestAsk() orelse return error.InvalidPrice,
            .Midpoint => blk: {
                const bid = self.getBestBid() orelse return error.InvalidPrice;
                const ask = self.getBestAsk() orelse return error.InvalidPrice;
                break :blk (bid + ask) / 2;
            },
            .LastTrade => return error.InvalidPrice, // Not implemented yet
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

        var order = CacheAlignedOrder.init(final_price, amount, id, side, .Peg, null);
        order.peg_params = peg_params;
        order.flags.is_peg = true;

        try self.placeOrderWithType(order);
    }

    pub fn placeMidpointPegOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64, offset: i64, limit_price: ?u64) OrderError!void {
        try self.placePegOrder(CacheAlignedOrder.init(price, amount, id, side, .Midpoint, offset, limit_price));
    }

    pub fn placeDiscretionaryOrder(self: *ShardedOrderbook, side: OrderSide, base_price: u64, amount: u64, id: u64, discretionary_price: u64) OrderError!void {
        const disc_params = try self.allocator.create(DiscretionaryParams);
        errdefer self.allocator.destroy(disc_params);

        disc_params.* = .{
            .base_price = base_price,
            .discretionary_price = discretionary_price,
            .last_executed_price = null,
        };

        var order = CacheAlignedOrder.init(base_price, amount, id, side, .Discretionary, null);
        order.discretionary_params = disc_params;
        order.flags.is_discretionary = true;

        // Set current order context for matching
        self.current_order = &order;
        self.current_order_flags = order.flags;
        defer {
            self.current_order = null;
            self.current_order_flags = .{};
        }

        self.placeOrderWithType(order) catch |err| {
            // Clean up memory if placement fails
            self.allocator.destroy(disc_params);
            return err;
        };
    }

    pub fn placeConditionalOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64, condition_type: ConditionalType, target_value: u64) OrderError!void {
        const cond_params = try self.allocator.create(ConditionalParams);
        errdefer self.allocator.destroy(cond_params);

        cond_params.* = .{
            .condition_type = condition_type,
            .price_threshold = target_value,
            .time_threshold = null,
            .volume_threshold = null,
            .custom_condition = null,
            .reference_symbol = null,
            .is_condition_met = false,
        };

        var order = CacheAlignedOrder.init(price, amount, id, side, .Conditional, null);
        order.conditional_params = cond_params;
        order.flags.is_conditional = true;

        try self.placeOrderWithType(order);
    }

    pub fn getBestBid(self: *ShardedOrderbook) ?u64 {
        if (self.best_bid_cache) |price| {
            return price;
        }

        var best_bid: ?u64 = null;
        for (self.bid_levels) |levels| {
            var it = levels.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.order_count == 0) continue;
                best_bid = if (best_bid) |current_best|
                    @max(current_best, entry.key_ptr.*)
                else
                    entry.key_ptr.*;
            }
        }
        self.best_bid_cache = best_bid;
        return best_bid;
    }

    pub fn getBestAsk(self: *ShardedOrderbook) ?u64 {
        if (self.best_ask_cache) |price| {
            return price;
        }

        var best_ask: ?u64 = null;
        for (self.ask_levels) |levels| {
            var it = levels.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.order_count == 0) continue;
                best_ask = if (best_ask) |current_best|
                    @min(current_best, entry.key_ptr.*)
                else
                    entry.key_ptr.*;
            }
        }
        self.best_ask_cache = best_ask;
        return best_ask;
    }

    fn getNextBid(self: *ShardedOrderbook, current_price: u64) ?u64 {
        var next_bid: ?u64 = null;
        for (self.bid_levels) |levels| {
            var it = levels.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.order_count == 0) continue;
                if (entry.key_ptr.* < current_price) {
                    next_bid = if (next_bid) |current_next|
                        @max(current_next, entry.key_ptr.*)
                    else
                        entry.key_ptr.*;
                }
            }
        }
        return next_bid;
    }

    fn getNextAsk(self: *ShardedOrderbook, current_price: u64) ?u64 {
        var next_ask: ?u64 = null;
        for (self.ask_levels) |levels| {
            var it = levels.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.order_count == 0) continue;
                if (entry.key_ptr.* > current_price) {
                    next_ask = if (next_ask) |current_next|
                        @min(current_next, entry.key_ptr.*)
                    else
                        entry.key_ptr.*;
                }
            }
        }
        return next_ask;
    }

    pub fn getOrdersInRange(self: *const ShardedOrderbook, start_price: u64, end_price: u64, shard_index: usize) u64 {
        var total_amount: u64 = 0;
        var it = self.shards[shard_index].iterator();

        while (it.next()) |entry| {
            const price = entry.key_ptr.price;
            if (price >= start_price and price <= end_price) {
                total_amount += entry.value_ptr.amount;
            }
        }
        return total_amount;
    }

    pub fn priceToShard(self: *const ShardedOrderbook, price: u64) usize {
        return @intCast(price % self.shard_count);
    }

    pub fn cancelOrder(self: *ShardedOrderbook, id: u64) OrderError!void {
        // Search all shards for the order
        for (0..self.shard_count) |i| {
            var it = self.shards[i].iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.*.id == id) {
                    var order = entry.value_ptr.*;
                    const levels = if (order.side == .Buy) &self.bid_levels[i] else &self.ask_levels[i];

                    // Update price level
                    try self.updatePriceLevel(levels, order.price, -@as(i64, @intCast(order.amount)), -1);

                    // Clean up order memory
                    order.deinit(self.allocator);

                    // Remove order
                    _ = self.shards[i].swapRemove(entry.key_ptr.*);
                    return;
                }
            }

            // Also check stop orders
            var stop_it = self.stop_orders[i].iterator();
            while (stop_it.next()) |entry| {
                if (entry.value_ptr.*.id == id) {
                    var order = entry.value_ptr.*;
                    // Clean up order memory
                    order.deinit(self.allocator);
                    _ = self.stop_orders[i].orderedRemove(entry.key_ptr.*);
                    return;
                }
            }
        }
        return OrderError.OrderNotFound;
    }

    pub fn matchOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64) MatchError!MatchResult {
        const saved_order = self.current_order;
        const saved_flags = self.current_order_flags;
        defer {
            self.current_order = saved_order;
            self.current_order_flags = saved_flags;
        }

        var executed_amount: u64 = 0;
        var remaining_amount = amount;
        var execution_price = price;

        const is_buy = side == .Buy;
        const best_counter_price = if (is_buy) self.getBestAsk() else self.getBestBid();
        const is_market_order = (is_buy and price == std.math.maxInt(u64)) or (!is_buy and price == 0);

        // For OCO orders, check if the linked order should be cancelled
        if (self.current_order_flags.is_oco and self.current_order.?.oco_params != null) {
            const oco_params = self.current_order.?.oco_params.?;
            if (!oco_params.is_cancelled) {
                try self.cancelOrder(oco_params.linked_order.id);
                oco_params.is_cancelled = true;
            }
        }

        // For TWAP orders, don't match immediately
        if (self.current_order_flags.is_twap) {
            return MatchResult{
                .filled_amount = 0,
                .remaining_amount = amount,
                .execution_price = price,
            };
        }

        // For Trailing Stop orders, update the stop price based on market movement
        if (self.current_order_flags.is_trailing_stop and self.current_order.?.trailing_params != null) {
            const trailing_params = self.current_order.?.trailing_params.?;
            const current_market_price = if (is_buy)
                self.getBestAsk() orelse price
            else
                self.getBestBid() orelse price;

            if (is_buy) {
                if (current_market_price < trailing_params.last_trigger_price) {
                    trailing_params.last_trigger_price = current_market_price;
                    try self.executeTrailingStopOrder(self.current_order.?);
                }
            } else {
                if (current_market_price > trailing_params.last_trigger_price) {
                    trailing_params.last_trigger_price = current_market_price;
                    try self.executeTrailingStopOrder(self.current_order.?);
                }
            }
        }

        // For Peg orders, update the order price based on the reference price
        if (self.current_order_flags.is_peg and self.current_order.?.peg_params != null) {
            const peg_params = self.current_order.?.peg_params.?;
            const reference_price = switch (peg_params.peg_type) {
                .BestBid => self.getBestBid() orelse return error.NoBestBid,
                .BestAsk => self.getBestAsk() orelse return error.NoBestAsk,
                .Midpoint => blk: {
                    const bid = self.getBestBid() orelse return error.NoBestBid;
                    const ask = self.getBestAsk() orelse return error.NoBestAsk;
                    break :blk (bid + ask) / 2;
                },
                .LastTrade => return error.LastTradeNotImplemented,
            };

            const pegged_price = @as(u64, @intCast(@as(i64, @intCast(reference_price)) + peg_params.offset));
            if (peg_params.limit_price) |limit_price| {
                if ((is_buy and pegged_price > limit_price) or (!is_buy and pegged_price < limit_price)) {
                    return MatchResult{
                        .filled_amount = 0,
                        .remaining_amount = amount,
                        .execution_price = price,
                    };
                }
            }
            execution_price = pegged_price;
        }

        // For Discretionary orders, try matching at discretionary price first
        if (self.current_order_flags.is_discretionary and self.current_order.?.discretionary_params != null) {
            const disc_params = self.current_order.?.discretionary_params.?;
            const disc_result = try self.executeMatchCore(side, disc_params.discretionary_price, remaining_amount, is_buy, best_counter_price, true);

            if (disc_result.filled_amount > 0) {
                disc_params.last_executed_price = disc_result.execution_price;
                return disc_result;
            }
            // If no match at discretionary price, continue with base price
            execution_price = disc_params.base_price;
        }

        // For Conditional orders, check if conditions are met
        if (self.current_order_flags.is_conditional and self.current_order.?.conditional_params != null) {
            const cond_params = self.current_order.?.conditional_params.?;
            const condition_met = switch (cond_params.condition_type) {
                .Price => if (is_buy)
                    self.getBestAsk() orelse std.math.maxInt(u64) <= cond_params.price_threshold.?
                else
                    self.getBestBid() orelse 0 >= cond_params.price_threshold.?,
                .Time => if (cond_params.time_threshold) |threshold|
                    std.time.timestamp() >= threshold
                else
                    false,
                .Volume => if (cond_params.volume_threshold) |threshold|
                    self.getVolumeAtLevel(price, side) catch 0 >= threshold
                else
                    false,
                .Custom => if (cond_params.custom_condition) |condition|
                    condition(self.current_order.?)
                else
                    false,
            };

            if (!condition_met) {
                return MatchResult{
                    .filled_amount = 0,
                    .remaining_amount = amount,
                    .execution_price = price,
                };
            }
            cond_params.is_condition_met = true;
        }

        // Execute the match
        const result = try self.executeMatchCore(side, execution_price, remaining_amount, is_buy, best_counter_price, is_market_order);
        executed_amount = result.filled_amount;
        remaining_amount = result.remaining_amount;
        execution_price = result.execution_price;

        // For OSO orders, place the child order if parent is fully filled
        if (self.current_order_flags.is_oso and
            self.current_order.?.oso_params != null and
            executed_amount == amount)
        {
            const oso_params = self.current_order.?.oso_params.?;
            if (!oso_params.is_child_placed) {
                try self.placeOrderWithType(oso_params.child_order);
                oso_params.is_child_placed = true;
            }
        }

        return MatchResult{
            .filled_amount = executed_amount,
            .remaining_amount = remaining_amount,
            .execution_price = if (executed_amount > 0) execution_price else price,
        };
    }

    // Core matching logic moved to a separate function
    fn executeMatchCore(
        self: *ShardedOrderbook,
        side: OrderSide,
        price: u64,
        amount: u64,
        is_buy: bool,
        best_counter_price: ?u64,
        is_market_order: bool,
    ) !MatchResult {
        const VECTOR_WIDTH = if (@import("builtin").cpu.arch == .x86_64) @as(usize, 4) else @as(usize, 2);
        const BATCH_SIZE = VECTOR_WIDTH * 4;

        var executed_amount: u64 = 0;
        var remaining_amount = amount;
        var execution_price = price;
        var current_best_price = best_counter_price;

        // Pre-allocate vectors for SIMD operations
        var amount_vec: [VECTOR_WIDTH]u64 align(32) = undefined;
        var price_vec: [VECTOR_WIDTH]u64 align(32) = undefined;
        var match_vec: [VECTOR_WIDTH]bool align(32) = undefined;

        while (current_best_price != null and remaining_amount > 0) : (current_best_price = if (is_buy) self.getNextAsk(current_best_price.?) else self.getNextBid(current_best_price.?)) {
            if (!is_market_order and ((is_buy and current_best_price.? > price) or (!is_buy and current_best_price.? < price))) {
                break;
            }

            const shard_index = self.priceToShard(current_best_price.?);
            var orders = std.ArrayList(OrderEntry).init(self.allocator);
            defer orders.deinit();

            // Collect orders at this price level
            var it = self.shards[shard_index].iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.price == current_best_price.? and entry.value_ptr.side != side) {
                    try orders.append(.{ .key = entry.key_ptr.*, .order = entry.value_ptr.* });
                }
            }

            // Process orders in SIMD batches
            var batch_index: usize = 0;
            while (batch_index + BATCH_SIZE <= orders.items.len) : (batch_index += BATCH_SIZE) {
                var batch_executed: u64 = 0;
                var j: usize = 0;
                while (j < BATCH_SIZE and remaining_amount > 0) : (j += VECTOR_WIDTH) {
                    // Load prices and amounts into vectors
                    for (0..VECTOR_WIDTH) |k| {
                        if (j + k < BATCH_SIZE) {
                            price_vec[k] = orders.items[batch_index + j + k].order.price;
                            amount_vec[k] = @min(orders.items[batch_index + j + k].order.amount, remaining_amount);
                            match_vec[k] = if (is_buy)
                                price_vec[k] <= price
                            else
                                price_vec[k] >= price;
                        } else {
                            price_vec[k] = 0;
                            amount_vec[k] = 0;
                            match_vec[k] = false;
                        }
                    }

                    // Calculate matches using SIMD
                    const vec: @Vector(VECTOR_WIDTH, u64) = amount_vec;
                    const match_mask: @Vector(VECTOR_WIDTH, bool) = match_vec;
                    const zero_vec: @Vector(VECTOR_WIDTH, u64) = @splat(@as(u64, 0));
                    const matched_amounts = @select(u64, match_mask, vec, zero_vec);
                    const sum = @reduce(.Add, matched_amounts);
                    batch_executed += sum;
                    remaining_amount -= @min(remaining_amount, sum);

                    // Update orders
                    for (0..VECTOR_WIDTH) |k| {
                        if (j + k < BATCH_SIZE and match_vec[k] and amount_vec[k] > 0) {
                            try self.updateMatchedOrder(&orders.items[batch_index + j + k], amount_vec[k], current_best_price.?, shard_index);
                        }
                    }
                }

                executed_amount += batch_executed;
                execution_price = current_best_price.?;
            }

            // Handle remaining orders
            while (batch_index < orders.items.len and remaining_amount > 0) {
                const order_entry = &orders.items[batch_index];
                const should_match = if (is_buy)
                    order_entry.order.price <= price
                else
                    order_entry.order.price >= price;

                if (should_match) {
                    // For iceberg orders, limit matching to the display amount
                    const available_amount = if (order_entry.order.flags.is_iceberg)
                        @min(order_entry.order.amount, order_entry.order.display_amount.?)
                    else
                        order_entry.order.amount;
                    
                    const matched = @min(remaining_amount, available_amount);
                    if (matched > 0) {
                        try self.updateMatchedOrder(order_entry, matched, current_best_price.?, shard_index);
                        executed_amount += matched;
                        remaining_amount -= matched;
                        execution_price = current_best_price.?;
                    }
                }
                batch_index += 1;
            }
        }

        return MatchResult{
            .filled_amount = executed_amount,
            .remaining_amount = remaining_amount,
            .execution_price = execution_price,
        };
    }

    fn updateMatchedOrder(
        self: *ShardedOrderbook,
        order_entry: *OrderEntry,
        matched_amount: u64,
        execution_price: u64,
        shard_index: usize,
    ) !void {
        const levels = if (order_entry.order.side == .Buy)
            &self.bid_levels[shard_index]
        else
            &self.ask_levels[shard_index];

        // For iceberg orders, check if the display amount is fully matched
        const is_fully_matched = if (order_entry.order.flags.is_iceberg)
            matched_amount == @min(order_entry.order.amount, order_entry.order.display_amount.?)
        else
            matched_amount == order_entry.order.amount;
            
        if (is_fully_matched) {
            try self.updatePriceLevel(levels, execution_price, -@as(i64, @intCast(matched_amount)), -1);

            // Handle iceberg replenishment BEFORE removing the order
            if (order_entry.order.flags.is_iceberg) {
                // For iceberg orders, matched_amount represents the display amount that was matched
                // The order.amount contains the total remaining amount (including hidden reserves)
                const remaining_total = order_entry.order.amount - matched_amount;
                
                if (remaining_total > 0) {
                    // Replenish the iceberg with a new display portion
                    var replenished_order = order_entry.order;
                    replenished_order.amount = remaining_total;
                    const new_display_amount = @min(remaining_total, order_entry.order.display_amount.?);
                    replenished_order.display_amount = new_display_amount;
                    
                    // Replace the order in the shard (no need to remove first)
                    try self.shards[shard_index].put(order_entry.key, replenished_order);
                    // Add the new display amount back to the price level
                    try self.updatePriceLevel(levels, execution_price, @as(i64, @intCast(new_display_amount)), 1);
                } else {
                    // No remaining amount, remove the order completely
                    var order_to_remove = order_entry.order;
                    order_to_remove.deinit(self.allocator);
                    _ = self.shards[shard_index].swapRemove(order_entry.key);
                }
            } else {
                // Regular order - remove it completely
                var order_to_remove = order_entry.order;
                order_to_remove.deinit(self.allocator);
                _ = self.shards[shard_index].swapRemove(order_entry.key);
            }
        } else {
            try self.updatePriceLevel(levels, execution_price, -@as(i64, @intCast(matched_amount)), 0);
            var updated_order = order_entry.order;
            updated_order.amount -= matched_amount;
            try self.shards[shard_index].put(order_entry.key, updated_order);
        }
    }

    pub fn executeOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64, id: u64) !MatchResult {
        const match_result = try self.matchOrder(side, price, amount);

        if (match_result.remaining_amount > 0) {
            // For buy orders: only place if our price >= execution price (or no execution)
            // For sell orders: only place if our price <= execution price (or no execution)
            const should_place = match_result.filled_amount == 0 or
                (side == .Buy and price >= match_result.execution_price) or
                (side == .Sell and price <= match_result.execution_price);

            if (should_place) {
                try self.placeOrder(side, price, match_result.remaining_amount, id);
            } else {
                // Place at the last execution price if we got a partial fill
                try self.placeOrder(side, match_result.execution_price, match_result.remaining_amount, id);
            }
        }

        return match_result;
    }

    pub fn getVolume(self: *const ShardedOrderbook, side: OrderSide, price: u64) OrderError!u64 {
        const shard_index = self.priceToShard(price);
        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];

        if (levels.get(price)) |level| {
            return level.total_volume;
        }
        return 0;
    }

    pub fn getVolumeAtLevel(self: *const ShardedOrderbook, price: u64, side: OrderSide) !u64 {
        const shard_index = self.priceToShard(price);
        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];
        return if (levels.get(price)) |level| level.total_volume else 0;
    }

    pub fn getOrderCountAtLevel(self: *const ShardedOrderbook, price: u64, side: OrderSide) usize {
        const shard_index = self.priceToShard(price);
        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];
        return if (levels.get(price)) |level| level.order_count else 0;
    }

    pub fn getDepth(self: *const ShardedOrderbook, levels: usize) struct { bids: []const [2]u64, asks: []const [2]u64 } {
        var bids = std.ArrayList([2]u64).init(self.allocator);
        var asks = std.ArrayList([2]u64).init(self.allocator);

        var prices = std.ArrayList(u64).init(self.allocator);
        defer prices.deinit();

        // Collect bid prices
        for (self.shards) |shard| {
            var it = shard.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.side == .Buy) {
                    prices.append(entry.key_ptr.price) catch continue;
                }
            }
        }

        // Sort prices for bids (descending)
        std.mem.sort(u64, prices.items, {}, std.sort.desc(u64));
        var count: usize = 0;

        for (prices.items) |price| {
            const volume = self.getVolume(.Buy, price) catch continue;
            if (volume == 0) continue;

            if (count < levels) {
                bids.append(.{ price, volume }) catch continue;
                count += 1;
            }
        }

        // Clear prices for asks
        prices.clearRetainingCapacity();

        // Collect ask prices
        for (self.shards) |shard| {
            var it = shard.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.side == .Sell) {
                    prices.append(entry.key_ptr.price) catch continue;
                }
            }
        }

        // Sort prices for asks (ascending)
        std.mem.sort(u64, prices.items, {}, std.sort.asc(u64));
        count = 0;

        for (prices.items) |price| {
            const volume = self.getVolume(.Sell, price) catch continue;
            if (volume == 0) continue;

            if (count < levels) {
                asks.append(.{ price, volume }) catch continue;
                count += 1;
            }
        }

        const bid_slice = bids.toOwnedSlice() catch &[_][2]u64{};
        const ask_slice = asks.toOwnedSlice() catch &[_][2]u64{};

        return .{
            .bids = bid_slice,
            .asks = ask_slice,
        };
    }

    pub fn modifyOrder(self: *ShardedOrderbook, price: u64, id: u64, modification: OrderModification) !bool {
        const shard_index = self.priceToShard(price);
        const key = OrderKey{ .price = price, .id = id };

        if (self.shards[shard_index].getEntry(key)) |entry| {
            var order = entry.value_ptr.*;
            const old_amount = order.amount;
            const old_price = order.price;

            // Update amount if specified
            if (modification.new_amount) |new_amount| {
                if (new_amount == 0) {
                    return self.cancelOrder(id);
                }
                order.amount = new_amount;
            }

            // Update price if specified
            if (modification.new_price) |new_price| {
                if (new_price != price) {
                    // Remove from old price level
                    const old_levels = if (order.side == .Buy)
                        &self.bid_levels[shard_index]
                    else
                        &self.ask_levels[shard_index];
                    try self.updatePriceLevel(old_levels, old_price, -@as(i64, @intCast(old_amount)), -1);

                    // Add to new price level
                    const new_shard_index = self.priceToShard(new_price);
                    const new_levels = if (order.side == .Buy)
                        &self.bid_levels[new_shard_index]
                    else
                        &self.ask_levels[new_shard_index];
                    try self.updatePriceLevel(new_levels, new_price, @as(i64, @intCast(order.amount)), 1);

                    // Remove old order and add new one
                    _ = self.shards[shard_index].swapRemove(key);
                    const new_key = OrderKey{ .price = new_price, .id = id };
                    order.price = new_price;
                    try self.shards[new_shard_index].put(new_key, order);
                    return true;
                }
            } else if (modification.new_amount) |new_amount| {
                // Just update amount at current price level
                const levels = if (order.side == .Buy)
                    &self.bid_levels[shard_index]
                else
                    &self.ask_levels[shard_index];
                const amount_delta = @as(i64, @intCast(new_amount)) - @as(i64, @intCast(old_amount));
                try self.updatePriceLevel(levels, price, amount_delta, 0);
                try self.shards[shard_index].put(key, order);
                return true;
            }
        }

        return false;
    }

    pub fn executeMarketOrder(self: *ShardedOrderbook, side: OrderSide, amount: u64) !MatchResult {
        return self.placeMarketOrder(side, amount, 0); // Use 0 as a placeholder ID for market orders
    }

    pub fn getPriceLevelStats(self: *const ShardedOrderbook, price: u64, side: OrderSide) ?PriceLevelStats {
        const shard_index = self.priceToShard(price);
        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];

        if (levels.get(price)) |level| {
            if (level.order_count == 0) return null;

            var min_amount: u64 = std.math.maxInt(u64);
            var max_amount: u64 = 0;
            var total_amount: u64 = 0;

            var it = self.shards[shard_index].iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.price == price and entry.value_ptr.side == side) {
                    min_amount = @min(min_amount, entry.value_ptr.amount);
                    max_amount = @max(max_amount, entry.value_ptr.amount);
                    total_amount += entry.value_ptr.amount;
                }
            }

            return PriceLevelStats{
                .total_volume = level.total_volume,
                .order_count = level.order_count,
                .min_amount = min_amount,
                .max_amount = max_amount,
                .avg_amount = total_amount / level.order_count,
            };
        }

        return null;
    }

    // Add new function to check and trigger stop orders
    pub fn checkStopOrders(self: *ShardedOrderbook, price: u64) OrderError!void {
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
                            return OrderError.OutOfMemory;
                        };
                        return err;
                    };
                }
            }
        }
    }

    // Snapshot and persistence functions
    pub fn takeSnapshot(self: *const ShardedOrderbook) !BookSnapshot {
        var bids = std.ArrayList(OrderSnapshot).init(self.allocator);
        var asks = std.ArrayList(OrderSnapshot).init(self.allocator);

        // Collect regular orders
        for (self.shards) |shard| {
            var it = shard.iterator();
            while (it.next()) |entry| {
                const order = entry.value_ptr.*;
                const order_snapshot = OrderSnapshot{
                    .price = order.price,
                    .amount = order.amount,
                    .id = order.id,
                    .side = order.side,
                    .order_type = order.order_type,
                    .stop_price = order.stop_price,
                };

                switch (order.side) {
                    .Buy => try bids.append(order_snapshot),
                    .Sell => try asks.append(order_snapshot),
                }
            }
        }

        // Collect stop orders
        for (self.stop_orders) |shard| {
            var it = shard.iterator();
            while (it.next()) |entry| {
                const order = entry.value_ptr.*;
                const order_snapshot = OrderSnapshot{
                    .price = order.price,
                    .amount = order.amount,
                    .id = order.id,
                    .side = order.side,
                    .order_type = order.order_type,
                    .stop_price = order.stop_price,
                };

                switch (order.side) {
                    .Buy => try bids.append(order_snapshot),
                    .Sell => try asks.append(order_snapshot),
                }
            }
        }

        // Sort bids by price descending (highest first)
        std.mem.sort(OrderSnapshot, bids.items, {}, struct {
            fn lessThan(_: void, a: OrderSnapshot, b: OrderSnapshot) bool {
                return a.price > b.price;
            }
        }.lessThan);

        // Sort asks by price ascending (lowest first)
        std.mem.sort(OrderSnapshot, asks.items, {}, struct {
            fn lessThan(_: void, a: OrderSnapshot, b: OrderSnapshot) bool {
                return a.price < b.price;
            }
        }.lessThan);

        return BookSnapshot{
            .bids = bids,
            .asks = asks,
            .allocator = self.allocator,
        };
    }

    pub fn restoreFromSnapshot(self: *ShardedOrderbook, snapshot: BookSnapshot) !void {
        // Clear existing state
        for (0..self.shard_count) |i| {
            self.shards[i].clearRetainingCapacity();
            self.bid_levels[i].clearRetainingCapacity();
            self.ask_levels[i].clearRetainingCapacity();
            self.stop_orders[i].clearRetainingCapacity();
        }

        // Restore orders from both bids and asks
        for (snapshot.bids.items) |order| {
            const cache_aligned = CacheAlignedOrder.init(
                order.price,
                order.amount,
                order.id,
                order.side,
                order.order_type,
                order.stop_price,
            );
            try self.placeOrderWithType(cache_aligned);
        }

        for (snapshot.asks.items) |order| {
            const cache_aligned = CacheAlignedOrder.init(
                order.price,
                order.amount,
                order.id,
                order.side,
                order.order_type,
                order.stop_price,
            );
            try self.placeOrderWithType(cache_aligned);
        }
    }

    pub fn saveToFile(self: *const ShardedOrderbook, file_path: []const u8) !void {
        const snapshot = try self.takeSnapshot();
        defer snapshot.deinit();

        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var writer = file.writer();

        // Write header
        try writer.writeInt(u64, snapshot.bids.items.len, .little);
        try writer.writeInt(u64, snapshot.asks.items.len, .little);

        // Write bids
        for (snapshot.bids.items) |order| {
            try writer.writeInt(u64, order.price, .little);
            try writer.writeInt(u64, order.amount, .little);
            try writer.writeInt(u64, order.id, .little);
            try writer.writeInt(u8, @intFromEnum(order.side), .little);
            try writer.writeInt(u8, @intFromEnum(order.order_type), .little);
            try writer.writeByte(if (order.stop_price != null) 1 else 0);
            if (order.stop_price) |stop_price| {
                try writer.writeInt(u64, stop_price, .little);
            }
        }

        // Write asks
        for (snapshot.asks.items) |order| {
            try writer.writeInt(u64, order.price, .little);
            try writer.writeInt(u64, order.amount, .little);
            try writer.writeInt(u64, order.id, .little);
            try writer.writeInt(u8, @intFromEnum(order.side), .little);
            try writer.writeInt(u8, @intFromEnum(order.order_type), .little);
            try writer.writeByte(if (order.stop_price != null) 1 else 0);
            if (order.stop_price) |stop_price| {
                try writer.writeInt(u64, stop_price, .little);
            }
        }
    }

    pub fn loadFromFile(self: *ShardedOrderbook, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var reader = file.reader();

        // Read header
        const bid_count = try reader.readInt(u64, .little);
        const ask_count = try reader.readInt(u64, .little);

        // Read bids
        var bids = std.ArrayList(OrderSnapshot).init(self.allocator);
        var i: usize = 0;
        while (i < bid_count) : (i += 1) {
            const price = try reader.readInt(u64, .little);
            const amount = try reader.readInt(u64, .little);
            const id = try reader.readInt(u64, .little);
            const side = @as(OrderSide, @enumFromInt(try reader.readInt(u8, .little)));
            const order_type = @as(OrderType, @enumFromInt(try reader.readInt(u8, .little)));
            const has_stop_price = try reader.readByte() == 1;
            const stop_price = if (has_stop_price)
                try reader.readInt(u64, .little)
            else
                null;

            try bids.append(.{
                .price = price,
                .amount = amount,
                .id = id,
                .side = side,
                .order_type = order_type,
                .stop_price = stop_price,
            });
        }

        // Read asks
        var asks = std.ArrayList(OrderSnapshot).init(self.allocator);
        i = 0;
        while (i < ask_count) : (i += 1) {
            const price = try reader.readInt(u64, .little);
            const amount = try reader.readInt(u64, .little);
            const id = try reader.readInt(u64, .little);
            const side = @as(OrderSide, @enumFromInt(try reader.readInt(u8, .little)));
            const order_type = @as(OrderType, @enumFromInt(try reader.readInt(u8, .little)));
            const has_stop_price = try reader.readByte() == 1;
            const stop_price = if (has_stop_price)
                try reader.readInt(u64, .little)
            else
                null;

            try asks.append(.{
                .price = price,
                .amount = amount,
                .id = id,
                .side = side,
                .order_type = order_type,
                .stop_price = stop_price,
            });
        }

        // Create snapshot and restore
        const snapshot = BookSnapshot{
            .bids = bids,
            .asks = asks,
            .allocator = self.allocator,
        };
        defer snapshot.deinit();

        try self.restoreFromSnapshot(snapshot);
    }

    pub fn getStopPrice(self: *const ShardedOrderbook, id: u64) ?u64 {
        for (self.stop_orders) |shard| {
            var it = shard.iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.id == id) {
                    return entry.value_ptr.stop_price;
                }
            }
        }
        return null;
    }

    pub fn getOrderPrice(self: *const ShardedOrderbook, id: u64) !u64 {
        for (self.shards) |shard| {
            var it = shard.iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.id == id) {
                    return entry.value_ptr.price;
                }
            }
        }
        return error.OrderNotFound;
    }

    pub fn executeTrailingStopOrder(self: *ShardedOrderbook, order_data: *const CacheAlignedOrder) !void {
        const trailing_params = order_data.trailing_params.?;
        const current_market_price = if (order_data.side == .Buy)
            self.getBestAsk() orelse order_data.price
        else
            self.getBestBid() orelse order_data.price;

        var should_update = false;
        var new_stop_price = order_data.stop_price.?;

        if (order_data.side == .Buy) {
            if (current_market_price < trailing_params.last_trigger_price) {
                trailing_params.last_trigger_price = current_market_price;
                new_stop_price = current_market_price + trailing_params.distance;
                should_update = true;
            }
        } else {
            if (current_market_price > trailing_params.last_trigger_price) {
                trailing_params.last_trigger_price = current_market_price;
                new_stop_price = current_market_price - trailing_params.distance;
                should_update = true;
            }
        }

        if (should_update) {
            // Remove old order
            const shard_index = self.priceToShard(order_data.price);
            const key = OrderKey{ .price = order_data.price, .id = order_data.id };
            _ = self.stop_orders[shard_index].orderedRemove(key);

            // Create new order with updated stop price
            var new_order = CacheAlignedOrder.init(
                order_data.price,
                order_data.amount,
                order_data.id,
                order_data.side,
                .TrailingStop,
                new_stop_price,
            );
            new_order.trailing_params = trailing_params;
            new_order.flags.is_trailing_stop = true;

            // Add new order
            try self.stop_orders[shard_index].put(key, new_order);
        }
    }

    pub fn executeTWAPInterval(self: *ShardedOrderbook, order_data: *CacheAlignedOrder) !bool {
        const twap_params = order_data.twap_params.?;
        const current_time = std.time.timestamp();
        const elapsed_intervals = @divFloor(
            @as(u64, @intCast(current_time - twap_params.start_time)),
            twap_params.interval_seconds,
        );

        if (elapsed_intervals <= twap_params.intervals_executed) return false;
        if (elapsed_intervals >= twap_params.num_intervals) return true;

        // Execute the current interval by placing the order
        const shard_index = self.priceToShard(order_data.price);
        const levels = if (order_data.side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];

        // Update price level with the executed amount
        try self.updatePriceLevel(levels, order_data.price, @as(i64, @intCast(twap_params.amount_per_interval)), 1);

        // Execute the matching
        const result = try self.matchOrder(
            order_data.side,
            order_data.price,
            twap_params.amount_per_interval,
        );

        // Update TWAP parameters
        twap_params.intervals_executed = elapsed_intervals;

        // Check if we need to place a new order for remaining amount
        if (result.remaining_amount > 0) {
            const key = OrderKey{ .price = order_data.price, .id = order_data.id };
            var updated_order = order_data.*;
            updated_order.amount = result.remaining_amount;
            try self.shards[shard_index].put(key, updated_order);
        }

        return false;
    }

    // Add fast path for bulk insertions at same price level
    pub fn bulkInsertOrders(self: *ShardedOrderbook, side: OrderSide, price: u64, orders: []const CacheAlignedOrder) !void {
        const VECTOR_WIDTH = if (@import("builtin").cpu.arch == .x86_64) @as(usize, 4) else @as(usize, 2);
        const BATCH_SIZE = VECTOR_WIDTH * 4;
        const PREFETCH_DISTANCE = 8;

        const shard_index = self.priceToShard(price);
        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];

        // Initialize or update price level
        var total_volume: u64 = 0;
        var amount_vec: [VECTOR_WIDTH]u64 align(32) = undefined;

        // Process orders in SIMD batches
        var batch_index: usize = 0;
        while (batch_index + BATCH_SIZE <= orders.len) : (batch_index += BATCH_SIZE) {
            var j: usize = 0;
            while (j < BATCH_SIZE) : (j += VECTOR_WIDTH) {
                // Prefetch next batch
                if (batch_index + j + PREFETCH_DISTANCE < orders.len) {
                    const addr = &orders[batch_index + j + PREFETCH_DISTANCE];
                    switch (@import("builtin").cpu.arch) {
                        .x86_64 => {
                            asm volatile ("prefetcht0 (%[addr])"
                                : // No outputs
                                : [addr] "r" (addr),
                            );
                        },
                        .aarch64 => {
                            asm volatile ("prfm pldl1keep, [%[addr]]"
                                : // No outputs
                                : [addr] "r" (addr),
                            );
                        },
                        else => {},
                    }
                }

                // Load amounts into vector
                for (0..VECTOR_WIDTH) |k| {
                    amount_vec[k] = orders[batch_index + j + k].amount;
                }

                // Sum amounts using SIMD
                const vec: @Vector(VECTOR_WIDTH, u64) = amount_vec;
                total_volume += @reduce(.Add, vec);

                // Bulk insert orders
                for (0..VECTOR_WIDTH) |k| {
                    const order_data = orders[batch_index + j + k];
                    try self.shards[shard_index].put(
                        .{ .price = price, .id = order_data.id },
                        order_data,
                    );
                }
            }
        }

        // Handle remaining orders
        while (batch_index < orders.len) : (batch_index += 1) {
            const order_data = orders[batch_index];
            total_volume += order_data.amount;
            try self.shards[shard_index].put(
                .{ .price = price, .id = order_data.id },
                order_data,
            );
        }

        // Update price level
        try levels.put(price, .{
            .total_volume = total_volume,
            .order_count = orders.len,
        });

        // Update best prices
        if (side == .Buy) {
            if (self.best_bid_cache) |best| {
                self.best_bid_cache = @max(best, price);
            } else {
                self.best_bid_cache = price;
            }
        } else {
            if (self.best_ask_cache) |best| {
                self.best_ask_cache = @min(best, price);
            } else {
                self.best_ask_cache = price;
            }
        }
    }
};

pub const PegType = order_params.PegType;
pub const PegParams = order_params.PegParams;

pub const DiscretionaryParams = struct {
    base_price: u64, // Displayed limit price
    discretionary_price: u64, // Hidden discretionary price
    last_executed_price: ?u64 = null,
};

pub const ConditionalType = enum {
    Price,
    Time,
    Volume,
    Custom,
};

pub const ConditionalParams = struct {
    condition_type: ConditionalType,
    price_threshold: ?u64 = null,
    time_threshold: ?i64 = null,
    volume_threshold: ?u64 = null,
    custom_condition: ?*const fn (order: *const CacheAlignedOrder) bool = null,
    reference_symbol: ?[]const u8 = null,
    is_condition_met: bool = false,
};
