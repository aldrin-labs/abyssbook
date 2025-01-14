const std = @import("std");
const instruction = @import("instruction.zig");
const processor = @import("processor.zig");
const state = @import("state.zig");

pub const EntrypointError = error{
    InvalidInstruction,
    InvalidAccountData,
    ProcessingError,
};

// SVM program entrypoint
pub fn entrypoint(
    program_id: [32]u8,
    accounts: []const u8,
    instruction_data: []const u8,
) EntrypointError!void {
    // Validate program ID
    if (!std.mem.eql(u8, &program_id, &instruction.Program.ID)) {
        return EntrypointError.InvalidInstruction;
    }

    // Initialize state manager
    var state_manager = state.StateManager.init(accounts) catch {
        return EntrypointError.InvalidAccountData;
    };

    // Load current state
    try state_manager.load();

    // Initialize processor
    var proc = processor.Processor.init(
        state_manager.state,
        accounts,
        std.time.timestamp(),
    );

    // Process instruction
    proc.process(instruction_data, accounts) catch |err| {
        return switch (err) {
            processor.ProcessorError.InvalidInstruction => EntrypointError.InvalidInstruction,
            processor.ProcessorError.InvalidAccountData => EntrypointError.InvalidAccountData,
            else => EntrypointError.ProcessingError,
        };
    };

    // Save updated state
    try state_manager.save();
}

// Test entrypoint
test "process valid instruction" {
    const testing = std.testing;

    // Create test accounts data
    var accounts_data: [state.StateManager.ACCOUNT_SIZE]u8 = undefined;
    @memset(&accounts_data, 0);

    // Create test instruction
    const test_instruction = [_]u8{
        @intFromEnum(instruction.OrderbookInstruction.InitializeOrderbook),
    };

    // Process instruction
    try entrypoint(instruction.Program.ID, &accounts_data, &test_instruction);

    // Verify state was initialized
    const state_manager = try state.StateManager.init(&accounts_data);
    try testing.expect(state_manager.state.is_initialized);
}

test "process invalid instruction" {
    const testing = std.testing;

    // Create test accounts data
    var accounts_data: [state.StateManager.ACCOUNT_SIZE]u8 = undefined;
    @memset(&accounts_data, 0);

    // Create invalid instruction
    const invalid_instruction = [_]u8{255}; // Invalid instruction type

    // Verify error is returned
    try testing.expectError(
        EntrypointError.InvalidInstruction,
        entrypoint(instruction.Program.ID, &accounts_data, &invalid_instruction),
    );
}

test "process with invalid program id" {
    const testing = std.testing;

    // Create test accounts data
    var accounts_data: [state.StateManager.ACCOUNT_SIZE]u8 = undefined;
    @memset(&accounts_data, 0);

    // Create test instruction
    const test_instruction = [_]u8{
        @intFromEnum(instruction.OrderbookInstruction.InitializeOrderbook),
    };

    // Create invalid program ID
    var invalid_program_id: [32]u8 = undefined;
    @memset(&invalid_program_id, 255);

    // Verify error is returned
    try testing.expectError(
        EntrypointError.InvalidInstruction,
        entrypoint(invalid_program_id, &accounts_data, &test_instruction),
    );
}

test "process with invalid account data" {
    const testing = std.testing;

    // Create invalid accounts data (too small)
    var accounts_data: [10]u8 = undefined;
    @memset(&accounts_data, 0);

    // Create test instruction
    const test_instruction = [_]u8{
        @intFromEnum(instruction.OrderbookInstruction.InitializeOrderbook),
    };

    // Verify error is returned
    try testing.expectError(
        EntrypointError.InvalidAccountData,
        entrypoint(instruction.Program.ID, &accounts_data, &test_instruction),
    );
}
