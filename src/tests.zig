const std = @import("std");
const testing = std.testing;
const vm = @import("vm.zig");
const instructions = @import("instructions.zig");
const orderbook = @import("orderbook.zig");
const market = @import("market.zig");
const fees = @import("fees.zig");

// ... existing tests ...

test "fee structure" {
    var allocator = testing.allocator;

    const volume_tiers = [_]fees.FeeLevel{
        .{ .volume_threshold = 0, .base_fee_bps = 50 }, // 0.5%
        .{ .volume_threshold = 10000, .base_fee_bps = 40 }, // 0.4%
        .{ .volume_threshold = 100000, .base_fee_bps = 30 }, // 0.3%
    };

    const nft_config = fees.NftStakingConfig{
        .enabled = true,
        .discount_bps = 10,
        .min_stake_time = 86400, // 24 hours
    };

    const lp_tiers = [_]fees.LpDiscountTier{
        .{ .lp_amount_threshold = 1000, .discount_bps = 5 },
        .{ .lp_amount_threshold = 10000, .discount_bps = 10 },
        .{ .lp_amount_threshold = 100000, .discount_bps = 20 },
    };

    var test_market = try market.Market.init(
        allocator,
        8,
        &volume_tiers,
        nft_config,
        &lp_tiers,
    );
    defer test_market.deinit();

    // Test base fee
    try test_market.placeOrder(1, 100, 1000, 1);
    try testing.expectEqual(@as(u64, 5), test_market.calculateUserFee(1, 1000)); // 0.5%

    // Test volume discount
    try test_market.updateUserVolume(1, 20000);
    try testing.expectEqual(@as(u64, 4), test_market.calculateUserFee(1, 1000)); // 0.4%

    // Test NFT staking discount
    try test_market.stakeNft(1, std.time.timestamp() - 100000);
    try testing.expectEqual(@as(u64, 3), test_market.calculateUserFee(1, 1000)); // 0.3%

    // Test LP discount
    try test_market.provideLiquidity(1, 100000);
    try testing.expectEqual(@as(u64, 1), test_market.calculateUserFee(1, 1000)); // 0.1%
}