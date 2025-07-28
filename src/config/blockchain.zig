const std = @import("std");

/// BlockchainConfig stores configuration for blockchain connections
pub const BlockchainConfig = struct {
    api_key: []const u8,
    base_url: []const u8,
    network: Network,

    /// Network options for blockchain connections
    pub const Network = enum {
        mainnet,
        testnet,
        devnet,
    };

    /// Load configuration from environment or config file
    pub fn load(allocator: std.mem.Allocator) !BlockchainConfig {
        // Try to load from environment variables first
        const api_key = std.process.getEnvVarOwned(allocator, "ABYSSBOOK_API_KEY") catch blk: {
            // Fall back to config file or default testing values
            std.debug.print("Warning: ABYSSBOOK_API_KEY environment variable not found\n", .{});
            std.debug.print("Using default API key for testing. Set ABYSSBOOK_API_KEY for production.\n", .{});
            break :blk try allocator.dupe(u8, "test_api_key_please_set_environment_variable");
        };

        const base_url = std.process.getEnvVarOwned(allocator, "ABYSSBOOK_BASE_URL") catch blk: {
            // Use default bloXroute endpoint
            std.debug.print("Using default bloXroute Solana endpoint\n", .{});
            break :blk try allocator.dupe(u8, "https://ny.solana.dex.blxrbdn.com");
        };

        // Determine network from environment or default to mainnet
        const network_str = std.process.getEnvVarOwned(allocator, "ABYSSBOOK_NETWORK") catch blk: {
            break :blk null;
        };
        defer if (network_str) |ns| allocator.free(ns);

        const network = if (network_str) |ns| blk: {
            if (std.mem.eql(u8, ns, "testnet")) {
                break :blk Network.testnet;
            } else if (std.mem.eql(u8, ns, "devnet")) {
                break :blk Network.devnet;
            } else {
                break :blk Network.mainnet;
            }
        } else Network.mainnet;

        return BlockchainConfig{
            .api_key = api_key,
            .base_url = base_url,
            .network = network,
        };
    }

    /// Get the network name as a string
    pub fn getNetworkName(self: BlockchainConfig) []const u8 {
        return switch (self.network) {
            .mainnet => "mainnet",
            .testnet => "testnet",
            .devnet => "devnet",
        };
    }

    /// Free resources
    pub fn deinit(self: *BlockchainConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.api_key);
        allocator.free(self.base_url);
    }
};
