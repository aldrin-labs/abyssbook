const std = @import("std");

/// Multi-stage CLI input sanitizer with enhanced security filtering
/// Provides layered validation while maintaining user experience
pub const InputSanitizer = struct {
    allocator: std.mem.Allocator,
    max_input_length: usize,
    strict_mode: bool,

    const Self = @This();

    pub const SanitizationConfig = struct {
        max_length: usize = 1024,
        allow_unicode: bool = true,
        allow_special_chars: bool = true,
        strict_commands: bool = false,
        filter_sql_injection: bool = true,
        filter_path_traversal: bool = true,
        filter_script_injection: bool = true,
    };

    pub const SanitizationResult = struct {
        cleaned_input: []const u8,
        warnings: std.ArrayList([]const u8),
        blocked_patterns: std.ArrayList([]const u8),
        security_level: SecurityLevel,

        pub fn deinit(self: *SanitizationResult, allocator: std.mem.Allocator) void {
            allocator.free(self.cleaned_input);
            for (self.warnings.items) |warning| {
                allocator.free(warning);
            }
            for (self.blocked_patterns.items) |pattern| {
                allocator.free(pattern);
            }
            self.warnings.deinit();
            self.blocked_patterns.deinit();
        }
    };

    pub const SecurityLevel = enum {
        SAFE,
        SUSPICIOUS,
        DANGEROUS,
        BLOCKED,
    };

    // Dangerous patterns to detect and block
    const DANGEROUS_PATTERNS = [_][]const u8{
        // SQL Injection patterns
        "'; DROP TABLE",
        "' OR '1'='1",
        "UNION SELECT",
        "'; --",
        "' UNION",

        // Path traversal patterns
        "../",
        "..\\",
        "/..",
        "\\..",
        "/etc/passwd",
        "/etc/shadow",
        "\\windows\\system32",

        // Script injection patterns
        "<script>",
        "</script>",
        "javascript:",
        "vbscript:",
        "onload=",
        "onerror=",
        "eval(",
        "document.cookie",

        // Command injection patterns
        "$((",
        "`command`",
        "&&",
        "||",
        ";rm -rf",
        ";del /f",
        "|nc ",
        ">/dev/tcp",

        // Protocol attacks
        "file://",
        "ftp://",
        "ldap://",
        "data:",
        "gopher://",
    };

    // Suspicious patterns that trigger warnings but aren't blocked
    const SUSPICIOUS_PATTERNS = [_][]const u8{
        "admin",
        "root",
        "config",
        "password",
        "secret",
        "token",
        "auth",
        "login",
        "system",
        "internal",
    };

    pub fn init(allocator: std.mem.Allocator, config: SanitizationConfig) Self {
        return Self{
            .allocator = allocator,
            .max_input_length = config.max_length,
            .strict_mode = config.strict_commands,
        };
    }

    /// Multi-stage sanitization process
    pub fn sanitize(self: *Self, input: []const u8, config: SanitizationConfig) !SanitizationResult {
        var result = SanitizationResult{
            .cleaned_input = undefined,
            .warnings = std.ArrayList([]const u8).init(self.allocator),
            .blocked_patterns = std.ArrayList([]const u8).init(self.allocator),
            .security_level = .SAFE,
        };

        // Stage 1: Length validation
        if (input.len > config.max_length) {
            try result.blocked_patterns.append(try std.fmt.allocPrint(self.allocator, "Input too long: {d} > {d}", .{ input.len, config.max_length }));
            result.security_level = .BLOCKED;
            result.cleaned_input = try self.allocator.dupe(u8, "");
            return result;
        }

        // Stage 2: Null byte detection
        if (std.mem.indexOf(u8, input, "\x00")) |_| {
            try result.blocked_patterns.append(try self.allocator.dupe(u8, "Null byte detected"));
            result.security_level = .BLOCKED;
            result.cleaned_input = try self.allocator.dupe(u8, "");
            return result;
        }

        // Stage 3: Dangerous pattern detection
        for (DANGEROUS_PATTERNS) |pattern| {
            if (std.ascii.indexOfIgnoreCase(input, pattern)) |_| {
                try result.blocked_patterns.append(try std.fmt.allocPrint(self.allocator, "Dangerous pattern: {s}", .{pattern}));
                result.security_level = .BLOCKED;
                result.cleaned_input = try self.allocator.dupe(u8, "");
                return result;
            }
        }

        // Stage 4: Suspicious pattern detection (warnings only)
        for (SUSPICIOUS_PATTERNS) |pattern| {
            if (std.ascii.indexOfIgnoreCase(input, pattern)) |_| {
                try result.warnings.append(try std.fmt.allocPrint(self.allocator, "Suspicious pattern detected: {s}", .{pattern}));
                if (result.security_level == .SAFE) {
                    result.security_level = .SUSPICIOUS;
                }
            }
        }

        // Stage 5: Character filtering and normalization
        var cleaned = std.ArrayList(u8).init(self.allocator);
        defer cleaned.deinit();

        for (input) |char| {
            if (self.isAllowedCharacter(char, config)) {
                try cleaned.append(char);
            } else {
                try result.warnings.append(try std.fmt.allocPrint(self.allocator, "Filtered character: 0x{X:0>2}", .{char}));
                if (result.security_level == .SAFE) {
                    result.security_level = .SUSPICIOUS;
                }
            }
        }

        // Stage 6: Command-specific validation
        if (config.strict_commands) {
            const command_result = self.validateCommand(cleaned.items);
            if (command_result != .SAFE) {
                result.security_level = command_result;
                if (command_result == .BLOCKED) {
                    try result.blocked_patterns.append(try self.allocator.dupe(u8, "Invalid command format"));
                    result.cleaned_input = try self.allocator.dupe(u8, "");
                    return result;
                }
            }
        }

        // Stage 7: Final validation and encoding
        result.cleaned_input = try self.allocator.dupe(u8, cleaned.items);

        return result;
    }

    /// Check if character is allowed based on configuration
    fn isAllowedCharacter(self: *Self, char: u8, config: SanitizationConfig) bool {
        _ = self; // unused

        // Always allow basic ASCII printable characters
        if (char >= 32 and char <= 126) {
            if (!config.allow_special_chars) {
                // Only allow alphanumeric, space, and basic punctuation
                return std.ascii.isAlphanumeric(char) or char == ' ' or char == '.' or char == '-' or char == '_';
            }
            return true;
        }

        // Allow newlines and tabs if special chars are enabled
        if (config.allow_special_chars and (char == '\n' or char == '\t' or char == '\r')) {
            return true;
        }

        // Allow extended Unicode if enabled
        if (config.allow_unicode and char >= 128) {
            return true;
        }

        return false;
    }

    /// Validate command structure for strict mode
    fn validateCommand(self: *Self, input: []const u8) SecurityLevel {
        _ = self; // unused

        if (input.len == 0) return .BLOCKED;

        // Check for valid command format: command [subcommand] [args...]
        var parts = std.mem.split(u8, input, " ");
        const command = parts.next() orelse return .BLOCKED;

        // Validate command name (alphanumeric and hyphens only)
        for (command) |char| {
            if (!std.ascii.isAlphanumeric(char) and char != '-' and char != '_') {
                return .BLOCKED;
            }
        }

        // Commands should start with a letter
        if (!std.ascii.isAlphabetic(command[0])) {
            return .BLOCKED;
        }

        return .SAFE;
    }

    /// Quick validation for performance-critical paths
    pub fn quickValidate(self: *Self, input: []const u8) bool {
        // Basic length check
        if (input.len > self.max_input_length) return false;

        // Quick scan for dangerous patterns
        for (DANGEROUS_PATTERNS[0..5]) |pattern| { // Check only first 5 most critical
            if (std.ascii.indexOfIgnoreCase(input, pattern)) |_| {
                return false;
            }
        }

        return true;
    }

    /// Escape input for safe logging
    pub fn escapeForLogging(self: *Self, input: []const u8) ![]const u8 {
        var escaped = std.ArrayList(u8).init(self.allocator);
        defer escaped.deinit();

        for (input) |char| {
            switch (char) {
                '"' => try escaped.appendSlice("\\\""),
                '\\' => try escaped.appendSlice("\\\\"),
                '\n' => try escaped.appendSlice("\\n"),
                '\r' => try escaped.appendSlice("\\r"),
                '\t' => try escaped.appendSlice("\\t"),
                0...31, 127...255 => {
                    try escaped.writer().print("\\x{X:0>2}", .{char});
                },
                else => try escaped.append(char),
            }
        }

        return self.allocator.dupe(u8, escaped.items);
    }
};
