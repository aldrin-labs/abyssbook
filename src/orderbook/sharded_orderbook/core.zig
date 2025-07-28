const std = @import("std");
const orderbook = @import("../orderbook.zig");
const order = @import("../order.zig");
const maps = @import("../maps.zig");
const types = @import("../types.zig");
const matching = @import("matching.zig");
const basic_orders = @import("basic_orders.zig");
const advanced_orders = @import("advanced_orders.zig");
const price_level = @import("price_level.zig");

pub const ShardedOrderbook = struct {
    shards: []maps.OrderMap,
    bid_levels: []maps.PriceLevelMap,
    ask_levels: []maps.PriceLevelMap,
    stop_orders: []maps.StopOrderMap,
    // Global order ID index for fast duplicate detection
    global_order_index: std.HashMap(u64, ShardLocationInfo, std.hash_map.DefaultHashContext, std.hash_map.default_max_load_percentage),
    shard_count: usize,
    allocator: std.mem.Allocator,
    current_order: ?*const order.CacheAlignedOrder = null,
    current_order_flags: types.OrderFlags = .{},
    best_bid_cache: ?u64 = null,
    best_ask_cache: ?u64 = null,

    const ShardLocationInfo = struct {
        shard_index: usize,
        price: u64,
        side: types.OrderSide,
    };

    pub fn init(allocator: std.mem.Allocator, shard_count: usize) !ShardedOrderbook {
        const shards = try allocator.alloc(maps.OrderMap, shard_count);
        const bid_levels = try allocator.alloc(maps.PriceLevelMap, shard_count);
        const ask_levels = try allocator.alloc(maps.PriceLevelMap, shard_count);
        const stop_orders = try allocator.alloc(maps.StopOrderMap, shard_count);

        for (0..shard_count) |i| {
            shards[i] = maps.OrderMap.init(allocator);
            bid_levels[i] = try maps.PriceLevelMap.init(allocator);
            ask_levels[i] = try maps.PriceLevelMap.init(allocator);
            stop_orders[i] = maps.StopOrderMap.init(allocator);
        }

        return ShardedOrderbook{
            .shards = shards,
            .bid_levels = bid_levels,
            .ask_levels = ask_levels,
            .stop_orders = stop_orders,
            .global_order_index = std.HashMap(u64, ShardLocationInfo, std.hash_map.DefaultHashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .shard_count = shard_count,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ShardedOrderbook) void {
        for (0..self.shard_count) |i| {
            self.shards[i].deinit();
            self.bid_levels[i].deinit();
            self.ask_levels[i].deinit();
            self.stop_orders[i].deinit();
        }
        self.global_order_index.deinit();
        self.allocator.free(self.shards);
        self.allocator.free(self.bid_levels);
        self.allocator.free(self.ask_levels);
        self.allocator.free(self.stop_orders);
    }

    pub fn priceToShard(self: *const ShardedOrderbook, price: u64) usize {
        return @intCast(price % self.shard_count);
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

    pub fn getVolume(self: *const ShardedOrderbook, side: types.OrderSide, price: u64) types.OrderError!u64 {
        const shard_index = self.priceToShard(price);
        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];

        if (levels.get(price)) |level| {
            return level.total_volume;
        }
        return 0;
    }

    pub fn getVolumeAtLevel(self: *const ShardedOrderbook, price: u64, side: types.OrderSide) u64 {
        const shard_index = self.priceToShard(price);
        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];
        return if (levels.get(price)) |level| level.total_volume else 0;
    }

    pub fn getOrderCountAtLevel(self: *const ShardedOrderbook, price: u64, side: types.OrderSide) usize {
        const shard_index = self.priceToShard(price);
        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];
        return if (levels.get(price)) |level| level.order_count else 0;
    }

    pub fn placeOrder(self: *ShardedOrderbook, order_data: order.CacheAlignedOrder) !void {
        return basic_orders.placeOrderWithType(self, order_data);
    }

    pub fn cancelOrder(self: *ShardedOrderbook, order_id: u64) !void {
        return basic_orders.cancelOrder(self, order_id);
    }

    pub fn matchMarketOrder(self: *ShardedOrderbook, side: types.OrderSide, amount: u64) !types.MatchResult {
        return matching.matchMarketOrder(self, side, amount);
    }

    pub fn placePegOrder(self: *ShardedOrderbook, order_data: order.CacheAlignedOrder) !void {
        return advanced_orders.placePegOrder(self, order_data);
    }

    pub fn getRandomOrder(self: *const ShardedOrderbook) ?u64 {
        var total_orders: usize = 0;
        for (self.shards) |shard| {
            total_orders += shard.count();
        }
        if (total_orders == 0) return null;

        const random_index = std.crypto.random.intRangeAtMost(usize, 0, total_orders - 1);
        var current_index: usize = 0;

        for (self.shards) |shard| {
            var it = shard.iterator();
            while (it.next()) |entry| {
                if (current_index == random_index) {
                    return entry.key_ptr.id;
                }
                current_index += 1;
            }
        }
        return null;
    }

    pub fn generatePerformanceReport(self: *const ShardedOrderbook, output_path: []const u8) !void {
        const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
            std.debug.print("Error creating performance report file: {}\n", .{err});
            return err;
        };
        defer file.close();
        
        const writer = file.writer();
        
        // Write performance report header
        try writer.print("# Abyssbook Sharded Orderbook Performance Report\n\n");
        try writer.print("## Configuration\n");
        try writer.print("- Shard Count: {}\n", .{self.shard_count});
        try writer.print("- Total Global Orders: {}\n", .{self.global_order_index.count()});
        
        // Analyze per-shard metrics
        try writer.print("\n## Shard Distribution\n");
        for (0..self.shard_count) |i| {
            const order_count = self.shards[i].count();
            const bid_levels = self.bid_levels[i].count();
            const ask_levels = self.ask_levels[i].count();
            const stop_orders = self.stop_orders[i].count();
            
            try writer.print("### Shard {}\n", .{i});
            try writer.print("- Orders: {}\n", .{order_count});
            try writer.print("- Bid Levels: {}\n", .{bid_levels});
            try writer.print("- Ask Levels: {}\n", .{ask_levels});
            try writer.print("- Stop Orders: {}\n", .{stop_orders});
        }
        
        // Memory utilization analysis
        try writer.print("\n## Memory Utilization\n");
        const estimated_memory = self.shard_count * (
            @sizeOf(maps.OrderMap) + 
            @sizeOf(maps.PriceLevelMap) * 2 + 
            @sizeOf(maps.StopOrderMap)
        );
        try writer.print("- Estimated Memory Usage: {} bytes\n", .{estimated_memory});
        
        // Cache effectiveness
        try writer.print("\n## Cache Status\n");
        try writer.print("- Best Bid Cached: {}\n", .{self.best_bid_cache != null});
        try writer.print("- Best Ask Cached: {}\n", .{self.best_ask_cache != null});
        
        try writer.print("\n## Report Generated: {}\n", .{std.time.timestamp()});
        
        std.debug.print("Performance report written to: {s}\n", .{output_path});
    }

    pub fn matchOrder(self: *ShardedOrderbook, side: types.OrderSide, price: u64, amount: u64) !types.MatchResult {
        return matching.matchOrder(self, side, price, amount);
    }

    pub fn checkStopOrders(self: *ShardedOrderbook, price: u64) types.OrderError!void {
        return basic_orders.checkStopOrders(self, price);
    }

    pub fn bulkInsertOrders(self: *ShardedOrderbook, side: types.OrderSide, price: u64, orders: []const order.CacheAlignedOrder) !void {
        const shard_index = self.priceToShard(price);
        const levels = if (side == .Buy) &self.bid_levels[shard_index] else &self.ask_levels[shard_index];

        // Pre-allocate space in price level with padding for SIMD operations
        var level = try levels.getOrPut(price);
        if (!level.found_existing) {
            level.value_ptr.* = price_level.PriceLevel.init();
        }
        try level.value_ptr.ensureTotalCapacity(orders.len);

        // Process orders in SIMD-friendly batches
        const BATCH_SIZE = 8; // Size of SIMD vector
        var batch_start: usize = 0;

        // Prefetch next batch of orders
        while (batch_start + BATCH_SIZE <= orders.len) : (batch_start += BATCH_SIZE) {
            // Prefetch next batch
            if (batch_start + 2 * BATCH_SIZE <= orders.len) {
                for (orders[batch_start + BATCH_SIZE .. batch_start + BATCH_SIZE + 4]) |order_data| {
                    @prefetch(&order_data, .{ .locality = 3, .cache_type = .data });
                }
            }

            // Process current batch
            var total_volume: u64 = 0;
            inline for (0..BATCH_SIZE) |i| {
                const order_data = orders[batch_start + i];
                try self.shards[shard_index].put(.{ .price = price, .id = order_data.id }, order_data);
                total_volume += order_data.amount;
            }
            level.value_ptr.total_volume += total_volume;
            level.value_ptr.order_count += BATCH_SIZE;
        }

        // Handle remaining orders
        for (orders[batch_start..]) |order_data| {
            try self.shards[shard_index].put(.{ .price = price, .id = order_data.id }, order_data);
            level.value_ptr.total_volume += order_data.amount;
            level.value_ptr.order_count += 1;
        }

        // Update best prices with atomic operations
        if (side == .Buy) {
            if (self.best_bid) |best| {
                self.best_bid = @max(best, price);
            } else {
                self.best_bid = price;
            }
        } else {
            if (self.best_ask) |best| {
                self.best_ask = @min(best, price);
            } else {
                self.best_ask = price;
            }
        }
    }

    /// Fast duplicate order ID check using global index
    pub fn isDuplicateOrderId(self: *const ShardedOrderbook, order_id: u64) bool {
        return self.global_order_index.contains(order_id);
    }

    /// Register order ID in global index for duplicate prevention
    pub fn registerOrderId(self: *ShardedOrderbook, order_id: u64, shard_index: usize, price: u64, side: types.OrderSide) !void {
        try self.global_order_index.put(order_id, ShardLocationInfo{
            .shard_index = shard_index,
            .price = price,
            .side = side,
        });
    }

    /// Remove order ID from global index when order is removed
    pub fn unregisterOrderId(self: *ShardedOrderbook, order_id: u64) void {
        _ = self.global_order_index.remove(order_id);
    }

    /// Get order location information from global index
    pub fn getOrderLocation(self: *const ShardedOrderbook, order_id: u64) ?ShardLocationInfo {
        return self.global_order_index.get(order_id);
    }
};
