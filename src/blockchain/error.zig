const std = @import("std");

/// Error types for blockchain operations
pub const BlockchainError = error{
    NetworkError,
    ApiRequestFailed,
    AuthenticationFailed,
    RateLimitExceeded,
    InvalidResponse,
    TimeoutError,
    ConnectionFailed,
    InsufficientFunds,
    InvalidOrderParameters,
    OrderNotFound,
    MarketNotFound,
    ServiceUnavailable,
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
            return func(context) catch |err| {
                // Save the error for potential logging if all retries fail
                last_error = err;

                // Determine if we should retry based on the error type
                switch (err) {
                    // Network-related errors are retryable
                    BlockchainError.NetworkError, BlockchainError.TimeoutError, BlockchainError.ConnectionFailed, BlockchainError.ServiceUnavailable => {
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
                    BlockchainError.AuthenticationFailed, BlockchainError.InvalidResponse, BlockchainError.InsufficientFunds, BlockchainError.InvalidOrderParameters, BlockchainError.OrderNotFound, BlockchainError.MarketNotFound, BlockchainError.ApiRequestFailed, BlockchainError.UnknownError => {
                        return err;
                    },
                }
            };
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
            401 => BlockchainError.AuthenticationFailed,
            403 => BlockchainError.AuthenticationFailed,
            404 => BlockchainError.MarketNotFound,
            408 => BlockchainError.TimeoutError,
            429 => BlockchainError.RateLimitExceeded,
            500...599 => BlockchainError.ServiceUnavailable,
            else => BlockchainError.UnknownError,
        };
    }

    /// Format error message for user display
    pub fn formatErrorMessage(err: BlockchainError) []const u8 {
        return switch (err) {
            BlockchainError.NetworkError => "Network error: Could not connect to blockchain service",
            BlockchainError.ApiRequestFailed => "API request failed: The blockchain service rejected the request",
            BlockchainError.AuthenticationFailed => "Authentication failed: Please check your API credentials",
            BlockchainError.RateLimitExceeded => "Rate limit exceeded: Too many requests, please try again later",
            BlockchainError.InvalidResponse => "Invalid response: The blockchain service returned unexpected data",
            BlockchainError.TimeoutError => "Timeout error: The blockchain service took too long to respond",
            BlockchainError.ConnectionFailed => "Connection failed: Could not establish connection to blockchain service",
            BlockchainError.InsufficientFunds => "Insufficient funds: Not enough balance to complete the transaction",
            BlockchainError.InvalidOrderParameters => "Invalid order parameters: Please check price and size values",
            BlockchainError.OrderNotFound => "Order not found: The specified order ID does not exist",
            BlockchainError.MarketNotFound => "Market not found: The specified market does not exist",
            BlockchainError.ServiceUnavailable => "Service unavailable: The blockchain service is currently down",
            BlockchainError.UnknownError => "Unknown error: An unexpected error occurred",
        };
    }
};
