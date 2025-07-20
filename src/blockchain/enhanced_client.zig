const std = @import("std");
const BlockchainClient = @import("../blockchain/client.zig").BlockchainClient;
const OrderbookCache = @import("../cache/orderbook.zig").OrderbookCache;
const ErrorHandler = @import("../blockchain/error.zig").ErrorHandler;
const BlockchainError = @import("../blockchain/error.zig").BlockchainError;

/// Enhanced blockchain client with caching and error handling
pub const EnhancedBlockchainClient = struct {
    allocator: std.mem.Allocator,
    client: BlockchainClient,
    cache: OrderbookCache,
    error_handler: ErrorHandler,
    
    /// Initialize a new enhanced blockchain client
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !EnhancedBlockchainClient {
        const client = try BlockchainClient.init(allocator, api_key, base_url);
        const cache = try OrderbookCache.init(allocator, 5000); // 5 second TTL
        const error_handler = ErrorHandler.init(3, 500); // 3 retries, 500ms base delay
        
        return EnhancedBlockchainClient{
            .allocator = allocator,
            .client = client,
            .cache = cache,
            .error_handler = error_handler,
        };
    }
    
    /// Get orderbook data with caching and error handling
    pub fn getOrderbook(self: *EnhancedBlockchainClient, market: []const u8) !Orderbook {
        // Check cache first
        if (self.cache.get(market)) |cached_orderbook| {
            std.debug.print("Using cached orderbook data for market {s}\n", .{market});
            return cached_orderbook;
        }
        
        // Cache miss, fetch from blockchain with retry logic
        const Context = struct {
            client: *BlockchainClient,
            market: []const u8,
        };
        
        const context = Context{
            .client = &self.client,
            .market = market,
        };
        
        const fetchOrderbook = struct {
            fn call(ctx: Context) BlockchainError!Orderbook {
                return ctx.client.getOrderbook(ctx.market) catch |err| {
                    // Convert std.Error to BlockchainError
                    switch (err) {
                        error.NetworkError => return BlockchainError.NetworkError,
                        error.ConnectionFailed => return BlockchainError.ConnectionFailed,
                        error.ApiRequestFailed => return BlockchainError.ApiRequestFailed,
                        else => return BlockchainError.UnknownError,
                    }
                };
            }
        }.call;
        
        // Execute with retry logic
        const orderbook = try self.error_handler.executeWithRetry(Orderbook, context, fetchOrderbook);
        
        // Cache the result
        try self.cache.put(market, orderbook);
        
        return orderbook;
    }
    
    /// Deinitialize the client and free resources
    pub fn deinit(self: *EnhancedBlockchainClient) void {
        self.client.deinit();
        self.cache.deinit();
    }
};

// Re-export Orderbook type
pub const Orderbook = @import("../blockchain/client.zig").Orderbook;
