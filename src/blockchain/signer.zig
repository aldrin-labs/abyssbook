const std = @import("std");
const ed25519 = @import("std").crypto.sign.Ed25519;

/// TransactionSigner handles signing transactions for the Solana blockchain
pub const TransactionSigner = struct {
    allocator: std.mem.Allocator,
    keypair: ed25519.KeyPair,
    
    /// Initialize a new transaction signer with the provided keypair
    pub fn init(allocator: std.mem.Allocator, secret_key: []const u8) !TransactionSigner {
        if (secret_key.len != ed25519.SecretKey.encoded_length) {
            return error.InvalidSecretKeyLength;
        }
        
        var secret_key_bytes: [ed25519.SecretKey.encoded_length]u8 = undefined;
        std.mem.copy(u8, &secret_key_bytes, secret_key);
        
        const keypair = try ed25519.KeyPair.fromSecretKey(secret_key_bytes);
        
        return TransactionSigner{
            .allocator = allocator,
            .keypair = keypair,
        };
    }
    
    /// Sign a transaction message
    pub fn signTransaction(self: *TransactionSigner, message: []const u8) ![]const u8 {
        var signature: [ed25519.Signature.encoded_length]u8 = undefined;
        ed25519.sign(message, self.keypair, &signature);
        
        return try self.allocator.dupe(u8, &signature);
    }
    
    /// Get the public key associated with this signer
    pub fn getPublicKey(self: *TransactionSigner) []const u8 {
        return &self.keypair.public_key.bytes;
    }
    
    /// Create a transaction for placing an order
    pub fn createPlaceOrderTransaction(
        self: *TransactionSigner, 
        market: []const u8, 
        side: []const u8, 
        price: f64, 
        size: f64
    ) ![]const u8 {
        // In a real implementation, this would construct a proper Solana transaction
        // with the appropriate instructions for placing an order
        
        // For now, we'll create a simplified transaction message
        var message_buf: [1024]u8 = undefined;
        const message = try std.fmt.bufPrint(&message_buf, 
            "place_order:{s}:{s}:{d}:{d}:{d}", 
            .{
                market,
                side,
                price,
                size,
                std.time.timestamp(),
            }
        );
        
        // Sign the message
        return try self.signTransaction(message);
    }
    
    /// Create a transaction for canceling an order
    pub fn createCancelOrderTransaction(
        self: *TransactionSigner,
        market: []const u8,
        order_id: []const u8
    ) ![]const u8 {
        // In a real implementation, this would construct a proper Solana transaction
        // with the appropriate instructions for canceling an order
        
        // For now, we'll create a simplified transaction message
        var message_buf: [1024]u8 = undefined;
        const message = try std.fmt.bufPrint(&message_buf, 
            "cancel_order:{s}:{s}:{d}", 
            .{
                market,
                order_id,
                std.time.timestamp(),
            }
        );
        
        // Sign the message
        return try self.signTransaction(message);
    }
    
    /// Deinitialize the signer and free resources
    pub fn deinit(self: *TransactionSigner) void {
        // Clear sensitive data
        std.mem.set(u8, std.mem.asBytes(&self.keypair), 0);
    }
};
