const std = @import("std");

/// Comprehensive error types for secure blockchain operations
pub const BlockchainError = error{
    // Network and connection errors
    NetworkError,
    ApiRequestFailed,
    AuthenticationFailed,
    RateLimitExceeded,
    InvalidResponse,
    TimeoutError,
    ConnectionFailed,
    ServiceUnavailable,
    
    // Security and validation errors
    InvalidApiKey,
    InvalidBaseUrl,
    InsecureBaseUrl,
    Unauthorized,
    Forbidden,
    NotFound,
    RateLimited,
    ServerError,
    ResponseTooLarge,
    ResponseReadFailed,
    
    // Data validation errors
    InvalidMarket,
    MarketNameTooLong,
    InvalidMarketCharacters,
    EmptyResponse,
    InvalidJsonFormat,
    JsonSyntaxError,
    JsonUnexpectedToken,
    JsonParseError,
    
    // Order validation errors
    InvalidSide,
    InvalidPrice,
    PriceTooHigh,
    InvalidPriceValue,
    InvalidSize,
    SizeTooHigh,
    InvalidSizeValue,
    InvalidOrderId,
    OrderIdTooLong,
    InvalidOrderIdFormat,
    InvalidOwnerAddress,
    CrossedOrderbook,
    
    // HTTP and URL errors
    InvalidUrl,
    RequestPreparationFailed,
    HeaderSetupFailed,
    RequestStartFailed,
    RequestFinishFailed,
    ResponseWaitFailed,
    UrlConstructionFailed,
    
    // Order generation errors
    OrderIdGenerationFailed,
    
    // Client errors
    ClientNotConnected,
    
    // Traditional errors
    InsufficientFunds,
    InvalidOrderParameters,
    OrderNotFound,
    MarketNotFound,
    UnknownError,
};

