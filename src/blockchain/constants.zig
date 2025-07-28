const std = @import("std");

/// Centralized blockchain-related constants for consistent configuration
pub const BlockchainConstants = struct {
    /// Network and retry configuration
    pub const MAX_RETRIES: u8 = 3;
    pub const BASE_RETRY_DELAY_MS: u32 = 100;
    pub const RATE_LIMIT_DELAY_MS: u32 = 100;
    pub const RATE_LIMIT_EXTRA_DELAY_MS: u32 = 1000;
    
    /// Request and response limits  
    pub const MAX_RESPONSE_SIZE: usize = 10 * 1024 * 1024; // 10MB
    pub const REQUEST_TIMEOUT_MS: u32 = 30 * 1000; // 30 seconds
    
    /// Input validation limits
    pub const MAX_MARKET_NAME_LENGTH: usize = 64;
    pub const MAX_ORDER_ID_LENGTH: usize = 64;
    pub const MAX_SIDE_LENGTH: usize = 10;
    pub const MAX_PRICE_STRING_LENGTH: usize = 32;
    pub const MAX_SIZE_STRING_LENGTH: usize = 32;
    
    /// Business logic limits
    pub const MAX_PRICE_VALUE: f64 = 1000000000.0; // $1B max
    pub const MAX_SIZE_VALUE: f64 = 1000000000.0; // 1B max
    
    /// Security configuration
    pub const ORDER_ID_BYTES: usize = 16;
    pub const ORDER_ID_HEX_LENGTH: usize = 32;
    
    /// Monitoring and cleanup
    pub const OPERATION_CLEANUP_SLEEP_MS: u32 = 10;
    
    /// Error handler configuration
    pub const DEFAULT_ERROR_HANDLER_RETRIES: u8 = 3;
    pub const DEFAULT_ERROR_HANDLER_BASE_DELAY_MS: u32 = 200;
};