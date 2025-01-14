const std = @import("std");

pub const FeeLevel = struct {
    volume_threshold: u64,
    base_fee_bps: u16, // basis points (1/100th of 1%)
};

pub const NftStakingConfig = struct {
    enabled: bool,
    discount_bps: u16,
    min_stake_time: u64, // minimum staking duration in seconds
};

pub const LpDiscountTier = struct {
    lp_amount_threshold: u64,
    discount_bps: u16,
};

pub const FeeStructure = struct {
    volume_tiers: []FeeLevel,
    nft_staking: NftStakingConfig,
    lp_tiers: []LpDiscountTier,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        volume_tiers: []const FeeLevel,
        nft_config: NftStakingConfig,
        lp_tiers: []const LpDiscountTier,
    ) !FeeStructure {
        var fee_tiers = try allocator.dupe(FeeLevel, volume_tiers);
        var lp_discount_tiers = try allocator.dupe(LpDiscountTier, lp_tiers);

        // Sort tiers by thresholds
        std.sort.sort(FeeLevel, fee_tiers, {}, struct {
            fn lessThan(_: void, a: FeeLevel, b: FeeLevel) bool {
                return a.volume_threshold < b.volume_threshold;
            }
        }.lessThan);

        std.sort.sort(LpDiscountTier, lp_discount_tiers, {}, struct {
            fn lessThan(_: void, a: LpDiscountTier, b: LpDiscountTier) bool {
                return a.lp_amount_threshold < b.lp_amount_threshold;
            }
        }.lessThan);

        return FeeStructure{
            .volume_tiers = fee_tiers,
            .nft_staking = nft_config,
            .lp_tiers = lp_discount_tiers,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FeeStructure) void {
        self.allocator.free(self.volume_tiers);
        self.allocator.free(self.lp_tiers);
    }

    pub fn calculateFee(
        self: *const FeeStructure,
        trade_amount: u64,
        user_volume: u64,
        staked_nft: bool,
        nft_stake_time: ?u64,
        lp_amount: u64,
    ) u64 {
        // Start with base fee from volume tier
        var base_fee_bps = self.getVolumeTierFee(user_volume);

        // Apply NFT staking discount if enabled and conditions met
        if (self.nft_staking.enabled and staked_nft) {
            if (nft_stake_time) |stake_time| {
                if (stake_time >= self.nft_staking.min_stake_time) {
                    base_fee_bps = self.applyDiscount(base_fee_bps, self.nft_staking.discount_bps);
                }
            }
        }

        // Apply LP amount discount
        const lp_discount = self.getLpDiscount(lp_amount);
        base_fee_bps = self.applyDiscount(base_fee_bps, lp_discount);

        // Calculate final fee amount
        return (trade_amount * base_fee_bps) / 10000;
    }

    fn getVolumeTierFee(self: *const FeeStructure, volume: u64) u16 {
        var base_fee_bps: u16 = self.volume_tiers[0].base_fee_bps;

        for (self.volume_tiers) |tier| {
            if (volume >= tier.volume_threshold) {
                base_fee_bps = tier.base_fee_bps;
            } else {
                break;
            }
        }

        return base_fee_bps;
    }

    fn getLpDiscount(self: *const FeeStructure, lp_amount: u64) u16 {
        var discount: u16 = 0;

        for (self.lp_tiers) |tier| {
            if (lp_amount >= tier.lp_amount_threshold) {
                discount = tier.discount_bps;
            } else {
                break;
            }
        }

        return discount;
    }

    fn applyDiscount(self: *const FeeStructure, base_bps: u16, discount_bps: u16) u16 {
        return if (discount_bps >= base_bps) 0 else base_bps - discount_bps;
    }
};