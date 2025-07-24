const std = @import("std");
const logging = @import("../../logging.zig");

/// Argument parsing error types
pub const ArgError = error{
    MissingRequiredArgument,
    InvalidArgumentValue,
    UnknownArgument,
    InsufficientArguments,
};

/// Command argument definition
pub const ArgDef = struct {
    name: []const u8,
    description: []const u8,
    required: bool = false,
    default_value: ?[]const u8 = null,
};

/// Parsed argument result
pub const ParsedArg = struct {
    name: []const u8,
    value: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParsedArg) void {
        // Nothing to deinit currently as we're using string slices
        _ = self;
    }
};

/// Command argument parser
pub const ArgParser = struct {
    args: []const []const u8,
    allocator: std.mem.Allocator,
    definitions: std.ArrayList(ArgDef),
    parsed_args: std.StringHashMap(ParsedArg),
    subcommand: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, args: []const []const u8) ArgParser {
        return .{
            .args = args,
            .allocator = allocator,
            .definitions = std.ArrayList(ArgDef).init(allocator),
            .parsed_args = std.StringHashMap(ParsedArg).init(allocator),
            .subcommand = if (args.len > 0) args[0] else null,
        };
    }

    pub fn deinit(self: *ArgParser) void {
        self.definitions.deinit();

        var it = self.parsed_args.iterator();
        while (it.next()) |entry| {
            var arg = entry.value_ptr;
            arg.deinit();
        }
        self.parsed_args.deinit();
    }

    pub fn addArg(self: *ArgParser, name: []const u8, description: []const u8, required: bool, default_value: ?[]const u8) !void {
        try self.definitions.append(.{
            .name = name,
            .description = description,
            .required = required,
            .default_value = default_value,
        });
    }

    pub fn parse(self: *ArgParser) !void {
        // Log argument parsing attempt for security monitoring
        logging.debugGlobalWithContext("cli.args", "Parsing CLI arguments", .{
            .subcommand = if (self.subcommand) |cmd| cmd else "none",
            .arg_count = self.args.len,
            .definition_count = self.definitions.items.len,
        });

        // Skip the first argument (subcommand) if it exists
        const start_index: usize = if (self.args.len > 0) 1 else 0;

        // Process positional arguments based on definitions
        var def_index: usize = 0;
        var arg_index: usize = start_index;

        while (def_index < self.definitions.items.len and arg_index < self.args.len) {
            const def = self.definitions.items[def_index];
            const arg_value = self.args[arg_index];

            // Log argument processing for security
            logging.debugGlobalWithContext("cli.args", "Processing argument", .{
                .name = def.name,
                .has_value = true,
                .is_required = def.required,
            });

            // Basic validation for potentially dangerous inputs
            if (self.containsSuspiciousCharacters(arg_value)) {
                logging.warnGlobalWithContext("cli.args", "Suspicious characters detected in argument", .{
                    .argument_name = def.name,
                    .value_length = arg_value.len,
                });
            }

            try self.parsed_args.put(def.name, .{
                .name = def.name,
                .value = arg_value,
                .allocator = self.allocator,
            });

            def_index += 1;
            arg_index += 1;
        }

        // Check for missing required arguments
        for (self.definitions.items) |def| {
            if (def.required and !self.parsed_args.contains(def.name)) {
                logging.warnGlobalWithContext("cli.args", "Missing required argument", .{
                    .argument_name = def.name,
                });

                if (def.default_value) |default| {
                    logging.debugGlobalWithContext("cli.args", "Using default value for missing argument", .{
                        .argument_name = def.name,
                    });
                    try self.parsed_args.put(def.name, .{
                        .name = def.name,
                        .value = default,
                        .allocator = self.allocator,
                    });
                } else {
                    logging.errorGlobalWithContext("cli.args", "Required argument missing with no default", .{
                        .argument_name = def.name,
                    });
                    return ArgError.MissingRequiredArgument;
                }
            }
        }

        logging.infoGlobal("cli.args", "CLI arguments parsed successfully");
    }

    pub fn getString(self: *ArgParser, name: []const u8) ?[]const u8 {
        if (self.parsed_args.get(name)) |arg| {
            return arg.value;
        }

        // Check if there's a default value in definitions
        for (self.definitions.items) |def| {
            if (std.mem.eql(u8, def.name, name) and def.default_value != null) {
                return def.default_value;
            }
        }

        return null;
    }

    /// Check for suspicious characters that might indicate injection attempts
    fn containsSuspiciousCharacters(self: *ArgParser, value: []const u8) bool {
        _ = self;

        // Check for common injection patterns
        const suspicious_patterns = [_][]const u8{
            "../", // Path traversal
            "./", // Current directory access
            "\\x", // Hex escape sequences
            "$()", // Command substitution
            "`", // Backticks for command execution
            ";", // Command separator
            "|", // Pipe operator
            "&", // Background execution
            "rm ", // Dangerous file operations
            "del ", // Windows delete command
            "format ", // Format command
            "<script", // Script injection
            "javascript:", // JavaScript protocol
        };

        for (suspicious_patterns) |pattern| {
            if (std.mem.indexOf(u8, value, pattern) != null) {
                return true;
            }
        }

        // Check for excessive special characters
        var special_char_count: usize = 0;
        for (value) |char| {
            if (!std.ascii.isAlphanumeric(char) and char != '-' and char != '_' and char != '.' and char != '/') {
                special_char_count += 1;
            }
        }

        // If more than 20% of characters are special, consider suspicious
        return special_char_count > value.len / 5;
    }

    pub fn getStringOrError(self: *ArgParser, name: []const u8) ![]const u8 {
        if (self.getString(name)) |value| {
            return value;
        }
        return ArgError.MissingRequiredArgument;
    }

    pub fn getSubcommand(self: *ArgParser) ?[]const u8 {
        return self.subcommand;
    }

    pub fn printUsage(self: *ArgParser, command_name: []const u8, description: []const u8) void {
        std.debug.print("\n{s} - {s}\n\n", .{ command_name, description });
        std.debug.print("Arguments:\n", .{});

        for (self.definitions.items) |def| {
            const req_text = if (def.required) "required" else "optional";
            const default_text = if (def.default_value) |val|
                std.fmt.allocPrint(self.allocator, " (default: {s})", .{val}) catch "error"
            else
                "";

            std.debug.print("  {s}: {s} [{s}]{s}\n", .{
                def.name,
                def.description,
                req_text,
                default_text,
            });

            if (default_text.len > 0 and !std.mem.eql(u8, default_text, "error")) {
                self.allocator.free(default_text);
            }
        }
        std.debug.print("\n", .{});
    }
};

/// Helper function to create a parser for a specific command
pub fn createCommandParser(allocator: std.mem.Allocator, args: []const []const u8) ArgParser {
    return ArgParser.init(allocator, args);
}