/// ErrorHandler provides utilities for handling blockchain-related errors
pub const ErrorHandler = struct {
    /// Maximum number of retry attempts
    max_retries: u8,
    /// Base delay for exponential backoff in milliseconds
    base_delay_ms: u32,
    
    /// Initialize a new error handler
    pub fn init(max_retries: u8, base_delay_ms: u32) ErrorHandler {
        return ErrorHandler{
            .max_retries = max_retries,
            .base_delay_ms = base_delay_ms,
        };
    }
    
    /// Execute a function with retry logic
    pub fn executeWithRetry(
        self: *const ErrorHandler,
        comptime ReturnType: type,
        context: anytype,
        func: fn(@TypeOf(context)) BlockchainError!ReturnType,
    ) BlockchainError!ReturnType {
        var retry_count: u8 = 0;
        var last_error: BlockchainError = BlockchainError.UnknownError;
        
        while (retry_count <= self.max_retries) : (retry_count += 1) {
            // If this isn't the first attempt, apply exponential backoff
            if (retry_count > 0) {
                const delay_ms = self.base_delay_ms * (1 << (retry_count - 1));
                std.time.sleep(delay_ms * std.time.ns_per_ms);
                
                // Log retry attempt
                std.debug.print("Retrying operation (attempt {}/{})...\n", .{
                    retry_count, self.max_retries
                });
            }
            
            // Attempt the operation
            return func(context) catch |err| {
                // Save the error for potential logging if all retries fail
                last_error = err;
                
                // Determine if we should retry based on the error type
                switch (err) {
                    // Network-related errors are retryable
                    BlockchainError.NetworkError,
                    BlockchainError.TimeoutError,
                    BlockchainError.ConnectionFailed,
                    BlockchainError.ServiceUnavailable => {
                        // Continue to next retry iteration
                        continue;
                    },
                    
                    // Rate limiting requires retry with backoff
                    BlockchainError.RateLimitExceeded => {
                        // Add extra delay for rate limit errors
                        std.time.sleep(1000 * std.time.ns_per_ms);
                        continue;
                    },
                    
                    // Non-retryable errors should be returned immediately
                    BlockchainError.AuthenticationFailed,
                    BlockchainError.InvalidResponse,
                    BlockchainError.InsufficientFunds,
                    BlockchainError.InvalidOrderParameters,
                    BlockchainError.OrderNotFound,
                    BlockchainError.MarketNotFound,
                    BlockchainError.ApiRequestFailed,
                    BlockchainError.UnknownError => {
                        return err;
                    },
                }
            };
        }
        
        // If we've exhausted all retries, return the last error
        std.debug.print("Operation failed after {} retry attempts\n", .{self.max_retries});
        return last_error;
    }
    
    /// Convert HTTP status code to appropriate blockchain error
    pub fn httpStatusToError(status_code: u16) BlockchainError {
        return switch (status_code) {
            200...299 => unreachable, // Success codes shouldn't be converted to errors
            400 => BlockchainError.InvalidOrderParameters,
            401 => BlockchainError.Unauthorized,
            403 => BlockchainError.Forbidden,
            404 => BlockchainError.NotFound,
            408 => BlockchainError.TimeoutError,
            429 => BlockchainError.RateLimited,
            500 => BlockchainError.ServerError,
            502...599 => BlockchainError.ServiceUnavailable,
            else => BlockchainError.UnknownError,
        };
    }
    
    /// Format error message for user display with security context
    pub fn formatErrorMessage(err: BlockchainError) []const u8 {
        return switch (err) {
            // Network and connection errors
            BlockchainError.NetworkError => "Network error: Could not connect to blockchain service",
            BlockchainError.ApiRequestFailed => "API request failed: The blockchain service rejected the request",
            BlockchainError.AuthenticationFailed => "Authentication failed: Please check your API credentials",
            BlockchainError.RateLimitExceeded => "Rate limit exceeded: Too many requests, please try again later",
            BlockchainError.InvalidResponse => "Invalid response: The blockchain service returned unexpected data",
            BlockchainError.TimeoutError => "Timeout error: The blockchain service took too long to respond",
            BlockchainError.ConnectionFailed => "Connection failed: Could not establish connection to blockchain service",
            BlockchainError.ServiceUnavailable => "Service unavailable: The blockchain service is currently down",
            
            // Security errors
            BlockchainError.InvalidApiKey => "Security error: Invalid API key provided",
            BlockchainError.InvalidBaseUrl => "Security error: Invalid base URL provided",
            BlockchainError.InsecureBaseUrl => "Security error: Base URL must use HTTPS",
            BlockchainError.Unauthorized => "Authorization failed: Invalid or expired credentials",
            BlockchainError.Forbidden => "Access denied: Insufficient permissions",
            BlockchainError.NotFound => "Resource not found: The requested resource does not exist",
            BlockchainError.RateLimited => "Rate limited: Too many requests, please wait before retrying",
            BlockchainError.ServerError => "Server error: The blockchain service encountered an internal error",
            BlockchainError.ResponseTooLarge => "Security error: Response size exceeds safety limits",
            BlockchainError.ResponseReadFailed => "Communication error: Failed to read response from service",
            
            // Data validation errors
            BlockchainError.InvalidMarket => "Validation error: Invalid market identifier",
            BlockchainError.MarketNameTooLong => "Validation error: Market name exceeds maximum length",
            BlockchainError.InvalidMarketCharacters => "Security error: Market name contains invalid characters",
            BlockchainError.EmptyResponse => "Data error: Received empty response from service",
            BlockchainError.InvalidJsonFormat => "Data error: Response is not valid JSON",
            BlockchainError.JsonSyntaxError => "Data error: JSON syntax error in response",
            BlockchainError.JsonUnexpectedToken => "Data error: Unexpected token in JSON response",
            BlockchainError.JsonParseError => "Data error: Failed to parse JSON response",
            
            // Order validation errors
            BlockchainError.InvalidSide => "Validation error: Order side must be 'buy' or 'sell'",
            BlockchainError.InvalidPrice => "Validation error: Price must be positive",
            BlockchainError.PriceTooHigh => "Validation error: Price exceeds maximum allowed value",
            BlockchainError.InvalidPriceValue => "Validation error: Price is not a valid number",
            BlockchainError.InvalidSize => "Validation error: Size must be positive",
            BlockchainError.SizeTooHigh => "Validation error: Size exceeds maximum allowed value",
            BlockchainError.InvalidSizeValue => "Validation error: Size is not a valid number",
            BlockchainError.InvalidOrderId => "Validation error: Invalid order ID format",
            BlockchainError.OrderIdTooLong => "Validation error: Order ID exceeds maximum length",
            BlockchainError.InvalidOrderIdFormat => "Security error: Order ID contains invalid characters",
            BlockchainError.InvalidOwnerAddress => "Validation error: Invalid owner address",
            BlockchainError.CrossedOrderbook => "Data integrity error: Orderbook has crossed bids and asks",
            
            // HTTP and URL errors
            BlockchainError.InvalidUrl => "Configuration error: Invalid URL format",
            BlockchainError.RequestPreparationFailed => "Network error: Failed to prepare HTTP request",
            BlockchainError.HeaderSetupFailed => "Network error: Failed to set HTTP headers",
            BlockchainError.RequestStartFailed => "Network error: Failed to start HTTP request",
            BlockchainError.RequestFinishFailed => "Network error: Failed to complete HTTP request",
            BlockchainError.ResponseWaitFailed => "Network error: Failed to receive HTTP response",
            BlockchainError.UrlConstructionFailed => "Configuration error: Failed to construct request URL",
            
            // Generation errors
            BlockchainError.OrderIdGenerationFailed => "System error: Failed to generate secure order ID",
            
            // Client errors
            BlockchainError.ClientNotConnected => "System error: Blockchain client is not connected",
            
            // Traditional errors
            BlockchainError.InsufficientFunds => "Transaction error: Insufficient funds to complete the transaction",
            BlockchainError.InvalidOrderParameters => "Validation error: Please check order parameters",
            BlockchainError.OrderNotFound => "Order error: The specified order ID does not exist",
            BlockchainError.MarketNotFound => "Market error: The specified market does not exist",
            BlockchainError.UnknownError => "Unknown error: An unexpected error occurred",
        };
    }
};
