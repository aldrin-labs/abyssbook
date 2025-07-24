const std = @import("std");
const parser = @import("parser.zig");

/// Command argument definitions for help commands
pub const HelpCommandArgs = struct {
    pub fn helpArgs(allocator: std.mem.Allocator) !parser.ArgParser {
        var arg_parser = parser.ArgParser.init(allocator, &[_][]const u8{});
        try arg_parser.addArg("command", "Command to get help for", false, null);
        return arg_parser;
    }
};
