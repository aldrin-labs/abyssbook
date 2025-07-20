const std = @import("std");
const Thread = std.Thread;
const Mutex = Thread.Mutex;

/// Log levels in order of severity
pub const LogLevel = enum(u8) {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
    CRITICAL = 4,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .DEBUG => "DEBUG",
            .INFO => "INFO",
            .WARN => "WARN",
            .ERROR => "ERROR",
            .CRITICAL => "CRITICAL",
        };
    }

    pub fn fromString(level_str: []const u8) ?LogLevel {
        if (std.mem.eql(u8, level_str, "debug")) return .DEBUG;
        if (std.mem.eql(u8, level_str, "info")) return .INFO;
        if (std.mem.eql(u8, level_str, "warn")) return .WARN;
        if (std.mem.eql(u8, level_str, "error")) return .ERROR;
        if (std.mem.eql(u8, level_str, "critical")) return .CRITICAL;
        return null;
    }
};

/// Log entry structure for JSON serialization
pub const LogEntry = struct {
    timestamp: []const u8,
    level: []const u8,
    module: []const u8,
    message: []const u8,
    context: ?std.json.Value = null,

    pub fn format(
        self: LogEntry,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        // Write JSON formatted log entry
        try writer.print("{{\"timestamp\":\"{s}\",\"level\":\"{s}\",\"module\":\"{s}\",\"message\":\"{s}\"", .{ self.timestamp, self.level, self.module, self.message });

        if (self.context) |_| {
            try writer.print(",\"context\":null", .{});
        }

        try writer.print("}}\n", .{});
    }
};

/// Thread-safe structured logger
pub const Logger = struct {
    allocator: std.mem.Allocator,
    level: LogLevel,
    mutex: Mutex,
    output_writer: std.fs.File.Writer,
    buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, level: LogLevel) !Self {
        return Self{
            .allocator = allocator,
            .level = level,
            .mutex = Mutex{},
            .output_writer = std.io.getStdErr().writer(),
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn setLevel(self: *Self, level: LogLevel) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.level = level;
    }

    pub fn getLevel(self: *Self) LogLevel {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.level;
    }

    /// Get current timestamp in ISO 8601 format
    fn getTimestamp(self: *Self) ![]const u8 {
        const timestamp = std.time.timestamp();
        const epoch_seconds = @as(u64, @intCast(timestamp));

        // Convert to a simple format for now
        const buffer = try self.allocator.alloc(u8, 32);
        const len = std.fmt.formatIntBuf(buffer, epoch_seconds, 10, .lower, .{});
        return buffer[0..len];
    }

    /// Internal logging function
    fn logInternal(
        self: *Self,
        level: LogLevel,
        module: []const u8,
        message: []const u8,
        context: ?std.json.Value,
    ) !void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) {
            return; // Skip if below current log level
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        const timestamp = try self.getTimestamp();
        defer self.allocator.free(timestamp);

        const entry = LogEntry{
            .timestamp = timestamp,
            .level = level.toString(),
            .module = module,
            .message = message,
            .context = context,
        };

        // Clear buffer and format entry
        self.buffer.clearRetainingCapacity();
        try entry.format("", .{}, self.buffer.writer());

        // Write to output
        try self.output_writer.writeAll(self.buffer.items);
    }

    /// Log with context (key-value pairs)
    pub fn logWithContext(
        self: *Self,
        level: LogLevel,
        module: []const u8,
        message: []const u8,
        context: anytype,
    ) !void {
        var json_context = std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) };
        defer json_context.object.deinit();

        // Convert context struct to JSON value
        inline for (std.meta.fields(@TypeOf(context))) |field| {
            const value = @field(context, field.name);
            const json_value = switch (@TypeOf(value)) {
                []const u8 => std.json.Value{ .string = value },
                i32, i64, u32, u64 => std.json.Value{ .integer = @as(i64, @intCast(value)) },
                f32, f64 => std.json.Value{ .float = @as(f64, @floatCast(value)) },
                bool => std.json.Value{ .bool = value },
                else => std.json.Value{ .string = "unsupported_type" },
            };
            try json_context.object.put(field.name, json_value);
        }

        try self.logInternal(level, module, message, json_context);
    }

    /// Simple logging without context
    pub fn log(self: *Self, level: LogLevel, module: []const u8, message: []const u8) !void {
        try self.logInternal(level, module, message, null);
    }

    /// Convenience methods for different log levels
    pub fn debug(self: *Self, module: []const u8, message: []const u8) !void {
        try self.log(.DEBUG, module, message);
    }

    pub fn info(self: *Self, module: []const u8, message: []const u8) !void {
        try self.log(.INFO, module, message);
    }

    pub fn warn(self: *Self, module: []const u8, message: []const u8) !void {
        try self.log(.WARN, module, message);
    }

    pub fn err(self: *Self, module: []const u8, message: []const u8) !void {
        try self.log(.ERROR, module, message);
    }

    pub fn critical(self: *Self, module: []const u8, message: []const u8) !void {
        try self.log(.CRITICAL, module, message);
    }

    /// Convenience methods with context
    pub fn debugWithContext(self: *Self, module: []const u8, message: []const u8, context: anytype) !void {
        try self.logWithContext(.DEBUG, module, message, context);
    }

    pub fn infoWithContext(self: *Self, module: []const u8, message: []const u8, context: anytype) !void {
        try self.logWithContext(.INFO, module, message, context);
    }

    pub fn warnWithContext(self: *Self, module: []const u8, message: []const u8, context: anytype) !void {
        try self.logWithContext(.WARN, module, message, context);
    }

    pub fn errWithContext(self: *Self, module: []const u8, message: []const u8, context: anytype) !void {
        try self.logWithContext(.ERROR, module, message, context);
    }

    pub fn criticalWithContext(self: *Self, module: []const u8, message: []const u8, context: anytype) !void {
        try self.logWithContext(.CRITICAL, module, message, context);
    }
};

