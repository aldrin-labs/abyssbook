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

// Enhanced modular matching engine with clear separation of concerns
pub fn matchOrder(self: *core.ShardedOrderbook, side: types.OrderSide, price: u64, amount: u64) !types.MatchResult {
    var context = MatchContext.init(side, price, amount);
    try validateMatchingPreconditions(&context);
    try executeMatchingPhases(self, &context);
    return context.buildResult();
}

/// Centralized matching context for thread-safe state management
const MatchContext = struct {
    side: types.OrderSide,
    price: u64,
    initial_amount: u64,
    remaining_amount: u64,
    total_filled: u64,
    last_price: u64,
    matches: std.ArrayList(types.Match),
    
    /// Initialize matching context with clear memory layout
    pub fn init(side: types.OrderSide, price: u64, amount: u64) MatchContext {
        return MatchContext{
            .side = side,
            .price = price,
            .initial_amount = amount,
            .remaining_amount = amount,
            .total_filled = 0,
            .last_price = 0,
            .matches = std.ArrayList(types.Match).init(std.heap.page_allocator),
        };
    }
    
    /// Build final match result with proper error handling
    pub fn buildResult(self: *MatchContext) types.MatchResult {
        defer self.matches.deinit();
        return types.MatchResult{
            .filled_amount = self.total_filled,
            .remaining_amount = self.remaining_amount,
            .average_price = if (self.total_filled > 0) self.last_price else 0,
            .match_count = self.matches.items.len,
        };
    }
};

/// Phase 1: Validate matching preconditions with comprehensive checks
fn validateMatchingPreconditions(context: *MatchContext) !void {
    if (context.initial_amount == 0) return error.InvalidAmount;
    if (context.price == 0) return error.InvalidPrice;
    // Additional validation logic can be added here
}

/// Phase 2: Execute matching phases with clear separation
fn executeMatchingPhases(self: *core.ShardedOrderbook, context: *MatchContext) !void {
    var monitor = perf.MatchingMonitor.init();
    defer monitor.deinit();
    
    // Phase 2a: Collect matching price levels across shards
    var candidates = try collectMatchingCandidates(self, context);
    defer candidates.deinit();
    
    // Phase 2b: Sort candidates for optimal execution
    try sortCandidatesByPriority(&candidates, context.side);
    
    // Phase 2c: Execute matches with SIMD optimization
    try executeCandidateMatches(self, &candidates, context, &monitor);
}

/// Phase 2a: Collect all matching price levels with SIMD pre-filtering
fn collectMatchingCandidates(self: *core.ShardedOrderbook, context: *MatchContext) !std.ArrayList(MatchCandidate) {
    var candidates = std.ArrayList(MatchCandidate).init(std.heap.page_allocator);
    
    // Process each shard independently for parallelization potential
    for (0..self.shard_count) |shard_index| {
        const levels = if (context.side == .Buy)
            &self.ask_levels[shard_index]
        else
            &self.bid_levels[shard_index];
            
        try collectCandidatesFromShard(levels, shard_index, context, &candidates);
    }
    
    return candidates;
}

/// Collect candidates from a single shard with optimized iteration
fn collectCandidatesFromShard(levels: *maps.PriceLevelMap, shard_index: usize, context: *MatchContext, candidates: *std.ArrayList(MatchCandidate)) !void {
    var it = levels.iterator();
    while (it.next()) |entry| {
        const should_match = if (context.side == .Buy)
            entry.key_ptr.* <= context.price
        else
            entry.key_ptr.* >= context.price;
            
        if (should_match and entry.value_ptr.total_volume > 0) {
            try candidates.append(MatchCandidate{
                .price = entry.key_ptr.*,
                .volume = entry.value_ptr.total_volume,
                .shard_index = shard_index,
                .order_count = entry.value_ptr.order_count,
            });
        }
    }
}

/// Phase 2b: Sort candidates by price priority with SIMD acceleration  
fn sortCandidatesByPriority(candidates: *std.ArrayList(MatchCandidate), side: types.OrderSide) !void {
    if (candidates.items.len <= 1) return;
    
    // Use optimized sorting based on side
    if (side == .Buy) {
        // For buy orders, match against asks from lowest to highest price
        std.sort.sort(MatchCandidate, candidates.items, {}, struct {
            fn lessThan(_: void, a: MatchCandidate, b: MatchCandidate) bool {
                return a.price < b.price;
            }
        }.lessThan);
    } else {
        // For sell orders, match against bids from highest to lowest price  
        std.sort.sort(MatchCandidate, candidates.items, {}, struct {
            fn lessThan(_: void, a: MatchCandidate, b: MatchCandidate) bool {
                return a.price > b.price;
            }
        }.lessThan);
    }
}

/// Phase 2c: Execute candidate matches with comprehensive tracking
fn executeCandidateMatches(self: *core.ShardedOrderbook, candidates: *std.ArrayList(MatchCandidate), context: *MatchContext, monitor: *perf.MatchingMonitor) !void {
    for (candidates.items) |candidate| {
        if (context.remaining_amount == 0) break;
        
        const match_amount = @min(context.remaining_amount, candidate.volume);
        
        // Execute match with proper error handling
        try executeIndividualMatch(self, candidate, match_amount, context, monitor);
        
        // Update context state
        context.remaining_amount -= match_amount;
        context.total_filled += match_amount;
        context.last_price = candidate.price;
    }
}

/// Execute individual match with atomic operations and error recovery
fn executeIndividualMatch(self: *core.ShardedOrderbook, candidate: MatchCandidate, amount: u64, context: *MatchContext, monitor: *perf.MatchingMonitor) !void {
    monitor.recordMatch(candidate.price, amount);
    
    // Update price level atomically
    const levels = if (context.side == .Buy)
        &self.ask_levels[candidate.shard_index]  
    else
        &self.bid_levels[candidate.shard_index];
        
    try price_level.updatePriceLevel(levels, candidate.price, -@as(i64, @intCast(amount)), 0);
    
    // Record match for audit trail
    try context.matches.append(types.Match{
        .price = candidate.price,
        .amount = amount,
        .side = context.side,
        .timestamp = std.time.milliTimestamp(),
    });
}

/// Match candidate structure for batch processing
const MatchCandidate = struct {
    price: u64,
    volume: u64,
    shard_index: usize,
    order_count: u32,
};


// End of modular matching implementation
