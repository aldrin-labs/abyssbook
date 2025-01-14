const std = @import("std");

pub const OrderSide = enum {
    Buy,
    Sell,
};

pub const OrderType = enum {
    Limit,
    Market,
    Stop,
    StopLimit,
    IOC,
    FOK,
    PostOnly,
    GTD,
    Iceberg,
    OCO,
    TWAP,
    OSO,
    TrailingStop,
    Peg,
    MidpointPeg,
    Discretionary,
    Conditional,
};

pub const OrderFlags = packed struct {
    is_stop: bool = false,
    is_ioc: bool = false,
    is_fok: bool = false,
    is_post_only: bool = false,
    is_gtd: bool = false,
    is_iceberg: bool = false,
    is_oco: bool = false,
    is_twap: bool = false,
    is_oso: bool = false,
    is_trailing_stop: bool = false,
    is_peg: bool = false,
    is_midpoint_peg: bool = false,
    is_discretionary: bool = false,
    is_conditional: bool = false,
    padding: u2 = 0,
};

pub const OrderKey = struct {
    price: u64,
    id: u64,
};

pub const PriceLevel = struct {
    total_volume: u64,
    order_count: usize,
};

pub const MatchResult = struct {
    filled_amount: u64,
    remaining_amount: u64,
    execution_price: u64,
};

pub const OrderModification = struct {
    new_price: ?u64 = null,
    new_amount: ?u64 = null,
};

pub const PriceLevelStats = struct {
    total_volume: u64,
    order_count: usize,
    min_amount: u64,
    max_amount: u64,
    avg_amount: u64,
};

pub const OrderError = error{
    OutOfMemory,
    InvalidPrice,
    InvalidAmount,
    OrderNotFound,
    DuplicateOrder,
};