/// Global logger instance
var global_logger: ?*Logger = null;
var global_allocator: ?std.mem.Allocator = null;

/// Initialize global logger
pub fn initGlobalLogger(allocator: std.mem.Allocator, level: LogLevel) !void {
    if (global_logger != null) {
        return; // Already initialized
    }

    global_allocator = allocator;
    global_logger = try allocator.create(Logger);
    global_logger.?.* = try Logger.init(allocator, level);
}

/// Deinitialize global logger
pub fn deinitGlobalLogger() void {
    if (global_logger) |logger| {
        logger.deinit();
        if (global_allocator) |allocator| {
            allocator.destroy(logger);
        }
        global_logger = null;
        global_allocator = null;
    }
}

/// Get global logger instance
pub fn getGlobalLogger() ?*Logger {
    return global_logger;
}

/// Convenience functions for global logger
pub fn setGlobalLogLevel(level: LogLevel) void {
    if (global_logger) |logger| {
        logger.setLevel(level);
    }
}

pub fn logGlobal(level: LogLevel, module: []const u8, message: []const u8) void {
    if (global_logger) |logger| {
        logger.log(level, module, message) catch |err| {
            std.debug.print("Logging error: {any}\n", .{err});
        };
    }
}

pub fn logGlobalWithContext(level: LogLevel, module: []const u8, message: []const u8, context: anytype) void {
    if (global_logger) |logger| {
        logger.logWithContext(level, module, message, context) catch |err| {
            std.debug.print("Logging error: {any}\n", .{err});
        };
    }
}

// Convenience macros for global logging
pub fn debugGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.DEBUG, module, message);
}

pub fn infoGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.INFO, module, message);
}

pub fn warnGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.WARN, module, message);
}

pub fn errorGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.ERROR, module, message);
}

pub fn criticalGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.CRITICAL, module, message);
}

// Convenience functions with context for global logging
pub fn debugGlobalWithContext(module: []const u8, message: []const u8, context: anytype) void {
    logGlobalWithContext(.DEBUG, module, message, context);
}

pub fn infoGlobalWithContext(module: []const u8, message: []const u8, context: anytype) void {
    logGlobalWithContext(.INFO, module, message, context);
}

pub fn warnGlobalWithContext(module: []const u8, message: []const u8, context: anytype) void {
    logGlobalWithContext(.WARN, module, message, context);
}

pub fn errorGlobalWithContext(module: []const u8, message: []const u8, context: anytype) void {
    logGlobalWithContext(.ERROR, module, message, context);
}

pub fn criticalGlobalWithContext(module: []const u8, message: []const u8, context: anytype) void {
    logGlobalWithContext(.CRITICAL, module, message, context);
}
