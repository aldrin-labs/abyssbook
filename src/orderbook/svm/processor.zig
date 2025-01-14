const std = @import("std");
const errors = @import("error.zig");
const instruction = @import("instruction.zig");
const order_mod = @import("order.zig");
const match_mod = @import("match.zig");
const token = @import("token.zig");
const state_manager_mod = @import("state_manager.zig");

pub const Pubkey = [32]u8;

const ProcessorError = errors.ProcessorError;
const OrderbookInstruction = instruction.OrderbookInstruction;
const OrderbookState = instruction.OrderbookState;
const Order = order_mod.Order;
const Side = order_mod.Side;
const OrderType = order_mod.OrderType;
const OrderMatch = match_mod.OrderMatch;
const TokenAccount = token.TokenAccount;
const StateManager = state_manager_mod.StateManager;

pub const Processor = struct {
    // Program state
    state: *OrderbookState,
    // Account data buffer
    account_data: []u8,
    // Current slot/timestamp
    clock: i64,
    // State manager for handling orderbook state
    state_manager: *StateManager,

    const Self = @This();

    pub fn init(
        state: *OrderbookState,
        account_data: []u8,
        clock: i64,
        state_manager: *StateManager,
    ) Self {
        return .{
            .state = state,
            .account_data = account_data,
            .clock = clock,
            .state_manager = state_manager,
        };
    }

    pub fn process(self: *Self, instruction_data: []const u8, accounts: []const u8) ProcessorError!void {
        const instruction_type = instruction.Program.deserializeInstruction(instruction_data) catch {
            return ProcessorError.InvalidInstruction;
        };

        try instruction.Program.validateAccounts(accounts);

        switch (instruction_type) {
            .InitializeOrderbook => try self.processInitialize(),
            .PlaceOrder => try self.processPlaceOrder(instruction_data[1..]),
            .CancelOrder => try self.processCancelOrder(instruction_data[1..]),
            .MatchOrders => try self.processMatchOrders(),
            .SettleFunds => try self.processSettleFunds(),
            .SweepFees => try self.processSweepFees(),
            .CloseOrderbook => try self.processCloseOrderbook(),
        }
    }

    fn processInitialize(self: *Self) ProcessorError!void {
        if (self.state.is_initialized) {
            return ProcessorError.InvalidInstruction;
        }

        self.state.is_initialized = true;
        self.state.bump = try self.findProgramAddress();
    }

    fn processPlaceOrder(self: *Self, data: []const u8) ProcessorError!void {
        if (!self.state.is_initialized) {
            return ProcessorError.OrderbookNotInitialized;
        }

        const order = try self.deserializeOrder(data);
        try self.validateOrder(order);

        // Add order to orderbook
        try self.addOrder(order);
    }

    fn processCancelOrder(self: *Self, data: []const u8) ProcessorError!void {
        if (!self.state.is_initialized) {
            return ProcessorError.OrderbookNotInitialized;
        }

        const order_id = std.mem.readIntLittle(u64, data[0..8]);
        try self.removeOrder(order_id);
    }

    fn processMatchOrders(self: *Self) ProcessorError!void {
        if (!self.state.is_initialized) {
            return ProcessorError.OrderbookNotInitialized;
        }

        // Match orders and generate trades
        try self.matchOrders();
    }

    fn processSettleFunds(self: *Self) ProcessorError!void {
        if (!self.state.is_initialized) {
            return ProcessorError.OrderbookNotInitialized;
        }

        // Get all pending matches
        var matches = try self.getPendingMatches();
        defer matches.deinit();

        // Process each match
        for (matches.items) |match| {
            // Get maker and taker orders
            const maker_order = self.state_manager.getOrder(match.maker_order_id) orelse
                continue;
            const taker_order = self.state_manager.getOrder(match.taker_order_id) orelse
                continue;

            // Calculate amounts
            const base_amount = match.quantity;
            const quote_amount = match.quantity * match.price;

            // Transfer base tokens
            if (maker_order.side == .Ask) {
                try self.transferBaseTokens(maker_order.owner, taker_order.owner, base_amount);
            } else {
                try self.transferBaseTokens(taker_order.owner, maker_order.owner, base_amount);
            }

            // Transfer quote tokens
            if (maker_order.side == .Ask) {
                try self.transferQuoteTokens(taker_order.owner, maker_order.owner, quote_amount);
            } else {
                try self.transferQuoteTokens(maker_order.owner, taker_order.owner, quote_amount);
            }

            // Collect fees
            try self.transferQuoteTokens(maker_order.owner, self.state.market_authority, match.maker_fee);
            try self.transferQuoteTokens(taker_order.owner, self.state.market_authority, match.taker_fee);

            // Mark match as settled
            try self.markMatchSettled(match);
        }
    }

    fn processSweepFees(self: *Self) ProcessorError!void {
        if (!self.state.is_initialized) {
            return ProcessorError.OrderbookNotInitialized;
        }

        // Get accumulated fees
        const fee_account = try self.getQuoteTokenAccount(self.state.market_authority);
        const fee_amount = fee_account.amount;

        if (fee_amount == 0) {
            return;
        }

        // Transfer fees to market authority
        try self.transferQuoteTokens(
            self.state.market_authority,
            self.state.market_authority,
            fee_amount,
        );

        // Emit fee collection event
        try self.emitEvent("FeesSweep", std.mem.asBytes(&fee_amount));
    }

    fn processCloseOrderbook(self: *Self) ProcessorError!void {
        if (!self.state.is_initialized) {
            return ProcessorError.OrderbookNotInitialized;
        }

        // Ensure all matches are settled
        if (try self.hasPendingMatches()) {
            return ProcessorError.InvalidInstruction;
        }

        // Cancel all open orders
        const orders = self.state_manager.getAllOrders();
        for (orders) |order| {
            if (order.order_id != 0) {
                try self.cancelOrder(order);
            }
        }

        // Transfer remaining fees
        try self.processSweepFees();

        // Clear state
        self.state_manager.clear();

        // Emit close event
        try self.emitEvent("OrderbookClosed", &[_]u8{});
    }

    // Helper functions
    fn findProgramAddress(self: *Self) !u8 {
        _ = self;
        // Implement program address derivation
        return 0;
    }

    fn deserializeOrder(data: []const u8) !Order {
        if (data.len < @sizeOf(Order)) {
            return ProcessorError.InvalidInstruction;
        }

        return @as(*const Order, @ptrCast(@alignCast(data.ptr))).*;
    }

    fn validateOrder(self: *Self, order: Order) !void {
        if (order.quantity < self.state.min_base_order_size) {
            return ProcessorError.InvalidInstruction;
        }

        if (order.price % self.state.tick_size != 0) {
            return ProcessorError.InvalidInstruction;
        }
    }

    fn addOrder(self: *Self, order: Order) !void {
        // Validate order owner's token balance
        try self.validateTokenBalance(order.owner, order.side, order.price * order.quantity);

        // Add order to state
        try self.state_manager.addOrder(order);

        // Emit order placed event
        try self.emitEvent("OrderPlaced", &[_]u8{
            @intFromEnum(order.side),
            @intFromEnum(order.order_type),
        });

        // Try to match order immediately if not post-only
        if (order.order_type != .PostOnly) {
            try self.matchOrder(order);
        }
    }

    fn matchOrder(self: *Self, taker_order: Order) !void {
        const opposite_side = if (taker_order.side == .Bid) .Ask else .Bid;
        var remaining_quantity = taker_order.quantity;

        // Get sorted orders from opposite side
        var maker_orders = try self.state_manager.getOrdersSorted(opposite_side);
        defer maker_orders.deinit();

        // Match against maker orders
        for (maker_orders.items) |*maker_order| {
            if (remaining_quantity == 0) break;

            const price_matches = if (taker_order.side == .Bid)
                maker_order.price <= taker_order.price
            else
                maker_order.price >= taker_order.price;

            if (!price_matches) break;

            // Calculate match quantity
            const match_quantity = @min(remaining_quantity, maker_order.quantity);
            const match_price = maker_order.price;

            // Calculate fees
            const maker_fee = self.calculateFee(match_quantity, match_price, true);
            const taker_fee = self.calculateFee(match_quantity, match_price, false);

            // Create match record
            const match = OrderMatch.init(
                self.state_manager.getNextMatchId(),
                maker_order.order_id,
                taker_order.order_id,
                match_price,
                match_quantity,
                maker_fee,
                taker_fee,
                self.clock,
            );

            // Update order quantities
            remaining_quantity -= match_quantity;
            maker_order.quantity -= match_quantity;

            // Record match
            try self.recordMatch(match);

            // Remove filled maker order
            if (maker_order.quantity == 0) {
                try self.state_manager.removeOrder(maker_order.order_id);
            } else {
                try self.state_manager.updateOrder(maker_order.order_id, maker_order.quantity);
            }
        }

        // Handle remaining taker order quantity
        if (remaining_quantity > 0) {
            if (taker_order.order_type == .ImmediateOrCancel) {
                // Cancel remaining quantity for IOC orders
                try self.state_manager.removeOrder(taker_order.order_id);
            } else {
                // Update taker order with remaining quantity
                try self.state_manager.updateOrder(taker_order.order_id, remaining_quantity);
            }
        }
    }

    fn recordMatch(self: *Self, match: OrderMatch) !void {
        // Add match to state
        try self.state_manager.addMatch(match);

        // Emit trade event
        try self.emitEvent("Trade", std.mem.asBytes(&match));
    }

    fn calculateFee(self: *Self, quantity: u64, price: u64, is_maker: bool) u64 {
        const total_value = quantity * price;
        const fee_rate = if (is_maker)
            self.state.fee_rate_bps / 2 // Maker pays half the fee
        else
            self.state.fee_rate_bps;
        return (total_value * fee_rate) / 10000;
    }

    fn validateTokenBalance(self: *Self, owner: Pubkey, side: Side, amount: u64) !void {
        const token_account = if (side == .Bid)
            try self.getQuoteTokenAccount(owner)
        else
            try self.getBaseTokenAccount(owner);

        if (token_account.amount < amount) {
            return ProcessorError.InsufficientFunds;
        }
    }

    fn transferBaseTokens(self: *Self, from: Pubkey, to: Pubkey, amount: u64) !void {
        const from_account = try self.getBaseTokenAccount(from);
        const to_account = try self.getBaseTokenAccount(to);

        if (from_account.amount < amount) {
            return ProcessorError.InsufficientFunds;
        }

        try self.state_manager.updateTokenAccount(
            from_account.address,
            .{ .amount = from_account.amount - amount },
        );

        try self.state_manager.updateTokenAccount(
            to_account.address,
            .{ .amount = to_account.amount + amount },
        );

        try self.emitEvent("BaseTokenTransfer", std.mem.asBytes(&.{
            .from = from,
            .to = to,
            .amount = amount,
        }));
    }

    fn transferQuoteTokens(self: *Self, from: Pubkey, to: Pubkey, amount: u64) !void {
        const from_account = try self.getQuoteTokenAccount(from);
        const to_account = try self.getQuoteTokenAccount(to);

        if (from_account.amount < amount) {
            return ProcessorError.InsufficientFunds;
        }

        try self.state_manager.updateTokenAccount(
            from_account.address,
            .{ .amount = from_account.amount - amount },
        );

        try self.state_manager.updateTokenAccount(
            to_account.address,
            .{ .amount = to_account.amount + amount },
        );

        try self.emitEvent("QuoteTokenTransfer", std.mem.asBytes(&.{
            .from = from,
            .to = to,
            .amount = amount,
        }));
    }

    fn getBaseTokenAccount(self: *Self, owner: Pubkey) !TokenAccount {
        return self.state_manager.getTokenAccount(owner, self.state.base_mint) orelse
            ProcessorError.TokenAccountNotFound;
    }

    fn getQuoteTokenAccount(self: *Self, owner: Pubkey) !TokenAccount {
        return self.state_manager.getTokenAccount(owner, self.state.quote_mint) orelse
            ProcessorError.TokenAccountNotFound;
    }

    fn emitEvent(self: *Self, event_type: []const u8, data: []const u8) !void {
        _ = self;
        _ = event_type;
        _ = data;
        // Implement event emission
    }
};
