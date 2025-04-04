const std = @import("std");
const parser = @import("args/parser.zig");

/// Command argument definitions for orders commands
pub const OrdersCommandArgs = struct {
    pub fn listArgs(allocator: std.mem.Allocator) !parser.ArgParser {
        var arg_parser = parser.ArgParser.init(allocator, &[_][]const u8{});
        try arg_parser.addArg("side", "Filter orders by side (buy or sell)", false, null);
        return arg_parser;
    }

    pub fn placeArgs(allocator: std.mem.Allocator) !parser.ArgParser {
        var arg_parser = parser.ArgParser.init(allocator, &[_][]const u8{});
        try arg_parser.addArg("side", "Order side (buy or sell)", true, null);
        try arg_parser.addArg("price", "Order price in USD", true, null);
        try arg_parser.addArg("size", "Order size in shares", true, null);
        return arg_parser;
    }

    pub fn cancelArgs(allocator: std.mem.Allocator) !parser.ArgParser {
        var arg_parser = parser.ArgParser.init(allocator, &[_][]const u8{});
        try arg_parser.addArg("order_id", "ID of the order to cancel", true, null);
        return arg_parser;
    }
};
