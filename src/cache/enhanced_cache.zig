const std = @import("std");

/// Enhanced multi-level cache with LRU eviction and performance monitoring
pub fn MultiLevelCache(comptime Key: type, comptime Value: type) type {
    return struct {
        const Self = @This();
        
        pub const CacheEntry = struct {
            key: Key,
            value: Value,
            timestamp: i64,
            access_count: usize,
            last_access: i64,
            is_hot: bool,
        };
        
        pub const CacheLevel = struct {
            entries: std.HashMap(Key, CacheEntry, std.hash_map.DefaultContext(Key), std.hash_map.default_max_load_percentage),
            max_size: usize,
            ttl_ms: u64,
            hit_count: usize,
            miss_count: usize,
            eviction_count: usize,
            
            pub fn init(allocator: std.mem.Allocator, max_size: usize, ttl_ms: u64) CacheLevel {
                return .{
                    .entries = std.HashMap(Key, CacheEntry, std.hash_map.DefaultContext(Key), std.hash_map.default_max_load_percentage).init(allocator),
                    .max_size = max_size,
                    .ttl_ms = ttl_ms,
                    .hit_count = 0,
                    .miss_count = 0,
                    .eviction_count = 0,
                };
            }
            
            pub fn deinit(self: *CacheLevel) void {
                self.entries.deinit();
            }
            
            pub fn get(self: *CacheLevel, key: Key) ?Value {
                const current_time = std.time.milliTimestamp();
                
                if (self.entries.getPtr(key)) |entry| {
                    // Check if entry is expired
                    const age_ms = @as(u64, @intCast(current_time - entry.timestamp));
                    if (age_ms <= self.ttl_ms) {
                        // Update access statistics
                        entry.last_access = current_time;
                        entry.access_count += 1;
                        entry.is_hot = entry.access_count > 10; // Mark as hot if accessed > 10 times
                        
                        self.hit_count += 1;
                        return entry.value;
                    } else {
                        // Entry expired, remove it
                        _ = self.entries.remove(key);
                        self.eviction_count += 1;
                    }
                }
                
                self.miss_count += 1;
                return null;
            }
            
            pub fn put(self: *CacheLevel, key: Key, value: Value) !void {
                const current_time = std.time.milliTimestamp();
                
                // Check if we need to evict entries
                if (self.entries.count() >= self.max_size) {
                    try self.evictLRU();
                }
                
                const entry = CacheEntry{
                    .key = key,
                    .value = value,
                    .timestamp = current_time,
                    .access_count = 1,
                    .last_access = current_time,
                    .is_hot = false,
                };
                
                try self.entries.put(key, entry);
            }
            
            fn evictLRU(self: *CacheLevel) !void {
                if (self.entries.count() == 0) return;
                
                var oldest_key: ?Key = null;
                var oldest_time: i64 = std.math.maxInt(i64);
                
                var it = self.entries.iterator();
                while (it.next()) |entry| {
                    // Prefer evicting non-hot entries first
                    if (!entry.value_ptr.is_hot and entry.value_ptr.last_access < oldest_time) {
                        oldest_time = entry.value_ptr.last_access;
                        oldest_key = entry.key_ptr.*;
                    }
                }
                
                // If no non-hot entries, evict the oldest hot entry
                if (oldest_key == null) {
                    it = self.entries.iterator();
                    while (it.next()) |entry| {
                        if (entry.value_ptr.last_access < oldest_time) {
                            oldest_time = entry.value_ptr.last_access;
                            oldest_key = entry.key_ptr.*;
                        }
                    }
                }
                
                if (oldest_key) |key| {
                    _ = self.entries.remove(key);
                    self.eviction_count += 1;
                }
            }
            
            pub fn getHitRatio(self: *const CacheLevel) f64 {
                const total = self.hit_count + self.miss_count;
                return if (total > 0) @as(f64, @floatFromInt(self.hit_count)) / @as(f64, @floatFromInt(total)) * 100.0 else 0.0;
            }
            
            pub fn clear(self: *CacheLevel) void {
                self.entries.clearRetainingCapacity();
                self.hit_count = 0;
                self.miss_count = 0;
                self.eviction_count = 0;
            }
        };
        
        allocator: std.mem.Allocator,
        l1_cache: CacheLevel, // Hot data - small, fast
        l2_cache: CacheLevel, // Warm data - medium size
        l3_cache: CacheLevel, // Cold data - large, slower
        
        // Performance monitoring
        total_gets: usize,
        total_puts: usize,
        l1_promotions: usize,
        l2_promotions: usize,
        l3_demotions: usize,
        
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .l1_cache = CacheLevel.init(allocator, 1000, 5_000),    // 1K entries, 5s TTL
                .l2_cache = CacheLevel.init(allocator, 10_000, 30_000), // 10K entries, 30s TTL  
                .l3_cache = CacheLevel.init(allocator, 100_000, 300_000), // 100K entries, 5min TTL
                .total_gets = 0,
                .total_puts = 0,
                .l1_promotions = 0,
                .l2_promotions = 0,
                .l3_demotions = 0,
            };
        }
        
        pub fn deinit(self: *Self) void {
            self.l1_cache.deinit();
            self.l2_cache.deinit();
            self.l3_cache.deinit();
        }
        
        pub fn get(self: *Self, key: Key) ?Value {
            self.total_gets += 1;
            
            // Try L1 cache first (hottest data)
            if (self.l1_cache.get(key)) |value| {
                return value;
            }
            
            // Try L2 cache
            if (self.l2_cache.get(key)) |value| {
                // Promote to L1 if accessed frequently
                if (self.l2_cache.entries.get(key)) |entry| {
                    if (entry.is_hot) {
                        self.l1_cache.put(key, value) catch {};
                        self.l1_promotions += 1;
                    }
                }
                return value;
            }
            
            // Try L3 cache
            if (self.l3_cache.get(key)) |value| {
                // Promote to L2 if accessed frequently
                if (self.l3_cache.entries.get(key)) |entry| {
                    if (entry.access_count > 3) {
                        self.l2_cache.put(key, value) catch {};
                        self.l2_promotions += 1;
                    }
                }
                return value;
            }
            
            return null;
        }
        
        pub fn put(self: *Self, key: Key, value: Value) !void {
            self.total_puts += 1;
            
            // Always put new entries in L3 first
            // They'll be promoted based on access patterns
            try self.l3_cache.put(key, value);
        }
        
        pub fn remove(self: *Self, key: Key) void {
            _ = self.l1_cache.entries.remove(key);
            _ = self.l2_cache.entries.remove(key);
            _ = self.l3_cache.entries.remove(key);
        }
        
        pub fn clear(self: *Self) void {
            self.l1_cache.clear();
            self.l2_cache.clear();
            self.l3_cache.clear();
            self.total_gets = 0;
            self.total_puts = 0;
            self.l1_promotions = 0;
            self.l2_promotions = 0;
            self.l3_demotions = 0;
        }
        
        pub fn getOverallHitRatio(self: *const Self) f64 {
            const l1_hits = self.l1_cache.hit_count;
            const l2_hits = self.l2_cache.hit_count;
            const l3_hits = self.l3_cache.hit_count;
            const total_hits = l1_hits + l2_hits + l3_hits;
            
            return if (self.total_gets > 0) @as(f64, @floatFromInt(total_hits)) / @as(f64, @floatFromInt(self.total_gets)) * 100.0 else 0.0;
        }
        
        pub fn printStatistics(self: *const Self) void {
            std.debug.print("\n=== Multi-Level Cache Statistics ===\n");
            std.debug.print("Total Gets: {d}\n", .{self.total_gets});
            std.debug.print("Total Puts: {d}\n", .{self.total_puts});
            std.debug.print("Overall Hit Ratio: {d:.1}%\n", .{self.getOverallHitRatio()});
            std.debug.print("\nL1 Cache (Hot):\n");
            std.debug.print("  Entries: {d}/{d}\n", .{ self.l1_cache.entries.count(), self.l1_cache.max_size });
            std.debug.print("  Hit Ratio: {d:.1}%\n", .{self.l1_cache.getHitRatio()});
            std.debug.print("  Hits: {d}, Misses: {d}\n", .{ self.l1_cache.hit_count, self.l1_cache.miss_count });
            std.debug.print("  Evictions: {d}\n", .{self.l1_cache.eviction_count});
            
            std.debug.print("\nL2 Cache (Warm):\n");
            std.debug.print("  Entries: {d}/{d}\n", .{ self.l2_cache.entries.count(), self.l2_cache.max_size });
            std.debug.print("  Hit Ratio: {d:.1}%\n", .{self.l2_cache.getHitRatio()});
            std.debug.print("  Hits: {d}, Misses: {d}\n", .{ self.l2_cache.hit_count, self.l2_cache.miss_count });
            std.debug.print("  Evictions: {d}\n", .{self.l2_cache.eviction_count});
            
            std.debug.print("\nL3 Cache (Cold):\n");
            std.debug.print("  Entries: {d}/{d}\n", .{ self.l3_cache.entries.count(), self.l3_cache.max_size });
            std.debug.print("  Hit Ratio: {d:.1}%\n", .{self.l3_cache.getHitRatio()});
            std.debug.print("  Hits: {d}, Misses: {d}\n", .{ self.l3_cache.hit_count, self.l3_cache.miss_count });
            std.debug.print("  Evictions: {d}\n", .{self.l3_cache.eviction_count});
            
            std.debug.print("\nPromotion Statistics:\n");
            std.debug.print("  L1 Promotions: {d}\n", .{self.l1_promotions});
            std.debug.print("  L2 Promotions: {d}\n", .{self.l2_promotions});
            std.debug.print("  L3 Demotions: {d}\n", .{self.l3_demotions});
            std.debug.print("\n");
        }
        
        // Preload hot data based on historical access patterns
        pub fn warmCache(self: *Self, hot_keys: []const Key, warm_keys: []const Key) !void {
            // This would typically load from a persistence layer or analytics
            // For now, it's a placeholder for intelligent cache warming
            _ = self;
            _ = hot_keys;
            _ = warm_keys;
            std.debug.print("Cache warming not implemented yet\n");
        }
        
        // Adaptive cache sizing based on hit ratios
        pub fn optimizeSizes(self: *Self) void {
            const l1_hit_ratio = self.l1_cache.getHitRatio();
            const l2_hit_ratio = self.l2_cache.getHitRatio();
            const l3_hit_ratio = self.l3_cache.getHitRatio();
            
            // If L1 hit ratio is low, consider reducing its size
            if (l1_hit_ratio < 70.0 and self.l1_cache.max_size > 500) {
                self.l1_cache.max_size = @max(500, self.l1_cache.max_size - 100);
            }
            // If L1 hit ratio is very high, consider increasing its size
            else if (l1_hit_ratio > 95.0 and self.l1_cache.max_size < 2000) {
                self.l1_cache.max_size = @min(2000, self.l1_cache.max_size + 100);
            }
            
            // Similar logic for L2 and L3
            if (l2_hit_ratio < 60.0 and self.l2_cache.max_size > 5000) {
                self.l2_cache.max_size = @max(5000, self.l2_cache.max_size - 1000);
            } else if (l2_hit_ratio > 90.0 and self.l2_cache.max_size < 20000) {
                self.l2_cache.max_size = @min(20000, self.l2_cache.max_size + 1000);
            }
            
            if (l3_hit_ratio < 50.0 and self.l3_cache.max_size > 50000) {
                self.l3_cache.max_size = @max(50000, self.l3_cache.max_size - 10000);
            } else if (l3_hit_ratio > 80.0 and self.l3_cache.max_size < 200000) {
                self.l3_cache.max_size = @min(200000, self.l3_cache.max_size + 10000);
            }
        }
    };
}

