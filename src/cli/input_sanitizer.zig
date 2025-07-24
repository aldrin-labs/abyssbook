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

    // Advanced dangerous patterns with regex-like matching
    const DANGEROUS_PATTERNS = [_][]const u8{
        // SQL Injection patterns (enhanced)
        "'; DROP TABLE",
        "' OR '1'='1",
        "' OR 1=1",
        "UNION SELECT",
        "UNION ALL SELECT",
        "'; --",
        "' UNION",
        "SELECT * FROM",
        "INSERT INTO",
        "UPDATE SET",
        "DELETE FROM",
        "CREATE TABLE",
        "ALTER TABLE",
        "' AND SLEEP(",
        "WAITFOR DELAY",
        "' OR EXTRACTVALUE(",
        "' OR UPDATEXML(",

        // Path traversal patterns (enhanced)
        "../",
        "..\\",
        "/..",
        "\\..",
        "/etc/passwd",
        "/etc/shadow",
        "/etc/hosts",
        "\\windows\\system32",
        "\\boot.ini",
        "%2e%2e%2f",
        "%2e%2e\\",
        "..%2f",
        "..%5c",
        "....//",
        "....\\\\",

        // Script injection patterns (enhanced)
        "<script>",
        "</script>",
        "<iframe",
        "<object",
        "<embed",
        "<link",
        "<meta",
        "javascript:",
        "vbscript:",
        "data:text/html",
        "data:application/",
        "onload=",
        "onerror=",
        "onclick=",
        "onmouseover=",
        "onfocus=",
        "eval(",
        "document.cookie",
        "window.location",
        "document.write",
        "innerHTML",
        "outerHTML",

        // Command injection patterns (enhanced)
        "$((",
        "`command`",
        "&&",
        "||",
        ";rm -rf",
        ";del /f",
        "|nc ",
        ">/dev/tcp",
        "2>&1",
        ">/dev/null",
        ";cat /etc/",
        ";type c:\\",
        "$(curl",
        "$(wget",
        "|bash",
        "|sh",
        "|cmd",
        "|powershell",

        // Protocol attacks (enhanced)
        "file://",
        "ftp://",
        "ldap://",
        "ldaps://",
        "data:",
        "gopher://",
        "dict://",
        "sftp://",
        "tftp://",
        "jar://",

        // Advanced evasion techniques
        "char(0x",
        "0x3c736372697074",
        "%3cscript",
        "&lt;script",
        "\\u003cscript",
        "\\x3cscript",
        "/**/",
        "--+",
        "#",
        "/*",
        "*/",
        "\\0",
        "\\r\\n",
        "%0a",
        "%0d",
        "%09",
        "%20",
    };

    // Advanced suspicious patterns with context-aware detection
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
        "debug",
        "test",
        "dev",
        "staging",
        "prod",
        "api_key",
        "private_key",
        "session",
        "cookie",
        "header",
        "authorization",
        "bearer",
        "oauth",
        "jwt",
        "credentials",
        "database",
        "db_",
        "connection",
        "conn_",
        "server",
        "host",
        "port",
        "endpoint",
        "url",
        "path",
        "directory",
        "folder",
        "file_",
        "tmp",
        "temp",
        "cache",
        "log",
        "error",
        "exception",
        "stack",
        "trace",
        "dump",
        "backup",
        "restore",
        "export",
        "import",
        "migration",
        "schema",
    };

    pub fn init(allocator: std.mem.Allocator, config: SanitizationConfig) Self {
        return Self{
            .allocator = allocator,
            .max_input_length = config.max_length,
            .strict_mode = config.strict_commands,
        };
    }

    /// Multi-stage sanitization process with advanced heuristics
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

        // Stage 2: Null byte and control character detection
        if (std.mem.indexOf(u8, input, "\x00")) |_| {
            try result.blocked_patterns.append(try self.allocator.dupe(u8, "Null byte detected"));
            result.security_level = .BLOCKED;
            result.cleaned_input = try self.allocator.dupe(u8, "");
            return result;
        }

        // Stage 3: Advanced pattern matching with ML-inspired heuristics
        const pattern_result = try self.detectAdvancedPatterns(input, &result);
        if (pattern_result == .BLOCKED) {
            result.security_level = .BLOCKED;
            result.cleaned_input = try self.allocator.dupe(u8, "");
            return result;
        }

        // Stage 4: Encoding detection and normalization
        const encoding_result = try self.detectEncodingAttacks(input, &result);
        if (encoding_result == .BLOCKED) {
            result.security_level = .BLOCKED;
            result.cleaned_input = try self.allocator.dupe(u8, "");
            return result;
        }

        // Stage 5: Contextual analysis
        const context_result = try self.analyzeContext(input, &result);
        if (context_result == .BLOCKED) {
            result.security_level = .BLOCKED;
            result.cleaned_input = try self.allocator.dupe(u8, "");
            return result;
        }

        // Stage 6: Character filtering and normalization
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

        // Stage 7: Command-specific validation
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

        // Stage 8: Final validation and statistical analysis
        const stats_result = try self.analyzeStatisticalPatterns(cleaned.items, &result);
        if (stats_result == .BLOCKED) {
            result.security_level = .BLOCKED;
            result.cleaned_input = try self.allocator.dupe(u8, "");
            return result;
        }

        // Update security level based on all analyses
        if (result.security_level == .SAFE and stats_result != .SAFE) {
            result.security_level = stats_result;
        }

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

        // Check if command is empty
        if (command.len == 0) {
            return .BLOCKED;
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
                0...8, 11...12, 14...31, 127...255 => {
                    try escaped.writer().print("\\x{X:0>2}", .{char});
                },
                else => try escaped.append(char),
            }
        }

        return self.allocator.dupe(u8, escaped.items);
    }

    /// Advanced pattern detection with machine learning inspired heuristics
    fn detectAdvancedPatterns(self: *Self, input: []const u8, result: *SanitizationResult) !SecurityLevel {
        var max_level: SecurityLevel = .SAFE;

        // Phase 1: Direct pattern matching
        for (DANGEROUS_PATTERNS) |pattern| {
            if (std.ascii.indexOfIgnoreCase(input, pattern)) |_| {
                try result.blocked_patterns.append(try std.fmt.allocPrint(self.allocator, "Dangerous pattern: {s}", .{pattern}));
                return .BLOCKED;
            }
        }

        // Phase 2: Suspicious pattern detection with scoring
        var suspicion_score: f32 = 0.0;
        for (SUSPICIOUS_PATTERNS) |pattern| {
            if (std.ascii.indexOfIgnoreCase(input, pattern)) |_| {
                try result.warnings.append(try std.fmt.allocPrint(self.allocator, "Suspicious pattern detected: {s}", .{pattern}));
                suspicion_score += 1.0;
                max_level = .SUSPICIOUS;
            }
        }

        // Phase 3: Pattern combination analysis
        if (suspicion_score >= 3.0) {
            try result.blocked_patterns.append(try self.allocator.dupe(u8, "Multiple suspicious patterns detected"));
            return .BLOCKED;
        }

        // Phase 4: Fuzzy pattern matching for evasion attempts
        const fuzzy_level = try self.detectFuzzyPatterns(input, result);
        if (fuzzy_level == .BLOCKED) return .BLOCKED;
        if (fuzzy_level == .DANGEROUS) max_level = .DANGEROUS;

        return max_level;
    }

    /// Detect encoding-based attacks (URL encoding, hex encoding, etc.)
    fn detectEncodingAttacks(self: *Self, input: []const u8, result: *SanitizationResult) !SecurityLevel {
        var encoding_level: SecurityLevel = .SAFE;

        // Check for excessive URL encoding
        var url_encoded_count: usize = 0;
        var i: usize = 0;
        while (i < input.len) {
            if (input[i] == '%' and i + 2 < input.len) {
                if (std.ascii.isHex(input[i + 1]) and std.ascii.isHex(input[i + 2])) {
                    url_encoded_count += 1;
                    i += 3;
                } else {
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        if (url_encoded_count > input.len / 4) {
            try result.blocked_patterns.append(try std.fmt.allocPrint(self.allocator, "Excessive URL encoding: {d} encoded chars", .{url_encoded_count}));
            return .BLOCKED;
        } else if (url_encoded_count > 5) {
            try result.warnings.append(try std.fmt.allocPrint(self.allocator, "URL encoding detected: {d} chars", .{url_encoded_count}));
            encoding_level = .SUSPICIOUS;
        }

        // Check for hex patterns that could be obfuscated commands
        if (std.mem.indexOf(u8, input, "0x")) |_| {
            var hex_count: usize = 0;
            var j: usize = 0;
            while (j < input.len - 1) {
                if (input[j] == '0' and input[j + 1] == 'x') {
                    hex_count += 1;
                    j += 2;
                } else {
                    j += 1;
                }
            }

            if (hex_count > 3) {
                try result.warnings.append(try std.fmt.allocPrint(self.allocator, "Multiple hex patterns: {d}", .{hex_count}));
                encoding_level = .SUSPICIOUS;
            }
        }

        return encoding_level;
    }

    /// Contextual analysis based on input structure and content
    fn analyzeContext(self: *Self, input: []const u8, result: *SanitizationResult) !SecurityLevel {
        var context_level: SecurityLevel = .SAFE;

        // Analyze command-like structures
        if (input.len > 0 and (input[0] == '/' or input[0] == '\\' or input[0] == '.')) {
            try result.warnings.append(try self.allocator.dupe(u8, "Path-like input detected"));
            context_level = .SUSPICIOUS;
        }

        // Check for script-like structures
        var bracket_count: usize = 0;
        var paren_count: usize = 0;
        var quote_count: usize = 0;

        for (input) |char| {
            switch (char) {
                '<', '>' => bracket_count += 1,
                '(', ')' => paren_count += 1,
                '\'', '"' => quote_count += 1,
                else => {},
            }
        }

        if (bracket_count > 4 and paren_count > 2) {
            try result.warnings.append(try self.allocator.dupe(u8, "Script-like structure detected"));
            context_level = .SUSPICIOUS;
        }

        // Check for SQL-like structures
        const sql_keywords = [_][]const u8{ "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE" };
        var sql_keyword_count: usize = 0;
        
        for (sql_keywords) |keyword| {
            if (std.ascii.indexOfIgnoreCase(input, keyword)) |_| {
                sql_keyword_count += 1;
            }
        }

        if (sql_keyword_count >= 2) {
            try result.blocked_patterns.append(try self.allocator.dupe(u8, "SQL-like command structure detected"));
            return .BLOCKED;
        }

        return context_level;
    }

    /// Statistical pattern analysis for anomaly detection
    fn analyzeStatisticalPatterns(self: *Self, input: []const u8, result: *SanitizationResult) !SecurityLevel {
        if (input.len == 0) return .SAFE;

        var stats_level: SecurityLevel = .SAFE;

        // Character frequency analysis
        var char_freq: [256]usize = [_]usize{0} ** 256;
        for (input) |char| {
            char_freq[char] += 1;
        }

        // Check for excessive repetition of any character
        for (char_freq, 0..) |freq, char| {
            if (freq > input.len / 2 and freq > 10) {
                try result.warnings.append(try std.fmt.allocPrint(self.allocator, "Excessive character repetition: '{c}' appears {d} times", .{ @as(u8, @intCast(char)), freq }));
                stats_level = .SUSPICIOUS;
            }
        }

        // Entropy analysis (simplified)
        const entropy = self.calculateEntropy(input);
        if (entropy < 1.0) {
            try result.warnings.append(try std.fmt.allocPrint(self.allocator, "Low entropy input: {d:.2}", .{entropy}));
            stats_level = .SUSPICIOUS;
        } else if (entropy > 7.0) {
            try result.warnings.append(try std.fmt.allocPrint(self.allocator, "High entropy input (possible encoded): {d:.2}", .{entropy}));
            stats_level = .SUSPICIOUS;
        }

        // Length-based anomaly detection
        if (input.len > 500 and input.len < 1000) {
            // Check for unusual patterns in long inputs
            var space_count: usize = 0;
            var special_char_count: usize = 0;
            
            for (input) |char| {
                if (char == ' ') space_count += 1;
                if (!std.ascii.isAlphanumeric(char) and char != ' ') special_char_count += 1;
            }

            if (space_count < input.len / 20) { // Very few spaces in long input
                try result.warnings.append(try self.allocator.dupe(u8, "Long input with minimal spacing (possible obfuscation)"));
                stats_level = .SUSPICIOUS;
            }

            if (special_char_count > input.len / 3) { // Too many special characters
                try result.warnings.append(try self.allocator.dupe(u8, "High special character density"));
                stats_level = .SUSPICIOUS;
            }
        }

        return stats_level;
    }

    /// Fuzzy pattern matching for evasion detection
    fn detectFuzzyPatterns(self: *Self, input: []const u8, result: *SanitizationResult) !SecurityLevel {
        var fuzzy_level: SecurityLevel = .SAFE;

        // Check for obfuscated script tags
        const script_variations = [_][]const u8{
            "s c r i p t",
            "s\tc\tr\ti\tp\tt",
            "script",
            "SCRIPT",
            "ScRiPt",
        };

        for (script_variations) |variation| {
            if (std.mem.indexOf(u8, input, variation)) |_| {
                try result.blocked_patterns.append(try std.fmt.allocPrint(self.allocator, "Obfuscated script pattern: {s}", .{variation}));
                return .BLOCKED;
            }
        }

        // Check for command injection with spaces
        const cmd_patterns = [_][]const u8{
            "r m",
            "d e l",
            "c a t",
            "t y p e",
        };

        for (cmd_patterns) |pattern| {
            if (std.mem.indexOf(u8, input, pattern)) |_| {
                try result.warnings.append(try std.fmt.allocPrint(self.allocator, "Spaced command pattern: {s}", .{pattern}));
                fuzzy_level = .DANGEROUS;
            }
        }

        return fuzzy_level;
    }

    /// Calculate Shannon entropy for input analysis
    fn calculateEntropy(self: *Self, input: []const u8) f64 {
        _ = self;
        if (input.len == 0) return 0.0;

        var char_freq: [256]f64 = [_]f64{0.0} ** 256;
        const len_f = @as(f64, @floatFromInt(input.len));

        // Count character frequencies
        for (input) |char| {
            char_freq[char] += 1.0;
        }

        // Calculate entropy
        var entropy: f64 = 0.0;
        for (char_freq) |freq| {
            if (freq > 0.0) {
                const prob = freq / len_f;
                entropy -= prob * @log(prob) / @log(2.0);
            }
        }

        return entropy;
    }
};
