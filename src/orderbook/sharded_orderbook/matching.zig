const std = @import("std");
const types = @import("../types.zig");
const order = @import("../order.zig");
const core = @import("core.zig");
const price_level = @import("price_level.zig");
const maps = @import("../maps.zig");
const builtin = @import("builtin");
const simd_sort = @import("simd_sort.zig");
const perf = @import("perf_monitor.zig");
const perf_viz = @import("perf_viz.zig");

// Enhanced cache and SIMD optimization constants
const CACHE_LINE_SIZE = 64;
const MAX_ORDERS_PER_BATCH = 128; // Increased for better throughput
const PREFETCH_DISTANCE = 8;
const VECTOR_WIDTH = if (builtin.cpu.arch == .x86_64) @as(usize, 8) else @as(usize, 4);

// Price level cache with power-of-two size for fast modulo
const PRICE_LEVEL_CACHE_SIZE = 32;
const PRICE_LEVEL_CACHE_MASK = PRICE_LEVEL_CACHE_SIZE - 1;

// Cache-aligned circular buffer for price levels
const PriceLevelCache = struct {
    levels: [PRICE_LEVEL_CACHE_SIZE]price_level.PriceLevel align(CACHE_LINE_SIZE),
    head: usize align(CACHE_LINE_SIZE),
    tail: usize align(CACHE_LINE_SIZE),

    pub fn init() PriceLevelCache {
        return .{
            .levels = undefined,
            .head = 0,
            .tail = 0,
        };
    }

    pub fn push(self: *PriceLevelCache, level: price_level.PriceLevel) void {
        self.levels[self.tail & PRICE_LEVEL_CACHE_MASK] = level;
        self.tail += 1;
        if (self.tail - self.head > PRICE_LEVEL_CACHE_SIZE) {
            self.head += 1;
        }
    }

    pub fn get(self: *PriceLevelCache, idx: usize) ?*price_level.PriceLevel {
        if (idx >= self.head and idx < self.tail) {
            return &self.levels[idx & PRICE_LEVEL_CACHE_MASK];
        }
        return null;
    }
};

// SIMD-optimized batch matching
const VectorizedMatch = struct {
    prices: [VECTOR_WIDTH]u64 align(32),
    amounts: [VECTOR_WIDTH]u64 align(32),
    results: [VECTOR_WIDTH]CacheAlignedMatchResult align(32),
    count: usize,

    pub fn init() VectorizedMatch {
        return .{
            .prices = [_]u64{0} ** VECTOR_WIDTH,
            .amounts = [_]u64{0} ** VECTOR_WIDTH,
            .results = undefined,
            .count = 0,
        };
    }

    pub fn processBatch(self: *VectorizedMatch) void {
        if (self.count == 0) return;

        const price_vec: @Vector(VECTOR_WIDTH, u64) = self.prices;
        const amount_vec: @Vector(VECTOR_WIDTH, u64) = self.amounts;

        // Vectorized price comparison
        const matches = price_vec >= amount_vec;

        // Process matches in parallel
        for (0..self.count) |i| {
            if (@reduce(.And, matches)) {
                self.results[i].result = .{
                    .matched_amount = self.amounts[i],
                    .remaining_amount = 0,
                };
            } else {
                self.results[i].result = .{
                    .matched_amount = self.prices[i],
                    .remaining_amount = self.amounts[i] - self.prices[i],
                };
            }
        }
    }
};

// Cache-aligned match result with padding
const CacheAlignedMatchResult = struct {
    result: types.MatchResult align(CACHE_LINE_SIZE),
    padding: [CACHE_LINE_SIZE - @sizeOf(types.MatchResult)]u8 = undefined,
};

// SIMD-optimized batch structures
const VectorBatch = struct {
    prices: [VECTOR_WIDTH]u64 align(32),
    amounts: [VECTOR_WIDTH]u64 align(32),
    count: usize,

    pub fn init() VectorBatch {
        return .{
            .prices = [_]u64{0} ** VECTOR_WIDTH,
            .amounts = [_]u64{0} ** VECTOR_WIDTH,
            .count = 0,
        };
    }
};

