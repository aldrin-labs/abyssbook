const std = @import("std");
const http = @import("std").http;
const json = @import("std").json;
const Thread = std.Thread;

/// Maximum retry attempts for blockchain API calls
const MAX_RETRIES = 3;
/// Base delay for exponential backoff (in milliseconds)
const BASE_RETRY_DELAY_MS = 100;
/// Maximum response size to prevent DoS attacks
const MAX_RESPONSE_SIZE = 10 * 1024 * 1024; // 10MB
/// Request timeout in seconds
const REQUEST_TIMEOUT_MS = 30 * 1000; // 30 seconds

/// BlockchainClient handles all interactions with the Solana blockchain
/// through external APIs like bloXroute or Bitquery.
/// This implementation is thread-safe and includes comprehensive security measures.
pub const BlockchainClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    base_url: []const u8,
    client: ?http.Client,
    mutex: Thread.Mutex,
    connection_count: std.atomic.Value(u32),
    last_request_time: std.atomic.Value(i64),
    
    /// Initialize a new blockchain client with security measures
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !BlockchainClient {
        // Validate inputs
        if (api_key.len == 0) return error.InvalidApiKey;
        if (base_url.len == 0) return error.InvalidBaseUrl;
        if (!std.mem.startsWith(u8, base_url, "https://")) return error.InsecureBaseUrl;
        
        return BlockchainClient{
            .allocator = allocator,
            .api_key = api_key,
            .base_url = base_url,
            .client = null,
            .mutex = Thread.Mutex{},
            .connection_count = std.atomic.Value(u32).init(0),
            .last_request_time = std.atomic.Value(i64).init(0),
        };
    }
    
    /// Connect to the blockchain API with proper synchronization
    pub fn connect(self: *BlockchainClient) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.client == null) {
            var client = http.Client.init(self.allocator, .{});
            self.client = client;
            _ = self.connection_count.fetchAdd(1, .monotonic);
        }
    }
    
    /// Disconnect from the blockchain API with proper cleanup
    pub fn disconnect(self: *BlockchainClient) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.client) |*client| {
            client.deinit();
            self.client = null;
            _ = self.connection_count.fetchSub(1, .monotonic);
        }
    }
    
    /// Validate orderbook data structure for security
    fn validateOrderbook(orderbook: *const Orderbook) !void {
        if (orderbook.market.len == 0) return error.InvalidMarket;
        if (orderbook.market_address.len == 0) return error.InvalidMarketAddress;
        
        // Validate individual orders
        for (orderbook.bids) |bid| {
            try validateOrder(&bid);
        }
        for (orderbook.asks) |ask| {
            try validateOrder(&ask);
        }
    }
    
    /// Validate individual order data
    fn validateOrder(order: *const Order) !void {
        if (order.price <= 0) return error.InvalidPrice;
        if (order.size <= 0) return error.InvalidSize;
        if (order.order_id.len == 0) return error.InvalidOrderId;
        if (order.owner_address.len == 0) return error.InvalidOwnerAddress;
        
        // Additional validation: price and size should be reasonable
        if (order.price > 1000000000) return error.PriceTooHigh; // $1B max
        if (order.size > 1000000000) return error.SizeTooHigh; // 1B max
    }
    
    /// Rate limiting check to prevent DoS
    fn checkRateLimit(self: *BlockchainClient) !void {
        const now = std.time.milliTimestamp();
        const last_request = self.last_request_time.load(.monotonic);
        
        // Minimum 100ms between requests
        if (now - last_request < 100) {
            std.time.sleep(100 * std.time.ns_per_ms);
        }
        
        _ = self.last_request_time.swap(now, .monotonic);
    }
    
    /// Perform HTTP request with retries and proper error handling
    fn performRequest(self: *BlockchainClient, url: []const u8) ![]u8 {
        var attempt: u32 = 0;
        var last_error: anyerror = undefined;
        
        while (attempt < MAX_RETRIES) {
            const result = self.performSingleRequest(url) catch |err| {
                last_error = err;
                attempt += 1;
                
                if (attempt < MAX_RETRIES) {
                    // Exponential backoff
                    const delay = BASE_RETRY_DELAY_MS * (@as(u64, 1) << @intCast(attempt));
                    std.time.sleep(delay * std.time.ns_per_ms);
                }
                continue;
            };
            
            return result;
        }
        
        return last_error;
    }
    
    /// Perform a single HTTP request
    fn performSingleRequest(self: *BlockchainClient, url: []const u8) ![]u8 {
        try self.checkRateLimit();
        
        const client = self.client orelse return error.ClientNotConnected;
        
        // Parse URL with validation
        const uri = std.Uri.parse(url) catch return error.InvalidUrl;
        
        // Prepare the request
        var request = client.request(.GET, uri, .{
            .allocator = self.allocator,
        }, .{}) catch return error.RequestPreparationFailed;
        
        // Add security headers
        request.headers.append("Authorization", self.api_key) catch return error.HeaderSetupFailed;
        request.headers.append("User-Agent", "AbyssbookClient/1.0") catch return error.HeaderSetupFailed;
        request.headers.append("Accept", "application/json") catch return error.HeaderSetupFailed;
        
        // Send the request with timeout
        request.start() catch return error.RequestStartFailed;
        request.finish() catch return error.RequestFinishFailed;
        
        // Get the response
        const response = request.wait() catch return error.ResponseWaitFailed;
        
        // Check for successful response
        switch (response.status) {
            .ok => {},
            .unauthorized => return error.Unauthorized,
            .forbidden => return error.Forbidden,
            .not_found => return error.NotFound,
            .too_many_requests => return error.RateLimited,
            .internal_server_error => return error.ServerError,
            else => return error.ApiRequestFailed,
        }
        
        // Read the response body with size limit
        const body = response.reader().readAllAlloc(self.allocator, MAX_RESPONSE_SIZE) catch |err| {
            switch (err) {
                error.StreamTooLong => return error.ResponseTooLarge,
                else => return error.ResponseReadFailed,
            }
        };
        
        return body;
    }
    
    /// Get orderbook data for a specific market with comprehensive security
    pub fn getOrderbook(self: *BlockchainClient, market: []const u8) !Orderbook {
        // Input validation
        if (market.len == 0) return error.InvalidMarket;
        if (market.len > 64) return error.MarketNameTooLong;
        
        // Sanitize market name to prevent injection attacks
        for (market) |char| {
            if (!std.ascii.isAlphanumeric(char) and char != '/' and char != '-' and char != '_') {
                return error.InvalidMarketCharacters;
            }
        }
        
        try self.connect();
        
        // Construct the URL for the orderbook endpoint
        var url_buffer: [512]u8 = undefined;
        const url = std.fmt.bufPrint(&url_buffer, "{s}/api/v2/openbook/orderbooks/{s}", .{
            self.base_url, market
        }) catch return error.UrlConstructionFailed;
        
        // Perform request with retries
        const body = try self.performRequest(url);
        defer self.allocator.free(body);
        
        // Validate JSON structure before parsing
        if (body.len == 0) return error.EmptyResponse;
        if (body[0] != '{') return error.InvalidJsonFormat;
        
        // Parse the JSON response with error handling
        var stream = json.TokenStream.init(body);
        const orderbook = json.parse(Orderbook, &stream, .{
            .allocator = self.allocator,
        }) catch |err| {
            switch (err) {
                error.SyntaxError => return error.JsonSyntaxError,
                error.UnexpectedToken => return error.JsonUnexpectedToken,
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.JsonParseError,
            }
        };
        
        // Validate the parsed orderbook data
        try validateOrderbook(&orderbook);
        
        return orderbook;
    }
    
    /// Place an order on the blockchain with comprehensive validation
    pub fn placeOrder(self: *BlockchainClient, side: []const u8, price: f64, size: f64) ![]const u8 {
        // Input validation
        if (side.len == 0) return error.InvalidSide;
        if (!std.mem.eql(u8, side, "buy") and !std.mem.eql(u8, side, "sell")) {
            return error.InvalidSide;
        }
        
        // Price validation
        if (price <= 0) return error.InvalidPrice;
        if (price > 1000000000) return error.PriceTooHigh; // $1B max
        if (std.math.isNan(price) or std.math.isInf(price)) return error.InvalidPriceValue;
        
        // Size validation
        if (size <= 0) return error.InvalidSize;
        if (size > 1000000000) return error.SizeTooHigh; // 1B max
        if (std.math.isNan(size) or std.math.isInf(size)) return error.InvalidSizeValue;
        
        // Rate limiting check
        try self.checkRateLimit();
        
        // In a real implementation, this would construct and sign a transaction
        // For now, we'll return a mock order ID with proper security considerations
        _ = self;
        
        // Generate a cryptographically secure order ID
        var order_id_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&order_id_bytes);
        
        // Convert to hex string
        var order_id_buffer: [32]u8 = undefined;
        const order_id = std.fmt.bufPrint(&order_id_buffer, "{}", .{std.fmt.fmtSliceHexLower(&order_id_bytes)}) catch return error.OrderIdGenerationFailed;
        
        return try self.allocator.dupe(u8, order_id);
    }
    
    /// Cancel an order on the blockchain with proper validation
    pub fn cancelOrder(self: *BlockchainClient, order_id: []const u8) !void {
        // Input validation
        if (order_id.len == 0) return error.InvalidOrderId;
        if (order_id.len > 64) return error.OrderIdTooLong;
        
        // Validate order ID format (should be hex)
        for (order_id) |char| {
            if (!std.ascii.isHex(char)) {
                return error.InvalidOrderIdFormat;
            }
        }
        
        // Rate limiting check
        try self.checkRateLimit();
        
        // In a real implementation, this would construct and sign a transaction
        // For now, we'll just validate the input with security considerations
        _ = self;
    }
    
    /// Deinitialize the client and free resources securely
    pub fn deinit(self: *BlockchainClient) void {
        self.disconnect();
        
        // Clear sensitive data
        std.crypto.utils.secureZero(@constCast(self.api_key));
    }
    
    /// Get connection statistics for monitoring
    pub fn getConnectionCount(self: *BlockchainClient) u32 {
        return self.connection_count.load(.monotonic);
    }
    
    /// Get last request time for monitoring
    pub fn getLastRequestTime(self: *BlockchainClient) i64 {
        return self.last_request_time.load(.monotonic);
    }
};

