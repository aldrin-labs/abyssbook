const std = @import("std");
const orderbook = @import("orderbook.zig");
const fees = @import("fees.zig");

pub const Market = struct {
    orderbook: orderbook.ShardedOrderbook,
    fee_structure: fees.FeeStructure,
    user_volumes: std.AutoHashMap(u64, u64), // user_id -> volume
    nft_stakes: std.AutoHashMap(u64, u64), // user_id -> stake timestamp
    lp_amounts: std.AutoHashMap(u64, u64), // user_id -> LP amount
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        shard_count: usize,
        volume_tiers: []const fees.FeeLevel,
        nft_config: fees.NftStakingConfig,
        lp_tiers: []const fees.LpDiscountTier,
    ) !Market {
        return Market{
            .orderbook = try orderbook.ShardedOrderbook.init(allocator, shard_count),
            .fee_structure = try fees.FeeStructure.init(allocator, volume_tiers, nft_config, lp_tiers),
            .user_volumes = std.AutoHashMap(u64, u64).init(allocator),
            .nft_stakes = std.AutoHashMap(u64, u64).init(allocator),
            .lp_amounts = std.AutoHashMap(u64, u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Market) void {
        self.orderbook.deinit();
        self.fee_structure.deinit();
        self.user_volumes.deinit();
        self.nft_stakes.deinit();
        self.lp_amounts.deinit();
    }

    pub fn placeOrder(self: *Market, user_id: u64, price: u64, amount: u64, id: u64) !void {
        const fee = self.calculateUserFee(user_id, amount);
        const net_amount = amount - fee;

        try self.orderbook.placeOrder(price, net_amount, id);
        try self.updateUserVolume(user_id, amount);
    }

    pub fn stakeNft(self: *Market, user_id: u64, timestamp: u64) !void {
        if (!self.fee_structure.nft_staking.enabled) {
            return error.NftStakingDisabled;
        }
        try self.nft_stakes.put(user_id, timestamp);
    }

    pub fn unstakeNft(self: *Market, user_id: u64) void {
        _ = self.nft_stakes.remove(user_id);
    }

    pub fn provideLiquidity(self: *Market, user_id: u64, amount: u64) !void {
        const current = self.lp_amounts.get(user_id) orelse 0;
        try self.lp_amounts.put(user_id, current + amount);
    }

    pub fn removeLiquidity(self: *Market, user_id: u64, amount: u64) !void {
        const current = self.lp_amounts.get(user_id) orelse return error.InsufficientLiquidity;
        if (current < amount) return error.InsufficientLiquidity;
        try self.lp_amounts.put(user_id, current - amount);
    }

    fn calculateUserFee(self: *Market, user_id: u64, amount: u64) u64 {
        const volume = self.user_volumes.get(user_id) orelse 0;
        const has_staked_nft = self.nft_stakes.contains(user_id);
        const stake_time = if (has_staked_nft) self.nft_stakes.get(user_id) else null;
        const lp_amount = self.lp_amounts.get(user_id) orelse 0;

        return self.fee_structure.calculateFee(
            amount,
            volume,
            has_staked_nft,
            stake_time,
            lp_amount,
        );
    }

    fn updateUserVolume(self: *Market, user_id: u64, amount: u64) !void {
        const current = self.user_volumes.get(user_id) orelse 0;
        try self.user_volumes.put(user_id, current + amount);
    }
};