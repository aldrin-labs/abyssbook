const std = @import("std");
const BlockchainClient = @import("../blockchain/client.zig").BlockchainClient;
const Orderbook = @import("../blockchain/client.zig").Orderbook;

/// TUIService provides data for the text-based user interface
pub const TUIService = struct {
    allocator: std.mem.Allocator,
    client: BlockchainClient,
    default_market: []const u8,

    /// Initialize a new TUI service
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !TUIService {
        const client = try BlockchainClient.init(allocator, api_key, base_url);

        return TUIService{
            .allocator = allocator,
            .client = client,
            .default_market = try allocator.dupe(u8, "SOL/USDC"),
        };
    }

    /// Get the current orderbook data
    pub fn getOrderbook(self: *TUIService) !Orderbook {
        return try self.client.getOrderbook(self.default_market);
    }

    /// Calculate the spread between best bid and ask
    pub fn calculateSpread(_: *TUIService, orderbook: Orderbook) !f64 {
        if (orderbook.asks.len == 0 or orderbook.bids.len == 0) {
            return error.InsufficientOrderbookData;
        }

        // Find the best bid and ask prices
        var best_bid: f64 = 0;
        var best_ask: f64 = std.math.inf(f64);

        for (orderbook.bids) |bid| {
            if (bid.price > best_bid) {
                best_bid = bid.price;
            }
        }

        for (orderbook.asks) |ask| {
            if (ask.price < best_ask) {
                best_ask = ask.price;
            }
        }

        return best_ask - best_bid;
    }

    /// Deinitialize the service and free resources
    pub fn deinit(self: *TUIService) void {
        self.client.deinit();
        self.allocator.free(self.default_market);
    }
};
