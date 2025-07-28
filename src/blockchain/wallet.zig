const std = @import("std");
const TransactionSigner = @import("../blockchain/signer.zig").TransactionSigner;

/// Wallet handles key management and transaction signing for blockchain interactions
pub const Wallet = struct {
    allocator: std.mem.Allocator,
    signer: TransactionSigner,
    address: []const u8,

    /// Initialize a new wallet from a secret key
    pub fn initFromSecretKey(allocator: std.mem.Allocator, secret_key: []const u8) !Wallet {
        var signer = try TransactionSigner.init(allocator, secret_key);
        const public_key = signer.getPublicKey();
        const address = try allocator.dupe(u8, public_key);

        return Wallet{
            .allocator = allocator,
            .signer = signer,
            .address = address,
        };
    }

    /// Initialize a new wallet with a randomly generated keypair
    pub fn initRandom(allocator: std.mem.Allocator) !Wallet {
        // Generate a cryptographically secure random 32-byte secret key
        var secret_key: [32]u8 = undefined;
        std.crypto.random.bytes(&secret_key);
        
        // Ensure the secret key is in valid range for Ed25519
        // Ed25519 requires secret keys to be in the valid scalar range
        secret_key[31] &= 0x7F; // Clear the top bit to ensure valid scalar
        
        std.debug.print("Generated new secure keypair for wallet\n", .{});
        std.debug.print("Warning: This is a temporary wallet. Save your private key securely in production.\n", .{});
        
        return try initFromSecretKey(allocator, &secret_key);
    }

    /// Sign a transaction for placing an order
    pub fn signPlaceOrderTransaction(self: *Wallet, market: []const u8, side: []const u8, price: f64, size: f64) ![]const u8 {
        return try self.signer.createPlaceOrderTransaction(market, side, price, size);
    }

    /// Sign a transaction for canceling an order
    pub fn signCancelOrderTransaction(self: *Wallet, market: []const u8, order_id: []const u8) ![]const u8 {
        return try self.signer.createCancelOrderTransaction(market, order_id);
    }

    /// Get the wallet address (public key)
    pub fn getAddress(self: *const Wallet) []const u8 {
        return self.address;
    }

    /// Deinitialize the wallet and free resources
    pub fn deinit(self: *Wallet) void {
        self.signer.deinit();
        self.allocator.free(self.address);
    }
};
