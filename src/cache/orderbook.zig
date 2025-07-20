const std = @import("std");
const Orderbook = @import("../blockchain/client.zig").Orderbook;
const Order = @import("../blockchain/client.zig").Order;

/// Cache for storing orderbook data to improve performance
pub const OrderbookCache = struct {
    allocator: std.mem.Allocator,
    market_to_orderbook: std.StringHashMap(CachedOrderbook),
    ttl_ms: u64, // Time-to-live in milliseconds
    
    /// Cached orderbook with timestamp
    const CachedOrderbook = struct {
        orderbook: Orderbook,
        timestamp: i64,
    };
    
    /// Initialize a new orderbook cache
    pub fn init(allocator: std.mem.Allocator, ttl_ms: u64) !OrderbookCache {
        return OrderbookCache{
            .allocator = allocator,
            .market_to_orderbook = std.StringHashMap(CachedOrderbook).init(allocator),
            .ttl_ms = ttl_ms,
        };
    }
    
    /// Get orderbook from cache if available and not expired
    pub fn get(self: *OrderbookCache, market: []const u8) ?Orderbook {
        const current_time = std.time.milliTimestamp();
        
        if (self.market_to_orderbook.get(market)) |cached| {
            // Check if cache entry is still valid
            const age_ms = @as(u64, @intCast(current_time - cached.timestamp));
            if (age_ms <= self.ttl_ms) {
                // Clone the orderbook for the caller
                return self.cloneOrderbook(cached.orderbook) catch return null;
            } else {
                // Cache entry is expired, remove it
                _ = self.market_to_orderbook.remove(market);
            }
        }
        
        return null;
    }
    
    /// Store orderbook in cache
    pub fn put(self: *OrderbookCache, market: []const u8, orderbook: Orderbook) !void {
        // Clone the market string and orderbook for storage
        const market_copy = try self.allocator.dupe(u8, market);
        errdefer self.allocator.free(market_copy);
        
        const orderbook_copy = try self.cloneOrderbook(orderbook);
        errdefer {
            orderbook_copy.deinit(self.allocator);
        }
        
        // Create cache entry
        const cached = CachedOrderbook{
            .orderbook = orderbook_copy,
            .timestamp = std.time.milliTimestamp(),
        };
        
        // Remove existing entry if present
        if (self.market_to_orderbook.get(market)) |existing| {
            existing.orderbook.deinit(self.allocator);
            _ = self.market_to_orderbook.remove(market);
        }
        
        // Store new entry
        try self.market_to_orderbook.put(market_copy, cached);
    }
    
    /// Clear all cached entries
    pub fn clear(self: *OrderbookCache) void {
        var it = self.market_to_orderbook.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.orderbook.deinit(self.allocator);
        }
        self.market_to_orderbook.clearAndFree();
    }
    
    /// Clone an orderbook
    fn cloneOrderbook(self: *OrderbookCache, orderbook: Orderbook) !Orderbook {
        // Clone market and market address
        const market_copy = try self.allocator.dupe(u8, orderbook.market);
        errdefer self.allocator.free(market_copy);
        
        const market_address_copy = try self.allocator.dupe(u8, orderbook.market_address);
        errdefer self.allocator.free(market_address_copy);
        
        // Clone bids
        const bids_copy = try self.allocator.alloc(Order, orderbook.bids.len);
        errdefer self.allocator.free(bids_copy);
        
        for (orderbook.bids, 0..) |bid, i| {
            bids_copy[i].price = bid.price;
            bids_copy[i].size = bid.size;
            bids_copy[i].order_id = try self.allocator.dupe(u8, bid.order_id);
            errdefer self.allocator.free(bids_copy[i].order_id);
            
            bids_copy[i].owner_address = try self.allocator.dupe(u8, bid.owner_address);
            errdefer self.allocator.free(bids_copy[i].owner_address);
        }
        
        // Clone asks
        const asks_copy = try self.allocator.alloc(Order, orderbook.asks.len);
        errdefer self.allocator.free(asks_copy);
        
        for (orderbook.asks, 0..) |ask, i| {
            asks_copy[i].price = ask.price;
            asks_copy[i].size = ask.size;
            asks_copy[i].order_id = try self.allocator.dupe(u8, ask.order_id);
            errdefer self.allocator.free(asks_copy[i].order_id);
            
            asks_copy[i].owner_address = try self.allocator.dupe(u8, ask.owner_address);
            errdefer self.allocator.free(asks_copy[i].owner_address);
        }
        
        return Orderbook{
            .market = market_copy,
            .market_address = market_address_copy,
            .bids = bids_copy,
            .asks = asks_copy,
        };
    }
    
    /// Deinitialize the cache and free resources
    pub fn deinit(self: *OrderbookCache) void {
        self.clear();
        self.market_to_orderbook.deinit();
    }
};
