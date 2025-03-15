const std = @import("std");
const url_validator = @import("url_validator.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize URL validator with default trusted domains
    var validator = url_validator.UrlValidator.initDefault(allocator);

    // Get message from command line or use default test message
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const message = if (args.len > 1) 
        args[1] 
    else 
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

    // Validate the message
    const result = try validator.validateNotification(message);
    defer {
        for (result.suspicious_urls) |url| {
            allocator.free(url);
        }
        allocator.free(result.suspicious_urls);
    }

    // Print validation result
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n=== Phishing Detection Results ===\n\n", .{});
    
    if (result.is_valid) {
        try stdout.print("✅ Message appears to be legitimate. No suspicious URLs detected.\n", .{});
    } else {
        try stdout.print("⚠️ WARNING: Potential phishing attempt detected!\n\n", .{});
        try stdout.print("The following suspicious URLs were found:\n", .{});
        
        for (result.suspicious_urls) |url| {
            try stdout.print("  - {s}\n", .{url});
        }
        
        try stdout.print("\nRecommendations:\n", .{});
        try stdout.print("  - Do not click on these links\n", .{});
        try stdout.print("  - Do not provide any personal information\n", .{});
        try stdout.print("  - Contact the purported sender through official channels\n", .{});
        try stdout.print("  - Report this message as phishing\n", .{});
    }
}