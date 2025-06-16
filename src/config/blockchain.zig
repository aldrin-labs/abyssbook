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
        // In a real implementation, this would load from a config file or environment variables
        // For now, we'll return default values
        
        const api_key = try allocator.dupe(u8, "YOUR_API_KEY");
        const base_url = try allocator.dupe(u8, "https://ny.solana.dex.blxrbdn.com");
        
        return BlockchainConfig{
            .api_key = api_key,
            .base_url = base_url,
            .network = .mainnet,
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
