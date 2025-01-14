const std = @import("std");
const Pubkey = @import("processor.zig").Pubkey;
const Order = @import("order.zig").Order;
const Side = @import("order.zig").Side;
const OrderMatch = @import("match.zig").OrderMatch;
const TokenAccount = @import("token.zig").TokenAccount;

pub const StateManager = struct {
    // Memory allocator
    allocator: std.mem.Allocator,
    // Next order ID
    next_order_id: u64,
    // Next match ID
    next_match_id: u64,
    // Orders by ID
    orders: std.AutoHashMap(u64, Order),
    // Matches by ID
    matches: std.AutoHashMap(u64, OrderMatch),
    // Token accounts by owner and mint
    token_accounts: std.AutoHashMap(struct { owner: Pubkey, mint: Pubkey }, TokenAccount),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .next_order_id = 1,
            .next_match_id = 1,
            .orders = std.AutoHashMap(u64, Order).init(allocator),
            .matches = std.AutoHashMap(u64, OrderMatch).init(allocator),
            .token_accounts = std.AutoHashMap(
                struct { owner: Pubkey, mint: Pubkey },
                TokenAccount,
            ).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.orders.deinit();
        self.matches.deinit();
        self.token_accounts.deinit();
    }

    pub fn clear(self: *Self) void {
        self.orders.clearRetainingCapacity();
        self.matches.clearRetainingCapacity();
        self.token_accounts.clearRetainingCapacity();
        self.next_order_id = 1;
        self.next_match_id = 1;
    }

    pub fn getNextOrderId(self: *Self) u64 {
        const id = self.next_order_id;
        self.next_order_id += 1;
        return id;
    }

    pub fn getNextMatchId(self: *Self) u64 {
        const id = self.next_match_id;
        self.next_match_id += 1;
        return id;
    }

    pub fn addOrder(self: *Self, order: Order) !void {
        try self.orders.put(order.order_id, order);
    }

    pub fn getOrder(self: *Self, order_id: u64) ?Order {
        return self.orders.get(order_id);
    }

    pub fn removeOrder(self: *Self, order_id: u64) void {
        _ = self.orders.remove(order_id);
    }

    pub fn updateOrder(self: *Self, order_id: u64, quantity: u64) !void {
        if (self.orders.getPtr(order_id)) |order| {
            order.quantity = quantity;
        }
    }

    pub fn getAllOrders(self: *Self) []const Order {
        var orders = std.ArrayList(Order).init(self.allocator);
        var it = self.orders.valueIterator();
        while (it.next()) |order| {
            orders.append(order.*) catch continue;
        }
        return orders.toOwnedSlice();
    }

    pub fn getOrdersSorted(self: *Self, side: Side) !std.ArrayList(Order) {
        var orders = std.ArrayList(Order).init(self.allocator);
        errdefer orders.deinit();

        var it = self.orders.valueIterator();
        while (it.next()) |order| {
            if (order.side == side) {
                try orders.append(order.*);
            }
        }

        // Sort by price (ascending for asks, descending for bids)
        const sort_fn = if (side == .Ask)
            struct {
                fn lessThan(_: void, a: Order, b: Order) bool {
                    return a.price < b.price;
                }
            }.lessThan
        else
            struct {
                fn lessThan(_: void, a: Order, b: Order) bool {
                    return a.price > b.price;
                }
            }.lessThan;

        std.sort.insertion(Order, orders.items, {}, sort_fn);
        return orders;
    }

    pub fn addMatch(self: *Self, match: OrderMatch) !void {
        try self.matches.put(match.match_id, match);
    }

    pub fn getMatch(self: *Self, match_id: u64) ?OrderMatch {
        return self.matches.get(match_id);
    }

    pub fn updateMatch(self: *Self, match_id: u64, updates: struct { is_settled: bool }) !void {
        if (self.matches.getPtr(match_id)) |match| {
            match.is_settled = updates.is_settled;
        }
    }

    pub fn getMatches(self: *Self) []const OrderMatch {
        var matches = std.ArrayList(OrderMatch).init(self.allocator);
        var it = self.matches.valueIterator();
        while (it.next()) |match| {
            matches.append(match.*) catch continue;
        }
        return matches.toOwnedSlice();
    }

    pub fn addTokenAccount(self: *Self, token_account: TokenAccount) !void {
        try self.token_accounts.put(
            .{ .owner = token_account.owner, .mint = token_account.mint },
            token_account,
        );
    }

    pub fn getTokenAccount(self: *Self, owner: Pubkey, mint: Pubkey) ?TokenAccount {
        return self.token_accounts.get(.{ .owner = owner, .mint = mint });
    }

    pub fn updateTokenAccount(self: *Self, address: Pubkey, updates: struct { amount: u64 }) !void {
        if (self.token_accounts.getPtr(address)) |account| {
            account.amount = updates.amount;
        }
    }
};
