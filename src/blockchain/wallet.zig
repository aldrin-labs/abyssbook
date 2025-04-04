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
        comptime {
            if (std.builtin.mode != .Debug) {
                @compileError("initRandom: Hardcoded test key can only be used in Debug mode.");
            }
        }
        // In a real implementation, this would generate a secure random keypair
        // For now, we'll use a hardcoded test key (NEVER do this in production)
        const test_secret_key = [_]u8{
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
            0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
            0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20,
        };
        
        return try initFromSecretKey(allocator, &test_secret_key);
    }
    
    /// Sign a transaction for placing an order
    pub fn signPlaceOrderTransaction(
        self: *Wallet,
        market: []const u8,
        side: []const u8,
        price: f64,
        size: f64
    ) ![]const u8 {
        return try self.signer.createPlaceOrderTransaction(
            market,
            side,
            price,
            size
        );
    }
    
    /// Sign a transaction for canceling an order
    pub fn signCancelOrderTransaction(
        self: *Wallet,
        market: []const u8,
        order_id: []const u8
    ) ![]const u8 {
        return try self.signer.createCancelOrderTransaction(
            market,
            order_id
        );
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