// Cache-aligned order batch with SIMD-friendly layout
const OrderBatch = struct {
    orders: [MAX_ORDERS_PER_BATCH]order.CacheAlignedOrder align(CACHE_LINE_SIZE),
    vector_batches: [MAX_ORDERS_PER_BATCH / VECTOR_WIDTH + 1]VectorBatch,
    count: usize,

    pub fn init() OrderBatch {
        var self = OrderBatch{
            .orders = undefined,
            .vector_batches = undefined,
            .count = 0,
        };
        for (&self.vector_batches) |*batch| {
            batch.* = VectorBatch.init();
        }
        return self;
    }

    pub fn addOrder(self: *OrderBatch, order_data: order.CacheAlignedOrder, price: u64, amount: u64) void {
        const batch_index = self.count / VECTOR_WIDTH;
        const vector_index = self.count % VECTOR_WIDTH;

        self.orders[self.count] = order_data;
        self.vector_batches[batch_index].prices[vector_index] = price;
        self.vector_batches[batch_index].amounts[vector_index] = amount;

        self.count += 1;
        self.vector_batches[batch_index].count += 1;
    }
};

// Price level entry with cache-friendly layout
const PriceLevelEntry = struct {
    price: u64,
    shard_index: usize,
    volume: u64,
    padding: u64 = 0, // Ensure 32-byte alignment
};

// Cache-aligned price level batch for efficient processing
const PriceLevelBatch = struct {
    prices: [MAX_ORDERS_PER_BATCH]u64 align(32),
    volumes: [MAX_ORDERS_PER_BATCH]u64 align(32),
    shard_indices: [MAX_ORDERS_PER_BATCH]usize align(32),
    count: usize,

    pub fn init() PriceLevelBatch {
        return .{
            .prices = [_]u64{0} ** MAX_ORDERS_PER_BATCH,
            .volumes = [_]u64{0} ** MAX_ORDERS_PER_BATCH,
            .shard_indices = [_]usize{0} ** MAX_ORDERS_PER_BATCH,
            .count = 0,
        };
    }
};

// SIMD helper functions
fn prefetchPriceLevel(ptr: [*]const PriceLevelEntry, offset: usize) void {
    if (builtin.cpu.arch == .x86_64) {
        const addr = @intFromPtr(ptr) + offset * @sizeOf(PriceLevelEntry);
        asm volatile ("prefetcht0 (%[addr])"
            :
            : [addr] "r" (addr),
            : "memory"
        );
    }
}

fn vectorizedVolumeSum(volumes: []align(32) const u64) u64 {
    if (volumes.len < VECTOR_WIDTH) {
        var sum: u64 = 0;
        for (volumes) |v| sum += v;
        return sum;
    }

    const VolumeVector = @Vector(VECTOR_WIDTH, u64);
    var sum: u64 = 0;
    var i: usize = 0;

    // Process vectors
    while (i + VECTOR_WIDTH <= volumes.len) : (i += VECTOR_WIDTH) {
        const vec: VolumeVector = volumes[i..][0..VECTOR_WIDTH].*;
        sum += @reduce(.Add, vec);
    }

    // Handle remaining elements
    while (i < volumes.len) : (i += 1) {
        sum += volumes[i];
    }

    return sum;
}

fn vectorizedPriceMatch(prices: []align(32) const u64, target_price: u64) bool {
    if (prices.len < VECTOR_WIDTH) {
        for (prices) |p| {
            if (p == target_price) return true;
        }
        return false;
    }

    const PriceVector = @Vector(VECTOR_WIDTH, u64);
    var i: usize = 0;

    // Process vectors
    while (i + VECTOR_WIDTH <= prices.len) : (i += VECTOR_WIDTH) {
        const vec: PriceVector = prices[i..][0..VECTOR_WIDTH].*;
        const target_vec: PriceVector = @splat(target_price);
        const mask = vec == target_vec;
        if (@reduce(.Or, mask)) return true;
    }

    // Handle remaining elements
    while (i < prices.len) : (i += 1) {
        if (prices[i] == target_price) return true;
    }

    return false;
}

