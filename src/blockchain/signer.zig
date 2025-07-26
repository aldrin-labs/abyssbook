const std = @import("std");
const ed25519 = @import("std").crypto.sign.Ed25519;

/// TransactionSigner handles signing transactions for the Solana blockchain
pub const TransactionSigner = struct {
    allocator: std.mem.Allocator,
    keypair: ed25519.KeyPair,

    /// Initialize a new transaction signer with the provided secret key
    pub fn init(allocator: std.mem.Allocator, secret_key: []const u8) !TransactionSigner {
        if (secret_key.len != 32) {
            return error.InvalidSecretKeyLength;
        }

        // Create Ed25519 keypair from 32-byte seed
        var seed: [32]u8 = undefined;
        @memcpy(&seed, secret_key[0..32]);

        const keypair = try ed25519.KeyPair.create(seed);

        return TransactionSigner{
            .allocator = allocator,
            .keypair = keypair,
        };
    }

    /// Sign a transaction message
    pub fn signTransaction(self: *TransactionSigner, message: []const u8) ![]const u8 {
        const signature = try self.keypair.sign(message, null);

        return try self.allocator.dupe(u8, &signature.toBytes());
    }

    /// Get the public key associated with this signer
    pub fn getPublicKey(self: *TransactionSigner) []const u8 {
        return &self.keypair.public_key.bytes;
    }

    /// Create a transaction for placing an order
    pub fn createPlaceOrderTransaction(self: *TransactionSigner, market: []const u8, side: []const u8, price: f64, size: f64) ![]const u8 {
        // Create a structured transaction message that mimics Solana transaction format
        // While this is still simplified, it's more realistic than the previous stub
        
        const timestamp = std.time.timestamp();
        const nonce = std.crypto.random.int(u64);
        
        // Create transaction message with proper structure
        var message_buf: [2048]u8 = undefined;
        const message = try std.fmt.bufPrint(&message_buf, 
            "{{\"instruction\":\"place_order\",\"market\":\"{s}\",\"side\":\"{s}\",\"price\":{d:.6},\"size\":{d:.6},\"timestamp\":{d},\"nonce\":{d},\"pubkey\":\"{s}\"}}",
            .{
                market,
                side,
                price,
                size,
                timestamp,
                nonce,
                std.fmt.fmtSliceHexLower(&self.keypair.public_key.bytes),
            }
        );

        // Create message hash for signing (more realistic than signing the full JSON)
        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(message);
        var message_hash: [32]u8 = undefined;
        hasher.final(&message_hash);

        // Sign the message hash
        const signature = try self.keypair.sign(&message_hash, null);
        
        // Return signature as hex string for easier handling
        const signature_bytes = signature.toBytes();
        const hex_signature = try self.allocator.alloc(u8, signature_bytes.len * 2);
        
        for (signature_bytes, 0..) |byte, i| {
            _ = try std.fmt.bufPrint(hex_signature[i*2..i*2+2], "{X:0>2}", .{byte});
        }
        
        return hex_signature;
    }

    /// Create a transaction for canceling an order
    pub fn createCancelOrderTransaction(self: *TransactionSigner, market: []const u8, order_id: []const u8) ![]const u8 {
        // Create a structured transaction message for order cancellation
        
        const timestamp = std.time.timestamp();
        const nonce = std.crypto.random.int(u64);
        
        // Create transaction message with proper structure
        var message_buf: [2048]u8 = undefined;
        const message = try std.fmt.bufPrint(&message_buf, 
            "{{\"instruction\":\"cancel_order\",\"market\":\"{s}\",\"order_id\":\"{s}\",\"timestamp\":{d},\"nonce\":{d},\"pubkey\":\"{s}\"}}",
            .{
                market,
                order_id,
                timestamp,
                nonce,
                std.fmt.fmtSliceHexLower(&self.keypair.public_key.bytes),
            }
        );

        // Create message hash for signing
        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(message);
        var message_hash: [32]u8 = undefined;
        hasher.final(&message_hash);

        // Sign the message hash
        const signature = try self.keypair.sign(&message_hash, null);
        
        // Return signature as hex string
        const signature_bytes = signature.toBytes();
        const hex_signature = try self.allocator.alloc(u8, signature_bytes.len * 2);
        
        for (signature_bytes, 0..) |byte, i| {
            _ = try std.fmt.bufPrint(hex_signature[i*2..i*2+2], "{X:0>2}", .{byte});
        }
        
        return hex_signature;
    }

    /// Deinitialize the signer and free resources
    pub fn deinit(self: *TransactionSigner) void {
        // Clear sensitive data
        @memset(std.mem.asBytes(&self.keypair), 0);
    }
};
