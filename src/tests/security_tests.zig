const std = @import("std");
const cli = @import("cli");
const testing = std.testing;

// Security-focused tests for CLI argument parsing
// These tests ensure that the CLI handles edge cases and potential
// security vulnerabilities safely.

test "CLI security - malformed arguments" {
    var registry = cli.init();
    defer registry.deinit();

    // Test with empty arguments - should show help and succeed
    {
        const args = &[_][]const u8{};
        // Empty arguments should show help and not throw an error
        cli.execute(&registry, args) catch |err| {
            // If an error is thrown, it should be UnknownCommand
            std.debug.print("Unexpected error with empty args: {}\n", .{err});
            try testing.expect(err == error.UnknownCommand);
        };
    }

    // Test with very long arguments (potential buffer overflow)
    {
        var long_arg: [1024]u8 = undefined;
        @memset(&long_arg, 'A');
        const args = &[_][]const u8{ "abyssbook", &long_arg };

        cli.execute(&registry, args) catch |err| {
            // Should handle gracefully, not crash
            std.debug.print("Long argument test error (expected): {}\n", .{err});
            try testing.expect(err == error.UnknownCommand);
        };
    }

    // Test with null bytes in arguments
    {
        const args = &[_][]const u8{ "abyssbook", "test\x00injection" };
        cli.execute(&registry, args) catch |err| {
            try testing.expect(err == error.UnknownCommand);
        };
    }
}

test "CLI security - command injection attempts" {
    var registry = cli.init();
    defer registry.deinit();

    // Test shell injection patterns
    const injection_attempts = [_][]const u8{
        "; rm -rf /",
        "| cat /etc/passwd",
        "&& malicious_command",
        "`whoami`",
        "$(malicious_command)",
        "../../../etc/passwd",
        "\\x41\\x41\\x41\\x41",
    };

    for (injection_attempts) |injection| {
        const args = &[_][]const u8{ "abyssbook", injection };
        cli.execute(&registry, args) catch |err| {
            // All should fail safely without executing injection
            try testing.expect(err == error.UnknownCommand);
        };
    }
}

test "CLI security - special characters handling" {
    var registry = cli.init();
    defer registry.deinit();

    const special_chars = [_][]const u8{
        "test\x00", // null byte
        "test\n", // newline
        "test\r", // carriage return
        "test\t", // tab
        "test\x1b", // escape character
        "test\xff", // high byte
        "test'test", // single quote
        "test\"test", // double quote
        "test\\test", // backslash
    };

    for (special_chars) |special| {
        const args = &[_][]const u8{ "abyssbook", special };
        cli.execute(&registry, args) catch |err| {
            try testing.expect(err == error.UnknownCommand);
        };
    }
}

test "CLI security - memory boundary tests" {
    var registry = cli.init();
    defer registry.deinit();

    // Test with maximum reasonable number of arguments
    var args_array: [100][]const u8 = undefined;
    args_array[0] = "abyssbook";
    for (1..100) |i| {
        args_array[i] = "arg";
    }

    cli.execute(&registry, &args_array) catch |err| {
        // Should handle gracefully
        try testing.expect(err == error.UnknownCommand);
    };
}

test "CLI security - unicode and encoding tests" {
    var registry = cli.init();
    defer registry.deinit();

    const unicode_tests = [_][]const u8{
        "test\u{1F600}", // emoji
        "test\u{0000}", // null unicode
        "test\u{FFFF}", // max unicode in BMP
        "тест", // cyrillic
        "测试", // chinese
        "🚀🦾", // emojis from issue description
    };

    for (unicode_tests) |unicode| {
        const args = &[_][]const u8{ "abyssbook", unicode };
        cli.execute(&registry, args) catch |err| {
            try testing.expect(err == error.UnknownCommand);
        };
    }
}
