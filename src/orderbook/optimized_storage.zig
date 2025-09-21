const std = @import("std");

/// Cache-optimized order storage with structure-of-arrays layout
pub const OptimizedOrderStorage = struct {
    allocator: std.mem.Allocator,
    capacity: usize,
    count: usize,
    
    // Structure of Arrays for better cache locality
    prices: []u64,      // Aligned for SIMD operations
    amounts: []u64,     // Aligned for SIMD operations
    ids: []u64,         // Order IDs
    sides: []u8,        // Buy=0, Sell=1 (packed efficiently)
    flags: []u32,       // Order flags packed into single u32
    timestamps: []i64,  // For time-based operations
    
    // Index structures for fast lookup
    id_to_index: std.HashMap(u64, u32, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage),
    price_indices: std.AutoArrayHashMap(u64, std.ArrayList(u32)), // Price -> list of indices
    
    const SIMD_WIDTH = 8; // AVX2 64-bit elements
    const CACHE_LINE_SIZE = 64;
    const PREFETCH_DISTANCE = 2;
    
    pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !OptimizedOrderStorage {
        // Align capacity to SIMD width for better vectorization
        const aligned_capacity = ((initial_capacity + SIMD_WIDTH - 1) / SIMD_WIDTH) * SIMD_WIDTH;
        
        const prices = try allocator.alignedAlloc(u64, CACHE_LINE_SIZE, aligned_capacity);
        const amounts = try allocator.alignedAlloc(u64, CACHE_LINE_SIZE, aligned_capacity);
        const ids = try allocator.alignedAlloc(u64, CACHE_LINE_SIZE, aligned_capacity);
        const sides = try allocator.alignedAlloc(u8, CACHE_LINE_SIZE, aligned_capacity);
        const flags = try allocator.alignedAlloc(u32, CACHE_LINE_SIZE, aligned_capacity);
        const timestamps = try allocator.alignedAlloc(i64, CACHE_LINE_SIZE, aligned_capacity);
        
        return OptimizedOrderStorage{
            .allocator = allocator,
            .capacity = aligned_capacity,
            .count = 0,
            .prices = prices,
            .amounts = amounts,
            .ids = ids,
            .sides = sides,
            .flags = flags,
            .timestamps = timestamps,
            .id_to_index = std.HashMap(u64, u32, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .price_indices = std.AutoArrayHashMap(u64, std.ArrayList(u32)).init(allocator),
        };
    }
    
    pub fn deinit(self: *OptimizedOrderStorage) void {
        self.allocator.free(self.prices);
        self.allocator.free(self.amounts);
        self.allocator.free(self.ids);
        self.allocator.free(self.sides);
        self.allocator.free(self.flags);
        self.allocator.free(self.timestamps);
        self.id_to_index.deinit();
        
        var price_it = self.price_indices.iterator();
        while (price_it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.price_indices.deinit();
    }
    
    pub fn addOrder(self: *OptimizedOrderStorage, price: u64, amount: u64, id: u64, side: u8, order_flags: u32) !u32 {
        if (self.count >= self.capacity) {
            try self.resize(self.capacity * 2);
        }
        
        const index = @as(u32, @intCast(self.count));
        
        self.prices[self.count] = price;
        self.amounts[self.count] = amount;
        self.ids[self.count] = id;
        self.sides[self.count] = side;
        self.flags[self.count] = order_flags;
        self.timestamps[self.count] = std.time.nanoTimestamp();
        
        // Update indices
        try self.id_to_index.put(id, index);
        
        // Update price index
        if (self.price_indices.getPtr(price)) |indices| {
            try indices.append(index);
        } else {
            var new_indices = std.ArrayList(u32).init(self.allocator);
            try new_indices.append(index);
            try self.price_indices.put(price, new_indices);
        }
        
        self.count += 1;
        return index;
    }
    
    pub fn removeOrder(self: *OptimizedOrderStorage, id: u64) bool {
        if (self.id_to_index.get(id)) |index| {
            return self.removeByIndex(index);
        }
        return false;
    }
    
    fn removeByIndex(self: *OptimizedOrderStorage, index: u32) bool {
        if (index >= self.count) return false;
        
        const price = self.prices[index];
        const id = self.ids[index];
        
        // Remove from price index
        if (self.price_indices.getPtr(price)) |indices| {
            for (indices.items, 0..) |idx, i| {
                if (idx == index) {
                    _ = indices.swapRemove(i);
                    break;
                }
            }
            
            // If no more orders at this price, remove the price entry
            if (indices.items.len == 0) {
                indices.deinit();
                _ = self.price_indices.swapRemove(price);
            }
        }
        
        // Remove from ID index
        _ = self.id_to_index.remove(id);
        
        // Swap with last element to maintain density
        if (index < self.count - 1) {
            const last_index = self.count - 1;
            const last_id = self.ids[last_index];
            const last_price = self.prices[last_index];
            
            // Copy last element to removed position
            self.prices[index] = self.prices[last_index];
            self.amounts[index] = self.amounts[last_index];
            self.ids[index] = self.ids[last_index];
            self.sides[index] = self.sides[last_index];
            self.flags[index] = self.flags[last_index];
            self.timestamps[index] = self.timestamps[last_index];
            
            // Update indices
            try self.id_to_index.put(last_id, index) catch return false;
            
            if (self.price_indices.getPtr(last_price)) |indices| {
                for (indices.items) |*idx| {
                    if (idx.* == last_index) {
                        idx.* = index;
                        break;
                    }
                }
            }
        }
        
        self.count -= 1;
        return true;
    }
    
    // SIMD-optimized price filtering
    pub fn getOrdersAtPrice(self: *const OptimizedOrderStorage, price: u64, output: []u32) usize {
        if (self.price_indices.get(price)) |indices| {
            const copy_count = @min(indices.items.len, output.len);
            @memcpy(output[0..copy_count], indices.items[0..copy_count]);
            return copy_count;
        }
        return 0;
    }
    
    // SIMD-optimized range queries
    pub fn getOrdersInPriceRange(self: *const OptimizedOrderStorage, min_price: u64, max_price: u64, output: []u32) usize {
        var result_count: usize = 0;
        const PriceVector = @Vector(SIMD_WIDTH, u64);
        const min_vec: PriceVector = @splat(min_price);
        const max_vec: PriceVector = @splat(max_price);
        
        var i: usize = 0;
        // Process in SIMD chunks
        while (i + SIMD_WIDTH <= self.count and result_count < output.len) {
            // Prefetch next cache line
            if (i + PREFETCH_DISTANCE * SIMD_WIDTH < self.count) {
                const prefetch_addr = @intFromPtr(&self.prices[i + PREFETCH_DISTANCE * SIMD_WIDTH]);
                asm volatile ("prefetcht0 (%[addr])"
                    : // no outputs
                    : [addr] "r" (prefetch_addr),
                );
            }
            
            const price_vec: PriceVector = self.prices[i..i+SIMD_WIDTH][0..SIMD_WIDTH].*;
            const in_range = (price_vec >= min_vec) & (price_vec <= max_vec);
            
            // Extract matching indices
            for (0..SIMD_WIDTH) |j| {
                if (in_range[j] and result_count < output.len) {
                    output[result_count] = @as(u32, @intCast(i + j));
                    result_count += 1;
                }
            }
            
            i += SIMD_WIDTH;
        }
        
        // Handle remaining elements
        while (i < self.count and result_count < output.len) {
            if (self.prices[i] >= min_price and self.prices[i] <= max_price) {
                output[result_count] = @as(u32, @intCast(i));
                result_count += 1;
            }
            i += 1;
        }
        
        return result_count;
    }
    
    // SIMD-optimized volume calculation
    pub fn getTotalVolumeAtPrice(self: *const OptimizedOrderStorage, price: u64) u64 {
        if (self.price_indices.get(price)) |indices| {
            var total: u64 = 0;
            const AmountVector = @Vector(SIMD_WIDTH, u64);
            
            var i: usize = 0;
            // Process in SIMD chunks
            while (i + SIMD_WIDTH <= indices.items.len) {
                const indices_chunk = indices.items[i..i+SIMD_WIDTH];
                var amounts: [SIMD_WIDTH]u64 = undefined;
                
                // Gather amounts (this could be optimized with AVX2 gather instructions)
                for (indices_chunk, 0..) |idx, j| {
                    amounts[j] = self.amounts[idx];
                }
                
                const amount_vec: AmountVector = amounts;
                total += @reduce(.Add, amount_vec);
                i += SIMD_WIDTH;
            }
            
            // Handle remaining elements
            while (i < indices.items.len) : (i += 1) {
                total += self.amounts[indices.items[i]];
            }
            
            return total;
        }
        return 0;
    }
    
    // Batch operations for better cache utilization
    pub fn updateAmounts(self: *OptimizedOrderStorage, updates: []const AmountUpdate) void {
        const AmountVector = @Vector(SIMD_WIDTH, u64);
        
        var i: usize = 0;
        while (i + SIMD_WIDTH <= updates.len) {
            // Prefetch next batch
            if (i + PREFETCH_DISTANCE * SIMD_WIDTH < updates.len) {
                const prefetch_addr = @intFromPtr(&updates[i + PREFETCH_DISTANCE * SIMD_WIDTH]);
                asm volatile ("prefetcht0 (%[addr])"
                    : // no outputs
                    : [addr] "r" (prefetch_addr),
                );
            }
            
            // Gather current amounts
            var current_amounts: [SIMD_WIDTH]u64 = undefined;
            var new_amounts: [SIMD_WIDTH]u64 = undefined;
            
            for (0..SIMD_WIDTH) |j| {
                const update = updates[i + j];
                current_amounts[j] = self.amounts[update.index];
                new_amounts[j] = update.new_amount;
            }
            
            // Vectorized update
            const new_vec: AmountVector = new_amounts;
            
            // Scatter back (this could be optimized with AVX2 scatter instructions)
            for (0..SIMD_WIDTH) |j| {
                self.amounts[updates[i + j].index] = new_vec[j];
            }
            
            i += SIMD_WIDTH;
        }
        
        // Handle remaining updates
        while (i < updates.len) : (i += 1) {
            const update = updates[i];
            self.amounts[update.index] = update.new_amount;
        }
    }
    
    pub const AmountUpdate = struct {
        index: u32,
        new_amount: u64,
    };
    
    fn resize(self: *OptimizedOrderStorage, new_capacity: usize) !void {
        const aligned_capacity = ((new_capacity + SIMD_WIDTH - 1) / SIMD_WIDTH) * SIMD_WIDTH;
        
        // Reallocate arrays
        self.prices = try self.allocator.realloc(self.prices, aligned_capacity);
        self.amounts = try self.allocator.realloc(self.amounts, aligned_capacity);
        self.ids = try self.allocator.realloc(self.ids, aligned_capacity);
        self.sides = try self.allocator.realloc(self.sides, aligned_capacity);
        self.flags = try self.allocator.realloc(self.flags, aligned_capacity);
        self.timestamps = try self.allocator.realloc(self.timestamps, aligned_capacity);
        
        self.capacity = aligned_capacity;
    }
    
    pub fn getMemoryUsage(self: *const OptimizedOrderStorage) struct {
        arrays_bytes: usize,
        indices_bytes: usize,
        total_bytes: usize,
    } {
        const arrays_bytes = self.capacity * (
            @sizeOf(u64) + // prices
            @sizeOf(u64) + // amounts  
            @sizeOf(u64) + // ids
            @sizeOf(u8) +  // sides
            @sizeOf(u32) + // flags
            @sizeOf(i64)   // timestamps
        );
        
        // Estimate index overhead (rough approximation)
        const indices_bytes = self.count * @sizeOf(u64) * 2; // ID index + price indices
        
        return .{
            .arrays_bytes = arrays_bytes,
            .indices_bytes = indices_bytes,
            .total_bytes = arrays_bytes + indices_bytes,
        };
    }
    
    pub fn printStatistics(self: *const OptimizedOrderStorage) void {
        const memory = self.getMemoryUsage();
        std.debug.print("\n=== Optimized Order Storage Statistics ===\n");
        std.debug.print("Orders: {d}/{d} ({d:.1}% full)\n", .{ 
            self.count, 
            self.capacity, 
            @as(f64, @floatFromInt(self.count)) / @as(f64, @floatFromInt(self.capacity)) * 100.0 
        });
        std.debug.print("Memory Usage:\n");
        std.debug.print("  Arrays: {d:.2} MB\n", .{@as(f64, @floatFromInt(memory.arrays_bytes)) / 1_048_576.0});
        std.debug.print("  Indices: {d:.2} MB\n", .{@as(f64, @floatFromInt(memory.indices_bytes)) / 1_048_576.0});
        std.debug.print("  Total: {d:.2} MB\n", .{@as(f64, @floatFromInt(memory.total_bytes)) / 1_048_576.0});
        std.debug.print("  Bytes per order: {d}\n", .{if (self.count > 0) memory.total_bytes / self.count else 0});
        std.debug.print("Price levels: {d}\n", .{self.price_indices.count()});
        std.debug.print("Cache alignment: {d}-byte aligned\n", .{CACHE_LINE_SIZE});
        std.debug.print("SIMD width: {d} elements\n", .{SIMD_WIDTH});
        std.debug.print("\n");
    }
};

// Test the optimized storage
pub fn testOptimizedStorage() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Testing Optimized Order Storage...\n");
    
    var storage = try OptimizedOrderStorage.init(allocator, 1000);
    defer storage.deinit();
    
    // Add test orders
    const orders = [_]struct { price: u64, amount: u64, id: u64, side: u8 }{
        .{ .price = 100, .amount = 50, .id = 1, .side = 0 },
        .{ .price = 101, .amount = 75, .id = 2, .side = 0 },
        .{ .price = 100, .amount = 25, .id = 3, .side = 0 },
        .{ .price = 99, .amount = 100, .id = 4, .side = 1 },
        .{ .price = 98, .amount = 200, .id = 5, .side = 1 },
    };
    
    for (orders) |order| {
        _ = try storage.addOrder(order.price, order.amount, order.id, order.side, 0);
    }
    
    storage.printStatistics();
    
    // Test price range query
    var results: [10]u32 = undefined;
    const count = storage.getOrdersInPriceRange(99, 101, &results);
    std.debug.print("Orders in range 99-101: {d}\n", .{count});
    
    // Test volume calculation
    const volume_100 = storage.getTotalVolumeAtPrice(100);
    std.debug.print("Total volume at price 100: {d}\n", .{volume_100});
    
    // Test removal
    const removed = storage.removeOrder(2);
    std.debug.print("Removed order 2: {}\n", .{removed});
    
    storage.printStatistics();
}

pub fn main() !void {
    try testOptimizedStorage();
}