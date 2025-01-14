const std = @import("std");
const types = @import("types.zig");
const order = @import("order.zig");

pub const TWAPParams = struct {
    total_amount: u64,
    interval_seconds: u64,
    num_intervals: u64,
    start_time: i64,
    amount_per_interval: u64,
    intervals_executed: u64 = 0,
};

pub const TrailingStopParams = struct {
    distance: u64,
    last_trigger_price: u64,
    current_stop_price: u64,
};

pub const OSOParams = struct {
    child_order: order.CacheAlignedOrder,
    is_child_placed: bool = false,
};

pub const OCOParams = struct {
    linked_order: order.CacheAlignedOrder,
    is_cancelled: bool = false,
};

pub const PegType = enum {
    BestBid,
    BestAsk,
    Midpoint,
    LastTrade,
};

pub const PegParams = struct {
    peg_type: PegType,
    offset: i64,
    limit_price: ?u64 = null,
};

pub const DiscretionaryParams = struct {
    discretionary_price: u64,
};

pub const ConditionalType = enum {
    Price,
    Time,
    Volume,
    Custom,
};

pub const ConditionalParams = struct {
    condition_type: ConditionalType,
    price_threshold: ?u64 = null,
    time_threshold: ?i64 = null,
    volume_threshold: ?u64 = null,
    custom_condition: ?*const fn (order: *const order.CacheAlignedOrder) bool = null,
};