fn processBatchVectorized(
    self: *core.ShardedOrderbook,
    batch: *OrderBatch,
    levels: *maps.PriceLevelMap,
    price: u64,
    matched_amount: u64,
    monitor: *perf.PerformanceMonitor,
) !void {
    // Process each vector batch with performance tracking
    for (batch.vector_batches[0 .. batch.count / VECTOR_WIDTH + 1]) |*vector_batch| {
        if (vector_batch.count == 0) continue;

        monitor.simd_metrics.vector_operations += 1;

        // Process matched orders
        var i: usize = 0;
        while (i < vector_batch.count) : (i += 1) {
            // Check if the current amount is less than or equal to matched_amount
            const amount = vector_batch.amounts[i];
            if (amount <= matched_amount) {
                const order_index = ((@intFromPtr(vector_batch) - @intFromPtr(&batch.vector_batches)) / @sizeOf(VectorBatch)) * VECTOR_WIDTH + i;
                try processFilledOrder(self, &batch.orders[order_index], levels, price);
            } else {
                monitor.simd_metrics.scalar_operations += 1;
            }
        }
    }
}

pub fn matchMarketOrder(self: *core.ShardedOrderbook, side: types.OrderSide, amount: u64) !types.MatchResult {
    return matchOrder(self, side, if (side == .Buy) std.math.maxInt(u64) else 0, amount);
}

pub fn matchOrder(self: *core.ShardedOrderbook, side: types.OrderSide, price: u64, amount: u64) !types.MatchResult {
    return matchOrderOptimized(self, side, price, amount);
}

// Optimized matching core with enhanced SIMD support
fn matchOrderOptimized(self: *core.ShardedOrderbook, side: types.OrderSide, price: u64, amount: u64) !types.MatchResult {
    var monitor = perf.MatchingMonitor.init();
    defer monitor.deinit();

    var remaining_amount: u64 = amount;
    var total_filled: u64 = 0;
    var last_price: u64 = 0;

    // Initialize SIMD-optimized batch processing
    var level_batch = PriceLevelBatch.init();
    var price_cache: [PRICE_LEVEL_CACHE_SIZE]u64 align(CACHE_LINE_SIZE) = undefined;
    var cache_size: usize = 0;

    // Process each shard with SIMD operations
    for (0..self.shard_count) |shard_index| {
        const levels = if (side == .Buy)
            &self.ask_levels[shard_index]
        else
            &self.bid_levels[shard_index];

        var it = levels.iterator();
        while (it.next()) |entry| {
            const should_match = if (side == .Buy)
                entry.key_ptr.* <= price
            else
                entry.key_ptr.* >= price;

            if (!should_match) continue;

            // Prefetch next entries
            if (cache_size < PRICE_LEVEL_CACHE_SIZE) {
                @prefetch(entry.value_ptr, .{ .locality = 3, .cache_type = .data });
                price_cache[cache_size] = entry.key_ptr.*;
                cache_size += 1;
            }

            // Add to SIMD batch
            if (level_batch.count < MAX_ORDERS_PER_BATCH) {
                level_batch.prices[level_batch.count] = entry.key_ptr.*;
                level_batch.volumes[level_batch.count] = entry.value_ptr.total_volume;
                level_batch.shard_indices[level_batch.count] = shard_index;
                level_batch.count += 1;

                // Process batch when full
                if (level_batch.count == MAX_ORDERS_PER_BATCH) {
                    try processLevelBatchSIMD(self, &level_batch, &remaining_amount, &total_filled, &last_price, side, &monitor);
                    level_batch.count = 0;
                }
            }
        }
    }

    // Process remaining levels
    if (level_batch.count > 0) {
        try processLevelBatchSIMD(self, &level_batch, &remaining_amount, &total_filled, &last_price, side, &monitor);
    }

    return types.MatchResult{
        .filled_amount = total_filled,
        .remaining_amount = remaining_amount,
        .last_price = if (total_filled > 0) last_price else 0,
    };
}

