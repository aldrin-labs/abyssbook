const std = @import("std");
const Pubkey = @import("processor.zig").Pubkey;

pub const OrderMatch = struct {
    match_id: u64,
    maker_order_id: u64,
    taker_order_id: u64,
    price: u64,
    quantity: u64,
    maker_fee: u64,
    taker_fee: u64,
    is_settled: bool,
    timestamp: i64,

    pub fn init(
        match_id: u64,
        maker_order_id: u64,
        taker_order_id: u64,
        price: u64,
        quantity: u64,
        maker_fee: u64,
        taker_fee: u64,
        timestamp: i64,
    ) OrderMatch {
        return .{
            .match_id = match_id,
            .maker_order_id = maker_order_id,
            .taker_order_id = taker_order_id,
            .price = price,
            .quantity = quantity,
            .maker_fee = maker_fee,
            .taker_fee = taker_fee,
            .is_settled = false,
            .timestamp = timestamp,
        };
    }

    pub fn totalValue(self: *const OrderMatch) u64 {
        return self.price * self.quantity;
    }

    pub fn totalFees(self: *const OrderMatch) u64 {
        return self.maker_fee + self.taker_fee;
    }
};
