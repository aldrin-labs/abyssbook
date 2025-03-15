const std = @import("std");

pub const UrlValidationError = error{
    InvalidUrl,
    SuspiciousDomain,
    MismatchedDomain,
    PhishingAttempt,
};

pub const UrlValidator = struct {
    // List of trusted domains
    trusted_domains: []const []const u8,
    // Allocator for memory management
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, trusted_domains: []const []const u8) UrlValidator {
        return .{
            .trusted_domains = trusted_domains,
            .allocator = allocator,
        };
    }

    // Initialize with default trusted domains
    pub fn initDefault(allocator: std.mem.Allocator) UrlValidator {
        const default_domains = [_][]const u8{
            "github.com",
            "githubusercontent.com",
            "github.io",
            "aldrinlabs.com",
        };
        return init(allocator, &default_domains);
    }

    // Validate a URL to ensure it points to a trusted domain
    pub fn validateUrl(self: *const UrlValidator, url: []const u8) UrlValidationError!void {
        // Parse URL to extract domain
        const domain = try self.extractDomain(url);
        defer self.allocator.free(domain);

        // Check if domain is in trusted list
        for (self.trusted_domains) |trusted| {
            if (std.mem.endsWith(u8, domain, trusted)) {
                return;
            }
        }

        // Check for potential phishing attempts
        for (self.trusted_domains) |trusted| {
            if (self.isSimilarDomain(domain, trusted)) {
                return error.PhishingAttempt;
            }
        }

        return error.SuspiciousDomain;
    }

    // Extract domain from URL
    fn extractDomain(self: *const UrlValidator, url: []const u8) ![]u8 {
        // Find protocol separator
        const protocol_end = std.mem.indexOf(u8, url, "://");
        if (protocol_end == null) {
            return error.InvalidUrl;
        }

        // Extract domain part
        const domain_start = protocol_end.? + 3;
        const domain_end = std.mem.indexOfAnyPos(u8, url, domain_start, "/");
        const domain_slice = if (domain_end) |end|
            url[domain_start..end]
        else
            url[domain_start..];

        // Remove port if present
        const port_separator = std.mem.indexOf(u8, domain_slice, ":");
        const clean_domain = if (port_separator) |port|
            domain_slice[0..port]
        else
            domain_slice;

        // Return a copy of the domain
        return try self.allocator.dupe(u8, clean_domain);
    }

    // Check if a domain is similar to a trusted domain (potential phishing)
    fn isSimilarDomain(self: *const UrlValidator, domain: []const u8, trusted: []const u8) bool {
        _ = self;
        
        // Check for typosquatting (e.g., "githob.com" instead of "github.com")
        if (self.calculateLevenshteinDistance(domain, trusted) <= 2) {
            return true;
        }

        // Check for domain impersonation (e.g., "github-security.com")
        if (std.mem.indexOf(u8, domain, trusted) != null) {
            return true;
        }

        // Check for subdomain abuse (e.g., "github.phishing.com")
        const parts = std.mem.split(u8, domain, ".");
        var iter = parts.iterator();
        while (iter.next()) |part| {
            if (std.mem.eql(u8, part, trusted)) {
                return true;
            }
        }

        return false;
    }

    // Calculate Levenshtein distance between two strings
    fn calculateLevenshteinDistance(self: *const UrlValidator, s1: []const u8, s2: []const u8) usize {
        _ = self;
        
        if (s1.len == 0) return s2.len;
        if (s2.len == 0) return s1.len;

        var column = self.allocator.alloc(usize, s1.len + 1) catch |err| {
            std.debug.print("Failed to allocate memory: {}\n", .{err});
            return std.math.maxInt(usize);
        };
        defer self.allocator.free(column);

        for (0..s1.len + 1) |i| {
            column[i] = i;
        }

        for (0..s2.len) |j| {
            column[0] = j + 1;
            var last_diagonal: usize = j;

            for (0..s1.len) |i| {
                const old_diagonal = column[i + 1];
                if (s1[i] == s2[j]) {
                    column[i + 1] = last_diagonal;
                } else {
                    column[i + 1] = @min(column[i], @min(column[i + 1], last_diagonal)) + 1;
                }
                last_diagonal = old_diagonal;
            }
        }

        return column[s1.len];
    }

    // Validate a notification message to detect phishing attempts
    pub fn validateNotification(self: *const UrlValidator, message: []const u8) !struct { is_valid: bool, suspicious_urls: [][]const u8 } {
        var suspicious_urls = std.ArrayList([]const u8).init(self.allocator);
        defer suspicious_urls.deinit();

        // Extract URLs from message
        var urls = try self.extractUrls(message);
        defer {
            for (urls.items) |url| {
                self.allocator.free(url);
            }
            urls.deinit();
        }

        // Validate each URL
        for (urls.items) |url| {
            self.validateUrl(url) catch |err| {
                switch (err) {
                    error.PhishingAttempt, error.SuspiciousDomain => {
                        try suspicious_urls.append(try self.allocator.dupe(u8, url));
                    },
                    else => {},
                }
            };
        }

        // Return validation result
        if (suspicious_urls.items.len > 0) {
            return .{
                .is_valid = false,
                .suspicious_urls = try suspicious_urls.toOwnedSlice(),
            };
        } else {
            return .{
                .is_valid = true,
                .suspicious_urls = &[_][]const u8{},
            };
        }
    }

    // Extract URLs from a message
    fn extractUrls(self: *const UrlValidator, message: []const u8) !std.ArrayList([]u8) {
        var urls = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (urls.items) |url| {
                self.allocator.free(url);
            }
            urls.deinit();
        }

        // Simple URL extraction (can be improved with regex)
        const patterns = [_][]const u8{ "http://", "https://" };

        for (patterns) |pattern| {
            var start_idx: usize = 0;
            while (true) {
                const pattern_idx = std.mem.indexOfPos(u8, message, start_idx, pattern);
                if (pattern_idx == null) break;

                start_idx = pattern_idx.?;
                const end_idx = std.mem.indexOfAnyPos(u8, message, start_idx, " \t\n\r\"'<>()[]{}");
                const url_end = if (end_idx) |end| end else message.len;
                
                const url = try self.allocator.dupe(u8, message[start_idx..url_end]);
                try urls.append(url);

                start_idx = url_end;
            }
        }

        return urls;
    }

    // Free resources
    pub fn deinit(self: *UrlValidator, free_trusted_domains: bool) void {
        if (free_trusted_domains) {
            for (self.trusted_domains) |domain| {
                self.allocator.free(domain);
            }
            self.allocator.free(self.trusted_domains);
        }
    }
};

