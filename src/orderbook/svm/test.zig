const std = @import("std");
const testing = std.testing;
const processor = @import("processor.zig");
const instruction = @import("instruction.zig");
const order_mod = @import("order.zig");
const match_mod = @import("match.zig");
const token = @import("token.zig");
const state_manager_mod = @import("state_manager.zig");

const Pubkey = processor.Pubkey;
const Order = order_mod.Order;
const Side = order_mod.Side;
const OrderType = order_mod.OrderType;
const OrderMatch = match_mod.OrderMatch;
const TokenAccount = token.TokenAccount;
const StateManager = state_manager_mod.StateManager;
const OrderbookState = instruction.OrderbookState;
const Processor = processor.Processor;

test "orderbook initialization" {
    var state_manager = try StateManager.init(testing.allocator);
    defer state_manager.deinit();

    var state = OrderbookState.init(
        [_]u8{1} ** 32, // market_authority
        [_]u8{2} ** 32, // base_mint
        [_]u8{3} ** 32, // quote_mint
        [_]u8{4} ** 32, // base_vault
        [_]u8{5} ** 32, // quote_vault
        10, // fee_rate_bps
        100, // min_base_order_size
        1, // tick_size
    );

    var processor_instance = Processor.init(
        &state,
        &[_]u8{},
        std.time.timestamp(),
        &state_manager,
    );

    // Test initialization
    try processor_instance.process(&[_]u8{@intFromEnum(instruction.OrderbookInstruction.InitializeOrderbook)}, &[_]u8{});
    try testing.expect(state.is_initialized);
}

test "place and match orders" {
    var state_manager = try StateManager.init(testing.allocator);
    defer state_manager.deinit();

    var state = OrderbookState.init(
        [_]u8{1} ** 32, // market_authority
        [_]u8{2} ** 32, // base_mint
        [_]u8{3} ** 32, // quote_mint
        [_]u8{4} ** 32, // base_vault
        [_]u8{5} ** 32, // quote_vault
        10, // fee_rate_bps
        100, // min_base_order_size
        1, // tick_size
    );

    var processor_instance = Processor.init(
        &state,
        &[_]u8{},
        std.time.timestamp(),
        &state_manager,
    );

    // Initialize orderbook
    try processor_instance.process(&[_]u8{@intFromEnum(instruction.OrderbookInstruction.InitializeOrderbook)}, &[_]u8{});

    // Create token accounts
    const maker_pubkey = [_]u8{10} ** 32;
    const taker_pubkey = [_]u8{11} ** 32;

    // Add token accounts for maker
    try state_manager.addTokenAccount(TokenAccount{
        .address = maker_pubkey,
        .owner = maker_pubkey,
        .mint = state.base_mint,
        .amount = 1000,
        .delegate = null,
        .is_frozen = false,
    });
    try state_manager.addTokenAccount(TokenAccount{
        .address = maker_pubkey,
        .owner = maker_pubkey,
        .mint = state.quote_mint,
        .amount = 1000000,
        .delegate = null,
        .is_frozen = false,
    });

    // Add token accounts for taker
    try state_manager.addTokenAccount(TokenAccount{
        .address = taker_pubkey,
        .owner = taker_pubkey,
        .mint = state.base_mint,
        .amount = 1000,
        .delegate = null,
        .is_frozen = false,
    });
    try state_manager.addTokenAccount(TokenAccount{
        .address = taker_pubkey,
        .owner = taker_pubkey,
        .mint = state.quote_mint,
        .amount = 1000000,
        .delegate = null,
        .is_frozen = false,
    });

    // Place maker order (sell 500 @ 100)
    const maker_order = Order.init(
        state_manager.getNextOrderId(),
        maker_pubkey,
        .Ask,
        .Limit,
        100,
        500,
        std.time.timestamp(),
    );

    var maker_order_data = std.ArrayList(u8).init(testing.allocator);
    defer maker_order_data.deinit();

    try maker_order_data.append(@intFromEnum(instruction.OrderbookInstruction.PlaceOrder));
    try maker_order_data.appendSlice(std.mem.asBytes(&maker_order));

    try processor_instance.process(maker_order_data.items, &[_]u8{});

    // Place taker order (buy 300 @ 100)
    const taker_order = Order.init(
        state_manager.getNextOrderId(),
        taker_pubkey,
        .Bid,
        .Limit,
        100,
        300,
        std.time.timestamp(),
    );

    var taker_order_data = std.ArrayList(u8).init(testing.allocator);
    defer taker_order_data.deinit();

    try taker_order_data.append(@intFromEnum(instruction.OrderbookInstruction.PlaceOrder));
    try taker_order_data.appendSlice(std.mem.asBytes(&taker_order));

    try processor_instance.process(taker_order_data.items, &[_]u8{});

    // Match orders
    try processor_instance.process(&[_]u8{@intFromEnum(instruction.OrderbookInstruction.MatchOrders)}, &[_]u8{});

    // Settle funds
    try processor_instance.process(&[_]u8{@intFromEnum(instruction.OrderbookInstruction.SettleFunds)}, &[_]u8{});

    // Verify token balances
    const maker_base = (try processor_instance.getBaseTokenAccount(maker_pubkey)).amount;
    const maker_quote = (try processor_instance.getQuoteTokenAccount(maker_pubkey)).amount;
    const taker_base = (try processor_instance.getBaseTokenAccount(taker_pubkey)).amount;
    const taker_quote = (try processor_instance.getQuoteTokenAccount(taker_pubkey)).amount;

    try testing.expectEqual(@as(u64, 500), maker_base);
    try testing.expectEqual(@as(u64, 1029850), maker_quote); // 1000000 + (300 * 100) - maker_fee
    try testing.expectEqual(@as(u64, 1300), taker_base); // 1000 + 300
    try testing.expectEqual(@as(u64, 969850), taker_quote); // 1000000 - (300 * 100) - taker_fee
}
