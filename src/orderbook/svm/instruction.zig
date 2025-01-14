const std = @import("std");
const Pubkey = @import("processor.zig").Pubkey;

pub const OrderbookInstruction = enum(u8) {
    InitializeOrderbook,
    PlaceOrder,
    CancelOrder,
    MatchOrders,
    SettleFunds,
    SweepFees,
    CloseOrderbook,
};

pub const OrderbookState = struct {
    is_initialized: bool,
    market_authority: Pubkey,
    base_mint: Pubkey,
    quote_mint: Pubkey,
    base_vault: Pubkey,
    quote_vault: Pubkey,
    fee_rate_bps: u16,
    min_base_order_size: u64,
    tick_size: u64,
    bump: u8,

    pub fn init(
        market_authority: Pubkey,
        base_mint: Pubkey,
        quote_mint: Pubkey,
        base_vault: Pubkey,
        quote_vault: Pubkey,
        fee_rate_bps: u16,
        min_base_order_size: u64,
        tick_size: u64,
    ) OrderbookState {
        return .{
            .is_initialized = false,
            .market_authority = market_authority,
            .base_mint = base_mint,
            .quote_mint = quote_mint,
            .base_vault = base_vault,
            .quote_vault = quote_vault,
            .fee_rate_bps = fee_rate_bps,
            .min_base_order_size = min_base_order_size,
            .tick_size = tick_size,
            .bump = 0,
        };
    }
};

pub const Program = struct {
    pub fn deserializeInstruction(data: []const u8) !OrderbookInstruction {
        if (data.len < 1) {
            return error.InvalidInstruction;
        }
        return @as(OrderbookInstruction, @enumFromInt(data[0]));
    }

    pub fn validateAccounts(accounts: []const u8) !void {
        _ = accounts;
        // Implement account validation
    }
};