// Test the URL validator
test "URL Validator - Detect Phishing" {
    const testing = std.testing;
    var validator = UrlValidator.initDefault(testing.allocator);

    // Valid GitHub URL
    try testing.expectEqual(validator.validateUrl("https://github.com/user/repo"), void);

    // Phishing attempt with similar domain
    try testing.expectError(error.PhishingAttempt, validator.validateUrl("https://github-security.com/login"));

    // Suspicious domain
    try testing.expectError(error.SuspiciousDomain, validator.validateUrl("https://githubjobs-8p8e.onrender.com/"));
}

test "URL Validator - Notification Validation" {
    const testing = std.testing;
    var validator = UrlValidator.initDefault(testing.allocator);

    const phishing_message = 
        \\# Unusual Sign-in Activity Detected on Your GitHub Account
        \\
        \\We noticed a login from a new device:
        \\
        \\**Details of the Sign-in:**
        \\- **Location:** Reykjavik, Iceland
        \\- **IP Address:** 188.253.117.8
        \\- **Date and Time:** January 23, 2025 04:39 AM PST
        \\- **Device:** Unknown Device
        \\
        \\If this was you, please ignore this message. However, if you did not authorize this login, we recommend taking the following actions:
        \\
        \\**Secure Your Account:**
        \\1. **Change your password** immediately by visiting [GitHub's Password Change Page](https://githubjobs-8p8e.onrender.com/).
        \\2. **Review your active sessions** and revoke any unrecognized access:
        \\   - Go to your [GitHub Security Log](https://githubjobs-8p8e.onrender.com/) to see all recent activity.
        \\   - Look for and revoke suspicious sessions under [Authorized Applications and OAuth Tokens](https://githubjobs-8p8e.onrender.com/).
        \\3. **Enable or verify Two-Factor Authentication (2FA)** to add an extra layer of security:
        \\   - Check or set up 2FA in your [GitHub Two-Factor Authentication settings](https://githubjobs-8p8e.onrender.com/).
        \\
        \\**Contact Support:**
        \\If you feel your account security might be compromised or if you need further assistance, please contact GitHub Support at [GitHub Support](https://githubjobs-8p8e.onrender.com/).
        \\
        \\Thank you for your attention to this matter.
        \\
        \\Best regards,  
        \\The GitHub Security Team
    ;

    const result = try validator.validateNotification(phishing_message);
    try testing.expect(!result.is_valid);
    try testing.expect(result.suspicious_urls.len > 0);
    
    // Clean up
    for (result.suspicious_urls) |url| {
        testing.allocator.free(url);
    }
    testing.allocator.free(result.suspicious_urls);
}