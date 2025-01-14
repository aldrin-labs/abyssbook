const std = @import("std");
const instruction = @import("instruction.zig");
const OrderbookState = instruction.OrderbookState;
const Order = instruction.Order;

pub const StateError = error{
    InvalidAccountData,
    InvalidDataSize,
    InvalidOwner,
    AccountNotInitialized,
};

pub const StateManager = struct {
    // Constants for account sizes
    pub const STATE_SIZE = @sizeOf(OrderbookState);
    pub const ORDER_SIZE = @sizeOf(Order);
    pub const MAX_ORDERS = 1024;
    pub const ACCOUNT_SIZE = STATE_SIZE + (ORDER_SIZE * MAX_ORDERS);

    // Account data
    data: []u8,
    // Current state
    state: *OrderbookState,
    // Orders buffer
    orders: []Order,

    const Self = @This();

    pub fn init(account_data: []u8) StateError!Self {
        if (account_data.len < ACCOUNT_SIZE) {
            return StateError.InvalidDataSize;
        }

        const state = @as(*OrderbookState, @ptrCast(@alignCast(account_data.ptr)));
        const orders_ptr = @as([*]Order, @ptrCast(@alignCast(account_data[STATE_SIZE..].ptr)));
        const orders = orders_ptr[0..MAX_ORDERS];

        return Self{
            .data = account_data,
            .state = state,
            .orders = orders,
        };
    }

    pub fn load(self: *Self) StateError!void {
        if (!self.state.is_initialized) {
            return StateError.AccountNotInitialized;
        }
    }

    pub fn save(self: *Self) StateError!void {
        if (self.data.len < ACCOUNT_SIZE) {
            return StateError.InvalidDataSize;
        }

        // Update state in account data
        @memcpy(self.data[0..STATE_SIZE], std.mem.asBytes(self.state));

        // Update orders in account data
        const orders_data = std.mem.sliceAsBytes(self.orders);
        @memcpy(self.data[STATE_SIZE..][0..orders_data.len], orders_data);
    }

    pub fn addOrder(self: *Self, order: Order) StateError!void {
        // Find empty slot
        for (self.orders, 0..) |*slot, i| {
            if (slot.order_id == 0) {
                self.orders[i] = order;
                return;
            }
        }
        return StateError.InvalidDataSize; // No empty slots
    }

    pub fn removeOrder(self: *Self, order_id: u128) StateError!void {
        // Find and remove order
        for (self.orders) |*order| {
            if (order.order_id == order_id) {
                order.order_id = 0; // Mark as empty
                return;
            }
        }
        return StateError.InvalidAccountData; // Order not found
    }

    pub fn getOrder(self: *Self, order_id: u128) ?Order {
        // Find order by ID
        for (self.orders) |order| {
            if (order.order_id == order_id) {
                return order;
            }
        }
        return null;
    }

    pub fn getOrders(self: *Self, side: instruction.Side) []Order {
        var result = std.ArrayList(Order).init(std.heap.page_allocator);
        defer result.deinit();

        for (self.orders) |order| {
            if (order.order_id != 0 and order.side == side) {
                result.append(order) catch continue;
            }
        }

        return result.toOwnedSlice() catch &[_]Order{};
    }

    pub fn updateOrder(self: *Self, order_id: u128, new_quantity: u64) StateError!void {
        for (self.orders) |*order| {
            if (order.order_id == order_id) {
                order.quantity = new_quantity;
                return;
            }
        }
        return StateError.InvalidAccountData;
    }

    pub fn clear(self: *Self) void {
        for (self.orders) |*order| {
            order.order_id = 0;
        }
        self.state.is_initialized = false;
    }

    // Helper functions for state transitions
    pub fn validateTransition(self: *Self, new_state: OrderbookState) StateError!void {
        _ = self;
        _ = new_state;
        // Add state transition validation logic
    }

    pub fn applyTransition(self: *Self, new_state: OrderbookState) StateError!void {
        try self.validateTransition(new_state);
        self.state.* = new_state;
    }
};
