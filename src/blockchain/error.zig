const std = @import("std");
const BlockchainConstants = @import("constants.zig").BlockchainConstants;

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
        func: fn (@TypeOf(context)) BlockchainError!ReturnType,
    ) BlockchainError!ReturnType {
        var retry_count: u8 = 0;
        var last_error: BlockchainError = BlockchainError.UnknownError;

        while (retry_count <= self.max_retries) : (retry_count += 1) {
            // If this isn't the first attempt, apply exponential backoff
            if (retry_count > 0) {
                const delay_ms = self.base_delay_ms * (1 << (retry_count - 1));
                std.time.sleep(delay_ms * std.time.ns_per_ms);

                // Log retry attempt
                std.debug.print("Retrying operation (attempt {}/{})...\n", .{ retry_count, self.max_retries });
            }

            // Attempt the operation
            const result = func(context) catch |err| {
                // Save the error for potential logging if all retries fail
                last_error = err;

                // Determine if we should retry based on the error type
                switch (err) {
                    // Network-related errors are retryable
                    BlockchainError.NetworkError,
                    BlockchainError.TimeoutError,
                    BlockchainError.ConnectionFailed,
                    BlockchainError.ServiceUnavailable => {
                        // Continue to next retry iteration if retries remain
                        if (retry_count < self.max_retries) {
                            continue;
                        } else {
                            return err;
                        }
                    },

                    // Rate limiting requires retry with backoff
                    BlockchainError.RateLimitExceeded => {
                        // Add extra delay for rate limit errors
                        std.time.sleep(BlockchainConstants.RATE_LIMIT_EXTRA_DELAY_MS * std.time.ns_per_ms);
                        if (retry_count < self.max_retries) {
                            continue;
                        } else {
                            return err;
                        }
                    },

                    // Non-retryable errors should be returned immediately
                    BlockchainError.AuthenticationFailed,
                    BlockchainError.InvalidResponse,
                    BlockchainError.InsufficientFunds,
                    BlockchainError.InvalidOrderParameters,
                    BlockchainError.OrderNotFound,
                    BlockchainError.MarketNotFound,
                    BlockchainError.ApiRequestFailed,
                    BlockchainError.UnknownError,
                    // Add missing error cases for completeness
                    BlockchainError.Unauthorized,
                    BlockchainError.Forbidden,
                    BlockchainError.NotFound,
                    BlockchainError.InvalidApiKey,
                    BlockchainError.InvalidBaseUrl,
                    BlockchainError.InsecureBaseUrl => {
                        return err;
                    },
                    
                    // Default case for any other errors
                    else => {
                        return err;
                    },
                }
            };
            
            // If we reach here, the operation succeeded
            return result;
        }

        // If we've exhausted all retries, return the last error
        std.debug.print("Operation failed after {d} retry attempts\n", .{self.max_retries});
        return last_error;
    }

    /// Convert HTTP status code to appropriate blockchain error
    /// Note: This function should only be called with error status codes (400+)
    /// Success codes (200-299) will return UnknownError to avoid panics
    pub fn httpStatusToError(status_code: u16) BlockchainError {
        return switch (status_code) {
            200...299 => {
                // Log warning for unexpected success code conversion
                std.debug.print("Warning: httpStatusToError called with success code {d}\n", .{status_code});
                return BlockchainError.UnknownError;
            },
            400 => BlockchainError.InvalidOrderParameters,
            401 => BlockchainError.Unauthorized,
            403 => BlockchainError.Forbidden,
            404 => BlockchainError.NotFound,
            408 => BlockchainError.TimeoutError,
            429 => BlockchainError.RateLimited,
            500 => BlockchainError.ServerError,
            502...599 => BlockchainError.ServiceUnavailable,
            else => BlockchainError.UnknownError,
    }
    
    /// Format error message for user display with security context and operation details
    pub fn formatErrorMessage(err: BlockchainError) []const u8 {
        return switch (err) {
            // Network and connection errors
            BlockchainError.NetworkError => "🌐 Network error: Could not connect to blockchain service. Please check your internet connection.",
            BlockchainError.ApiRequestFailed => "🔌 API request failed: The blockchain service rejected the request. Please try again.",
            BlockchainError.AuthenticationFailed => "🔑 Authentication failed: Please verify your API credentials are correct.",
            BlockchainError.RateLimitExceeded => "⏱️ Rate limit exceeded: Too many requests sent. Please wait before retrying.",
            BlockchainError.InvalidResponse => "📥 Invalid response: The blockchain service returned unexpected data format.",
            BlockchainError.TimeoutError => "⏰ Timeout error: The blockchain service took too long to respond. Please retry.",
            BlockchainError.ConnectionFailed => "🔗 Connection failed: Could not establish connection to blockchain service.",
            BlockchainError.ServiceUnavailable => "🚫 Service unavailable: The blockchain service is currently down for maintenance.",
            
            // Security errors
            BlockchainError.InvalidApiKey => "🛡️ Security error: Invalid API key provided. Please check your configuration.",
            BlockchainError.InvalidBaseUrl => "🛡️ Security error: Invalid base URL provided. Please verify the endpoint.",
            BlockchainError.InsecureBaseUrl => "🛡️ Security error: Base URL must use HTTPS for secure connections.",
            BlockchainError.Unauthorized => "🚨 Authorization failed: Invalid or expired credentials. Please re-authenticate.",
            BlockchainError.Forbidden => "🚫 Access denied: Insufficient permissions for this operation.",
            BlockchainError.NotFound => "❓ Resource not found: The requested resource does not exist.",
            BlockchainError.RateLimited => "⏱️ Rate limited: Too many requests. Please wait before retrying.",
            BlockchainError.ServerError => "🔧 Server error: The blockchain service encountered an internal error.",
            BlockchainError.ResponseTooLarge => "📊 Security error: Response size exceeds safety limits to prevent DoS.",
            BlockchainError.ResponseReadFailed => "📤 Communication error: Failed to read response from service.",
            
            // Data validation errors
            BlockchainError.InvalidMarket => "📊 Validation error: Invalid market identifier provided.",
            BlockchainError.MarketNameTooLong => "📏 Validation error: Market name exceeds maximum allowed length.",
            BlockchainError.InvalidMarketCharacters => "🛡️ Security error: Market name contains prohibited characters.",
            BlockchainError.EmptyResponse => "📭 Data error: Received empty response from service.",
            BlockchainError.InvalidJsonFormat => "📄 Data error: Response is not valid JSON format.",
            BlockchainError.JsonSyntaxError => "📝 Data error: JSON syntax error in response.",
            BlockchainError.JsonUnexpectedToken => "🔍 Data error: Unexpected token in JSON response.",
            BlockchainError.JsonParseError => "🔧 Data error: Failed to parse JSON response.",
            
            // Order validation errors
            BlockchainError.InvalidSide => "📊 Validation error: Order side must be 'buy' or 'sell'.",
            BlockchainError.InvalidPrice => "💰 Validation error: Price must be a positive number.",
            BlockchainError.PriceTooHigh => "💸 Validation error: Price exceeds maximum allowed value.",
            BlockchainError.InvalidPriceValue => "🔢 Validation error: Price is not a valid number (NaN or Infinity).",
            BlockchainError.InvalidSize => "📦 Validation error: Size must be a positive number.",
            BlockchainError.SizeTooHigh => "📏 Validation error: Size exceeds maximum allowed value.",
            BlockchainError.InvalidSizeValue => "🔢 Validation error: Size is not a valid number (NaN or Infinity).",
            BlockchainError.InvalidOrderId => "🏷️ Validation error: Invalid order ID format provided.",
            BlockchainError.OrderIdTooLong => "📏 Validation error: Order ID exceeds maximum allowed length.",
            BlockchainError.InvalidOrderIdFormat => "🛡️ Security error: Order ID contains invalid characters.",
            BlockchainError.InvalidOwnerAddress => "👛 Validation error: Invalid wallet address format.",
            BlockchainError.CrossedOrderbook => "⚠️ Data integrity error: Orderbook has crossed bids and asks.",
            
            // HTTP and URL errors
            BlockchainError.InvalidUrl => "🔗 Configuration error: Invalid URL format provided.",
            BlockchainError.RequestPreparationFailed => "🔧 Network error: Failed to prepare HTTP request.",
            BlockchainError.HeaderSetupFailed => "📋 Network error: Failed to set HTTP headers.",
            BlockchainError.RequestStartFailed => "🚀 Network error: Failed to initiate HTTP request.",
            BlockchainError.RequestFinishFailed => "🏁 Network error: Failed to complete HTTP request.",
            BlockchainError.ResponseWaitFailed => "⏳ Network error: Failed to receive HTTP response.",
            BlockchainError.UrlConstructionFailed => "🔧 Configuration error: Failed to construct request URL.",
            
            // Generation errors
            BlockchainError.OrderIdGenerationFailed => "🔐 System error: Failed to generate secure order ID.",
            
            // Client errors
            BlockchainError.ClientNotConnected => "🔌 System error: Blockchain client is not connected.",
            
            // Traditional errors
            BlockchainError.InsufficientFunds => "💳 Transaction error: Insufficient funds to complete the operation.",
            BlockchainError.InvalidOrderParameters => "📋 Validation error: Please check your order parameters.",
            BlockchainError.OrderNotFound => "🔍 Order error: The specified order ID does not exist.",
            BlockchainError.MarketNotFound => "🏪 Market error: The specified market does not exist.",
            BlockchainError.UnknownError => "❓ Unknown error: An unexpected error occurred. Please contact support.",
        };
    }
};
