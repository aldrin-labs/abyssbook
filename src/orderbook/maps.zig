const std = @import("std");
const types = @import("types.zig");
const order = @import("order.zig");

pub const OrderMap = std.AutoArrayHashMap(types.OrderKey, order.CacheAlignedOrder);
pub const StopOrderMap = std.AutoArrayHashMap(types.OrderKey, order.CacheAlignedOrder);

const MAX_LEVEL = 16;
const P = 0.5;

const SkipNode = struct {
    price: u64,
    level: types.PriceLevel,
    forward: [MAX_LEVEL]?*SkipNode,

    pub fn init(price: u64, level_data: types.PriceLevel, allocator: std.mem.Allocator) !*SkipNode {
        const node = try allocator.create(SkipNode);
        node.* = .{
            .price = price,
            .level = level_data,
            .forward = [_]?*SkipNode{null} ** MAX_LEVEL,
        };
        return node;
    }
};

pub const OptimizedPriceLevelMap = struct {
    head: *SkipNode,
    level: usize,
    allocator: std.mem.Allocator,
    rng: std.rand.DefaultPrng,
    len: usize,

    pub fn init(allocator: std.mem.Allocator) !OptimizedPriceLevelMap {
        const head = try SkipNode.init(0, .{ .total_volume = 0, .order_count = 0 }, allocator);
        return OptimizedPriceLevelMap{
            .head = head,
            .level = 1,
            .allocator = allocator,
            .rng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp())),
            .len = 0,
        };
    }

    pub fn deinit(self: *OptimizedPriceLevelMap) void {
        var current = self.head;
        while (current.forward[0]) |next| {
            const to_free = current;
            current = next;
            self.allocator.destroy(to_free);
        }
        self.allocator.destroy(current);
    }

    fn randomLevel(self: *OptimizedPriceLevelMap) usize {
        var level: usize = 1;
        while (level < MAX_LEVEL and self.rng.random().float(f64) < P) {
            level += 1;
        }
        return level;
    }

    pub fn get(self: *const OptimizedPriceLevelMap, price: u64) ?types.PriceLevel {
        var current = self.head;
        var i = self.level - 1;
        while (true) {
            while (current.forward[i]) |next| {
                if (next.price > price) break;
                if (next.price == price) return next.level;
                current = next;
            }
            if (i == 0) break;
            i -= 1;
        }
        return null;
    }

    pub fn getPtr(self: *OptimizedPriceLevelMap, price: u64) ?*types.PriceLevel {
        var current = self.head;
        var i = self.level - 1;
        while (true) {
            while (current.forward[i]) |next| {
                if (next.price > price) break;
                if (next.price == price) return &next.level;
                current = next;
            }
            if (i == 0) break;
            i -= 1;
        }
        return null;
    }

    pub fn put(self: *OptimizedPriceLevelMap, price: u64, level: types.PriceLevel) !void {
        var update = [_]?*SkipNode{null} ** MAX_LEVEL;
        var current = self.head;
        var i = self.level - 1;

        while (true) : (i -= 1) {
            while (current.forward[i]) |next| {
                if (next.price > price) break;
                if (next.price == price) {
                    next.level = level;
                    return;
                }
                current = next;
            }
            update[i] = current;
            if (i == 0) break;
        }

        const new_level = self.randomLevel();
        if (new_level > self.level) {
            for (self.level..new_level) |j| {
                update[j] = self.head;
            }
            self.level = new_level;
        }

        const new_node = try SkipNode.init(price, level, self.allocator);
        i = 0;
        while (i < new_level) : (i += 1) {
            if (update[i]) |node| {
                new_node.forward[i] = node.forward[i];
                node.forward[i] = new_node;
            }
        }
        self.len += 1;
    }

    pub fn swapRemove(self: *OptimizedPriceLevelMap, price: u64) bool {
        var update = [_]?*SkipNode{null} ** MAX_LEVEL;
        var current = self.head;
        var i = self.level - 1;

        var found = false;
        while (true) : (i -= 1) {
            while (current.forward[i]) |next| {
                if (next.price > price) break;
                if (next.price == price) {
                    found = true;
                    break;
                }
                current = next;
            }
            update[i] = current;
            if (i == 0) break;
        }

        if (!found) return false;

        const to_remove = current.forward[0].?;
        i = 0;
        while (i < self.level) : (i += 1) {
            if (update[i]) |node| {
                if (node.forward[i] == to_remove) {
                    node.forward[i] = to_remove.forward[i];
                }
            }
        }

        while (self.level > 1 and self.head.forward[self.level - 1] == null) {
            self.level -= 1;
        }

        self.allocator.destroy(to_remove);
        self.len -= 1;
        return true;
    }

    pub fn count(self: *const OptimizedPriceLevelMap) usize {
        return self.len;
    }

    pub const Iterator = struct {
        current: ?*SkipNode,

        pub fn next(self: *Iterator) ?struct { key_ptr: *u64, value_ptr: *types.PriceLevel } {
            const node = self.current orelse return null;
            self.current = node.forward[0];
            return .{
                .key_ptr = &node.price,
                .value_ptr = &node.level,
            };
        }
    };

    pub fn iterator(self: *const OptimizedPriceLevelMap) Iterator {
        return .{ .current = self.head.forward[0] };
    }
};

pub const PriceLevelMap = OptimizedPriceLevelMap;
