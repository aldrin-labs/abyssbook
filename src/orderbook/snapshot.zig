const std = @import("std");
const types = @import("types.zig");

pub const OrderSnapshot = struct {
    price: u64,
    amount: u64,
    id: u64,
    side: types.OrderSide,
    order_type: types.OrderType,
    stop_price: ?u64,
};

pub const BookSnapshot = struct {
    orders: []OrderSnapshot,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const BookSnapshot) void {
        self.allocator.free(self.orders);
    }
};