// SIMD-optimized price level batch processing
fn processLevelBatchSIMD(
    self: *core.ShardedOrderbook,
    batch: *PriceLevelBatch,
    remaining_amount: *u64,
    total_filled: *u64,
    last_price: *u64,
    side: types.OrderSide,
    monitor: *perf.MatchingMonitor,
) !void {
    const vector_size = VECTOR_WIDTH;
    var i: usize = 0;

    // Process in SIMD vectors
    while (i + vector_size <= batch.count) : (i += vector_size) {
        var matched_amounts: [vector_size]u64 align(32) = undefined;

        // SIMD comparison and volume calculation
        inline for (0..vector_size) |j| {
            const should_match = if (side == .Buy)
                batch.prices[i + j] <= remaining_amount.*
            else
                batch.prices[i + j] >= remaining_amount.*;

            matched_amounts[j] = if (should_match)
                @min(remaining_amount.*, batch.volumes[i + j])
            else
                0;
        }

        // Update volumes and counts
        inline for (0..vector_size) |j| {
            if (matched_amounts[j] > 0) {
                const shard_index = batch.shard_indices[i + j];
                const levels = if (side == .Buy)
                    &self.ask_levels[shard_index]
                else
                    &self.bid_levels[shard_index];

                try price_level.updatePriceLevel(levels, batch.prices[i + j], -@as(i64, @intCast(matched_amounts[j])), 0);
                remaining_amount.* -= matched_amounts[j];
                total_filled.* += matched_amounts[j];
                last_price.* = batch.prices[i + j];
            }
        }
        monitor.simd_metrics.vector_operations += 1;
    }

    // Handle remaining entries
    while (i < batch.count) : (i += 1) {
        const should_match = if (side == .Buy)
            batch.prices[i] <= remaining_amount.*
        else
            batch.prices[i] >= remaining_amount.*;

        if (should_match) {
            const matched_amount = @min(remaining_amount.*, batch.volumes[i]);
            if (matched_amount > 0) {
                const shard_index = batch.shard_indices[i];
                const levels = if (side == .Buy)
                    &self.ask_levels[shard_index]
                else
                    &self.bid_levels[shard_index];

                try price_level.updatePriceLevel(levels, batch.prices[i], -@as(i64, @intCast(matched_amount)), 0);
                remaining_amount.* -= matched_amount;
                total_filled.* += matched_amount;
                last_price.* = batch.prices[i];
            }
        }
        monitor.simd_metrics.scalar_operations += 1;
    }
}

fn processFilledOrder(
    self: *core.ShardedOrderbook,
    order_data: *order.CacheAlignedOrder,
    levels: *maps.PriceLevelMap,
    price: u64,
) types.OrderError!void {
    try price_level.updatePriceLevel(levels, price, 0, -1);
    _ = self.shards[self.priceToShard(price)].swapRemove(.{ .price = price, .id = order_data.id });

    if (order_data.flags.is_oso and !order_data.oso_params.?.is_child_placed) {
        order_data.oso_params.?.is_child_placed = true;
        self.placeOrder(order_data.oso_params.?.child_order) catch |err| {
            order_data.oso_params.?.is_child_placed = false;
            return err;
        };
    }

    if (order_data.flags.is_oco and !order_data.oco_params.?.is_cancelled) {
        order_data.oco_params.?.is_cancelled = true;
        self.cancelOrder(order_data.oco_params.?.linked_order.id) catch |err| {
            order_data.oco_params.?.is_cancelled = false;
            return err;
        };
    }
}

pub fn matchDiscretionaryOrder(self: *core.ShardedOrderbook, order_data: *const order.CacheAlignedOrder) !types.MatchResult {
    const discretionary_params = order_data.discretionary_params.?;

    // Try to match at base price first
    const result = try matchOrder(self, order_data.side, order_data.price, order_data.amount);
    if (result.remaining_amount == 0) return result;

    // If base price didn't fully match, try discretionary price
    const discretionary_result = try matchOrder(
        self,
        order_data.side,
        discretionary_params.discretionary_price,
        result.remaining_amount,
    );

    return .{
        .filled_amount = result.filled_amount + discretionary_result.filled_amount,
        .remaining_amount = discretionary_result.remaining_amount,
        .execution_price = discretionary_result.execution_price,
    };
}

