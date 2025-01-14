const std = @import("std");
const Pubkey = @import("processor.zig").Pubkey;

pub const Side = enum(u8) {
    Buy,
    Sell,
};

pub const OrderType = enum(u8) {
    Limit,
    Market,
    PostOnly,
    FillOrKill,
    ImmediateOrCancel,
};

pub const Order = struct {
    order_id: u64,
    owner: Pubkey,
    side: Side,
    order_type: OrderType,
    price: u64,
    quantity: u64,
    filled_quantity: u64,
    timestamp: i64,
    is_active: bool,

    pub fn init(
        order_id: u64,
        owner: Pubkey,
        side: Side,
        order_type: OrderType,
        price: u64,
        quantity: u64,
        timestamp: i64,
    ) Order {
        return .{
            .order_id = order_id,
            .owner = owner,
            .side = side,
            .order_type = order_type,
            .price = price,
            .quantity = quantity,
            .filled_quantity = 0,
            .timestamp = timestamp,
            .is_active = true,
        };
    }

    pub fn remainingQuantity(self: *const Order) u64 {
        return self.quantity - self.filled_quantity;
    }

    pub fn isFilled(self: *const Order) bool {
        return self.filled_quantity >= self.quantity;
    }

    pub fn isPostOnly(self: *const Order) bool {
        return self.order_type == .PostOnly;
    }

    pub fn isFillOrKill(self: *const Order) bool {
        return self.order_type == .FillOrKill;
    }

    pub fn isImmediateOrCancel(self: *const Order) bool {
        return self.order_type == .ImmediateOrCancel;
    }
};