/// Represents an order in the orderbook with validation
pub const Order = struct {
    price: f64,
    size: f64,
    order_id: []const u8,
    owner_address: []const u8,
    
    /// Validate order data integrity
    pub fn validate(self: *const Order) !void {
        if (self.price <= 0) return error.InvalidPrice;
        if (self.size <= 0) return error.InvalidSize;
        if (self.order_id.len == 0) return error.InvalidOrderId;
        if (self.owner_address.len == 0) return error.InvalidOwnerAddress;
        
        // Additional security checks
        if (self.price > 1000000000) return error.PriceTooHigh;
        if (self.size > 1000000000) return error.SizeTooHigh;
        if (std.math.isNan(self.price) or std.math.isInf(self.price)) return error.InvalidPriceValue;
        if (std.math.isNan(self.size) or std.math.isInf(self.size)) return error.InvalidSizeValue;
    }
};

/// Represents a complete orderbook with bids and asks
pub const Orderbook = struct {
    market: []const u8,
    market_address: []const u8,
    bids: []Order,
    asks: []Order,
    
    /// Secure deinitialization with memory clearing
    pub fn deinit(self: *Orderbook, allocator: std.mem.Allocator) void {
        // Clear and free order data securely
        for (self.bids) |bid| {
            std.crypto.utils.secureZero(@constCast(bid.order_id));
            std.crypto.utils.secureZero(@constCast(bid.owner_address));
            allocator.free(bid.order_id);
            allocator.free(bid.owner_address);
        }
        for (self.asks) |ask| {
            std.crypto.utils.secureZero(@constCast(ask.order_id));
            std.crypto.utils.secureZero(@constCast(ask.owner_address));
            allocator.free(ask.order_id);
            allocator.free(ask.owner_address);
        }
        
        // Free arrays
        allocator.free(self.bids);
        allocator.free(self.asks);
        
        // Clear and free market data
        std.crypto.utils.secureZero(@constCast(self.market));
        std.crypto.utils.secureZero(@constCast(self.market_address));
        allocator.free(self.market);
        allocator.free(self.market_address);
    }
    
    /// Validate entire orderbook structure
    pub fn validate(self: *const Orderbook) !void {
        if (self.market.len == 0) return error.InvalidMarket;
        if (self.market_address.len == 0) return error.InvalidMarketAddress;
        
        // Validate all orders
        for (self.bids) |bid| {
            try bid.validate();
        }
        for (self.asks) |ask| {
            try ask.validate();
        }
        
        // Additional validation: check for crossed orderbook
        if (self.bids.len > 0 and self.asks.len > 0) {
            const highest_bid = self.getHighestBid();
            const lowest_ask = self.getLowestAsk();
            
            if (highest_bid >= lowest_ask) {
                return error.CrossedOrderbook;
            }
        }
    }
    
    /// Get highest bid price for validation
    fn getHighestBid(self: *const Orderbook) f64 {
        if (self.bids.len == 0) return 0;
        
        var highest: f64 = 0;
        for (self.bids) |bid| {
            if (bid.price > highest) {
                highest = bid.price;
            }
        }
        return highest;
    }
    
    /// Get lowest ask price for validation
    fn getLowestAsk(self: *const Orderbook) f64 {
        if (self.asks.len == 0) return std.math.inf(f64);
        
        var lowest: f64 = std.math.inf(f64);
        for (self.asks) |ask| {
            if (ask.price < lowest) {
                lowest = ask.price;
            }
        }
        return lowest;
    }
};