pub fn matchPegOrder(self: *core.ShardedOrderbook, order_data: *const order.CacheAlignedOrder) !types.MatchResult {
    const peg_params = order_data.peg_params.?;

    // Calculate current peg price
    const base_price = switch (peg_params.peg_type) {
        .BestBid => self.getBestBid() orelse return error.NoBestBid,
        .BestAsk => self.getBestAsk() orelse return error.NoBestAsk,
        .Midpoint => blk: {
            const bid = self.getBestBid() orelse return error.NoBestBid;
            const ask = self.getBestAsk() orelse return error.NoBestAsk;
            break :blk (bid + ask) / 2;
        },
        .LastTrade => return error.LastTradeNotImplemented,
    };

    // Apply offset
    const adjusted_price = if (peg_params.offset >= 0)
        base_price + @as(u64, @intCast(peg_params.offset))
    else if (@as(u64, @intCast(-peg_params.offset)) > base_price)
        0
    else
        base_price - @as(u64, @intCast(-peg_params.offset));

    // Check limit price if specified
    const final_price = if (peg_params.limit_price) |limit|
        if (order_data.side == .Buy)
            @min(adjusted_price, limit)
        else
            @max(adjusted_price, limit)
    else
        adjusted_price;

    return matchOrder(self, order_data.side, final_price, order_data.amount);
}

pub fn executeTWAPInterval(self: *core.ShardedOrderbook, order_data: *order.CacheAlignedOrder) !bool {
    const twap_params = order_data.twap_params.?;
    const current_time = std.time.timestamp();
    const elapsed_intervals = @divFloor(
        @as(u64, @intCast(current_time - twap_params.start_time)),
        twap_params.interval_seconds,
    );

    if (elapsed_intervals <= twap_params.intervals_executed) return false;
    if (elapsed_intervals >= twap_params.num_intervals) return true;

    // Execute the current interval
    const result = try matchOrder(
        self,
        order_data.side,
        order_data.price,
        twap_params.amount_per_interval,
    );

    // Update TWAP parameters
    twap_params.intervals_executed = elapsed_intervals;

    // Check if we need to place a new order for remaining amount
    if (result.remaining_amount > 0) {
        var new_order = order_data.*;
        new_order.amount = result.remaining_amount;
        try self.placeOrder(new_order);
    }

    return false;
}

pub fn executeConditionalOrder(self: *core.ShardedOrderbook, order_data: *const order.CacheAlignedOrder) !types.MatchResult {
    const cond_params = order_data.conditional_params.?;

    // Check if conditions are met
    const condition_met = switch (cond_params.condition_type) {
        .PriceAbove => if (order_data.side == .Buy)
            self.getBestAsk() orelse std.math.maxInt(u64) <= cond_params.target_value
        else
            self.getBestBid() orelse 0 >= cond_params.target_value,
        .PriceBelow => if (order_data.side == .Buy)
            self.getBestAsk() orelse std.math.maxInt(u64) >= cond_params.target_value
        else
            self.getBestBid() orelse 0 <= cond_params.target_value,
        .SpreadWidth => if (self.getBestAsk()) |ask| {
            if (self.getBestBid()) |bid| {
                ask - bid <= cond_params.target_value;
            } else false;
        } else false,
        .VolumeThreshold => false, // Not implemented yet
    };

    if (!condition_met) {
        return types.MatchResult{
            .filled_amount = 0,
            .remaining_amount = order_data.amount,
            .execution_price = order_data.price,
        };
    }

    return matchOrder(self, order_data.side, order_data.price, order_data.amount);
}

pub fn executeTrailingStopOrder(self: *core.ShardedOrderbook, order_data: *order.CacheAlignedOrder) !void {
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
        const key = types.OrderKey{ .price = order_data.price, .id = order_data.id };
        _ = self.stop_orders[shard_index].remove(key);

        // Create new order with updated stop price
        var new_order = order.CacheAlignedOrder.init(
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

pub fn executeIcebergOrder(self: *core.ShardedOrderbook, order_data: *const order.CacheAlignedOrder) !types.MatchResult {
    const display_amount = order_data.display_amount orelse order_data.amount;
    const result = try matchOrder(self, order_data.side, order_data.price, display_amount);

    // If the visible portion is fully filled and there's still hidden amount
    if (result.remaining_amount == 0 and result.filled_amount < order_data.amount) {
        var new_order = order_data.*;
        new_order.amount = order_data.amount - result.filled_amount;
        new_order.display_amount = @min(display_amount, new_order.amount);
        try self.placeOrder(new_order);
    }

    return result;
}