// Specialized orderbook cache with price level awareness
pub const OrderbookLevelCache = struct {
    price_level_cache: MultiLevelCache(u64, PriceLevelCacheEntry),
    best_bid_cache: ?u64,
    best_ask_cache: ?u64,
    last_update: i64,
    
    const PriceLevelCacheEntry = struct {
        total_volume: u64,
        order_count: usize,
        orders: []const OrderCacheEntry,
    };
    
    const OrderCacheEntry = struct {
        id: u64,
        amount: u64,
        timestamp: i64,
    };
    
    pub fn init(allocator: std.mem.Allocator) OrderbookLevelCache {
        return .{
            .price_level_cache = MultiLevelCache(u64, PriceLevelCacheEntry).init(allocator),
            .best_bid_cache = null,
            .best_ask_cache = null,
            .last_update = 0,
        };
    }
    
    pub fn deinit(self: *OrderbookLevelCache) void {
        self.price_level_cache.deinit();
    }
    
    pub fn updateBestPrices(self: *OrderbookLevelCache, best_bid: ?u64, best_ask: ?u64) void {
        self.best_bid_cache = best_bid;
        self.best_ask_cache = best_ask;
        self.last_update = std.time.milliTimestamp();
    }
    
    pub fn getBestBid(self: *OrderbookLevelCache) ?u64 {
        // Check if cache is fresh (within 100ms)
        const age = std.time.milliTimestamp() - self.last_update;
        if (age <= 100) {
            return self.best_bid_cache;
        }
        return null;
    }
    
    pub fn getBestAsk(self: *OrderbookLevelCache) ?u64 {
        // Check if cache is fresh (within 100ms)
        const age = std.time.milliTimestamp() - self.last_update;
        if (age <= 100) {
            return self.best_ask_cache;
        }
        return null;
    }
    
    pub fn cachePriceLevel(self: *OrderbookLevelCache, price: u64, entry: PriceLevelCacheEntry) !void {
        try self.price_level_cache.put(price, entry);
    }
    
    pub fn getPriceLevel(self: *OrderbookLevelCache, price: u64) ?PriceLevelCacheEntry {
        return self.price_level_cache.get(price);
    }
    
    pub fn printStatistics(self: *const OrderbookLevelCache) void {
        std.debug.print("\n=== Orderbook Cache Statistics ===\n");
        std.debug.print("Best Bid Cache: {?d}\n", .{self.best_bid_cache});
        std.debug.print("Best Ask Cache: {?d}\n", .{self.best_ask_cache});
        std.debug.print("Last Update: {d}ms ago\n", .{std.time.milliTimestamp() - self.last_update});
        self.price_level_cache.printStatistics();
    }
};

// Test function for the enhanced cache
pub fn testEnhancedCache() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var cache = MultiLevelCache(u64, []const u8).init(allocator);
    defer cache.deinit();
    
    std.debug.print("Testing Enhanced Multi-Level Cache...\n");
    
    // Test basic operations
    try cache.put(1, "value1");
    try cache.put(2, "value2");
    try cache.put(3, "value3");
    
    if (cache.get(1)) |value| {
        std.debug.print("Found: {s}\n", .{value});
    }
    
    // Simulate access patterns
    var i: u64 = 0;
    while (i < 10000) : (i += 1) {
        // Hot data - accessed frequently
        if (i % 10 < 3) {
            _ = cache.get(1);
            _ = cache.get(2);
        }
        // Warm data - accessed occasionally
        else if (i % 100 < 10) {
            _ = cache.get(3);
            _ = cache.get(4);
        }
        // Cold data - accessed rarely
        else {
            try cache.put(i + 100, "cold_value");
            _ = cache.get(i + 100);
        }
    }
    
    cache.printStatistics();
    cache.optimizeSizes();
    std.debug.print("Cache sizes optimized based on hit ratios\n");
}

pub fn main() !void {
    try testEnhancedCache();
}