const std = @import("std");
const types = @import("types.zig");
const params = @import("order_params.zig");

pub const CacheAlignedOrder = struct {
    price: u64,
    amount: u64,
    id: u64,
    side: types.OrderSide,
    order_type: types.OrderType,
    stop_price: ?u64,
    flags: types.OrderFlags,
    expiry_time: ?i64 = null,
    display_amount: ?u64 = null,
    twap_params: ?*params.TWAPParams = null,
    trailing_params: ?*params.TrailingStopParams = null,
    oso_params: ?*params.OSOParams = null,
    oco_params: ?*params.OCOParams = null,
    peg_params: ?*params.PegParams = null,
    discretionary_params: ?*params.DiscretionaryParams = null,
    conditional_params: ?*params.ConditionalParams = null,
    padding: [8]u8,

    pub fn init(price: u64, amount: u64, id: u64, side: types.OrderSide, order_type: types.OrderType, stop_price: ?u64) CacheAlignedOrder {
        return .{
            .price = price,
            .amount = amount,
            .id = id,
            .side = side,
            .order_type = order_type,
            .stop_price = stop_price,
            .flags = .{
                .is_stop = order_type == .Stop or order_type == .StopLimit,
                .is_ioc = order_type == .IOC,
                .is_fok = order_type == .FOK,
                .is_post_only = order_type == .PostOnly,
                .is_gtd = order_type == .GTD,
                .is_iceberg = order_type == .Iceberg,
                .is_oco = order_type == .OCO,
                .is_twap = order_type == .TWAP,
                .is_oso = order_type == .OSO,
                .is_trailing_stop = order_type == .TrailingStop,
                .is_peg = order_type == .Peg,
                .is_midpoint_peg = order_type == .MidpointPeg,
                .is_discretionary = order_type == .Discretionary,
                .is_conditional = order_type == .Conditional,
            },
            .expiry_time = null,
            .display_amount = null,
            .twap_params = null,
            .trailing_params = null,
            .oso_params = null,
            .oco_params = null,
            .peg_params = null,
            .discretionary_params = null,
            .conditional_params = null,
            .padding = [_]u8{0} ** 8,
        };
    }

    pub fn deinit(self: *CacheAlignedOrder, allocator: std.mem.Allocator) void {
        if (self.twap_params) |params_ptr| {
            allocator.destroy(params_ptr);
        }
        if (self.trailing_params) |params_ptr| {
            allocator.destroy(params_ptr);
        }
        if (self.oso_params) |params_ptr| {
            allocator.destroy(params_ptr);
        }
        if (self.oco_params) |params_ptr| {
            allocator.destroy(params_ptr);
        }
        if (self.peg_params) |params_ptr| {
            allocator.destroy(params_ptr);
        }
        if (self.discretionary_params) |params_ptr| {
            allocator.destroy(params_ptr);
        }
        if (self.conditional_params) |params_ptr| {
            if (params_ptr.reference_symbol) |symbol| {
                allocator.free(symbol);
            }
            allocator.destroy(params_ptr);
        }
    }
};
