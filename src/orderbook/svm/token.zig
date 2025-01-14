const std = @import("std");
const Pubkey = @import("processor.zig").Pubkey;

pub const TokenAccount = struct {
    address: Pubkey,
    owner: Pubkey,
    mint: Pubkey,
    amount: u64,
    delegate: ?Pubkey,
    is_frozen: bool,

    pub fn init(address: Pubkey, owner: Pubkey, mint: Pubkey) TokenAccount {
        return .{
            .address = address,
            .owner = owner,
            .mint = mint,
            .amount = 0,
            .delegate = null,
            .is_frozen = false,
        };
    }

    pub fn canTransfer(self: *const TokenAccount, amount: u64) bool {
        return !self.is_frozen and self.amount >= amount;
    }
};
