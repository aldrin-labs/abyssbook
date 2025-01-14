const std = @import("std");
const instructions = @import("instructions.zig");
const orderbook = @import("orderbook.zig");

pub const ZigBookVM = struct {
    registers: [11]u64,
    memory: []u8,
    program: []const instructions.Instruction,
    pc: usize,
    orderbook: orderbook.ShardedOrderbook,
    best_bid: u64,
    best_ask: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, program: []const instructions.Instruction, shard_count: usize) !ZigBookVM {
        return ZigBookVM{
            .registers = [_]u64{0} ** 11,
            .memory = try allocator.alloc(u8, 1024),
            .program = program,
            .pc = 0,
            .orderbook = try orderbook.ShardedOrderbook.init(allocator, shard_count),
            .best_bid = 0,
            .best_ask = std.math.maxInt(u64),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ZigBookVM) void {
        self.allocator.free(self.memory);
        self.orderbook.deinit();
    }

    pub fn run(self: *ZigBookVM) !void {
        while (self.pc < self.program.len) : (self.pc += 1) {
            try self.execute(self.program[self.pc]);
        }
    }

    pub fn execute(self: *ZigBookVM, instruction: instructions.Instruction) !void {
        switch (instruction) {
            .Load => |load| {
                self.registers[load.reg] = load.value;
            },
            .Add => |add| {
                self.registers[add.dest] = self.registers[add.src1] + self.registers[add.src2];
            },
            .Sub => |sub| {
                self.registers[sub.dest] = self.registers[sub.src1] - self.registers[sub.src2];
            },
            .Mul => |mul| {
                self.registers[mul.dest] = self.registers[mul.src1] * self.registers[mul.src2];
            },
            .Div => |div| {
                self.registers[div.dest] = self.registers[div.src1] / self.registers[div.src2];
            },
            .PlaceOrderOptimized => |place| {
                const price = self.registers[place.price_reg];
                const amount = self.registers[place.amount_reg];
                const id = self.registers[place.id_reg];
                try self.orderbook.placeOrder(price, amount, id);
                self.updateBestBidAsk(price, amount);
            },
            .MatchOrdersInShard => |match_shard| {
                const shard_id = @as(usize, @intCast(self.registers[match_shard.shard_reg]));
                try self.matchOrdersInShard(shard_id);
            },
            .CrossShardMatch => |cross| {
                const shard1 = @as(usize, @intCast(self.registers[cross.shard1_reg]));
                const shard2 = @as(usize, @intCast(self.registers[cross.shard2_reg]));
                try self.crossShardMatch(shard1, shard2);
            },
            .UpdateBestBidAsk => {
                try self.updateBestBidAskFull();
            },
            .VectorizedPriceCheck => |check| {
                const start = self.registers[check.start_reg];
                const end = self.registers[check.end_reg];
                const shard = @as(usize, @intCast(self.registers[check.shard_reg]));
                const result = try self.vectorizedPriceCheck(start, end, shard);
                self.registers[check.result_reg] = result;
            },
        }
    }

    fn updateBestBidAsk(self: *ZigBookVM, price: u64, amount: u64) void {
        if (amount > 0) {
            self.best_bid = @max(self.best_bid, price);
        } else {
            self.best_ask = @min(self.best_ask, price);
        }
    }

    fn updateBestBidAskFull(self: *ZigBookVM) !void {
        for (self.orderbook.shards) |*shard| {
            var it = shard.iterator();
            while (it.next()) |entry| {
                const price = entry.key_ptr.*;
                const amount = entry.value_ptr.amount;
                self.updateBestBidAsk(price, amount);
            }
        }
    }

    fn matchOrdersInShard(self: *ZigBookVM, shard_id: usize) !void {
        var matched = std.ArrayList(u64).init(self.allocator);
        defer matched.deinit();

        var it = self.orderbook.shards[shard_id].iterator();
        while (it.next()) |entry| {
            const price = entry.key_ptr.*;
            const amount = entry.value_ptr.amount;
            if (amount > 0) {
                try matched.append(price);
            }
        }

        for (matched.items) |price| {
            _ = self.orderbook.shards[shard_id].remove(price);
        }
    }

    fn crossShardMatch(self: *ZigBookVM, shard1: usize, shard2: usize) !void {
        var matched = std.ArrayList(u64).init(self.allocator);
        defer matched.deinit();

        var it = self.orderbook.shards[shard1].iterator();
        while (it.next()) |entry| {
            const price = entry.key_ptr.*;
            if (self.orderbook.shards[shard2].get(price)) |order2| {
                if (entry.value_ptr.amount > 0 and order2.amount > 0) {
                    try matched.append(price);
                }
            }
        }

        for (matched.items) |price| {
            _ = self.orderbook.shards[shard1].remove(price);
            _ = self.orderbook.shards[shard2].remove(price);
        }
    }

    fn vectorizedPriceCheck(self: *ZigBookVM, start: u64, end: u64, shard: usize) !u64 {
        var total: u64 = 0;
        var it = self.orderbook.shards[shard].iterator();
        while (it.next()) |entry| {
            const price = entry.key_ptr.*;
            if (price >= start and price <= end) {
                total += entry.value_ptr.amount;
            }
        }
        return total;
    }
};
