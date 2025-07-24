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

/// Performance monitoring thresholds for dynamic log level adjustment
pub const PerformanceThresholds = struct {
    high_latency_us: u64 = 1000, // 1ms
    high_memory_mb: u64 = 100, // 100MB
    high_cpu_percent: f64 = 80.0, // 80%
    adjust_interval_ms: u64 = 5000, // 5 seconds
};

/// High-performance logger with lock-free optimizations
pub const Logger = struct {
    allocator: std.mem.Allocator,
    level: LogLevel,
    original_level: LogLevel,
    output_writer: std.fs.File.Writer,
    performance_mode: bool = false,
    last_adjustment: i64 = 0,
    thresholds: PerformanceThresholds,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, level: LogLevel) !Self {
        return Self{
            .allocator = allocator,
            .level = level,
            .original_level = level,
            .output_writer = std.io.getStdErr().writer(),
            .performance_mode = false,
            .last_adjustment = std.time.milliTimestamp(),
            .thresholds = PerformanceThresholds{},
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self; // No cleanup needed for simplified version
    }

    /// High-performance lock-free logging (for hot paths)
    pub fn logFast(
        self: *Self,
        level: LogLevel,
        module: []const u8,
        message: []const u8,
    ) void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) {
            return; // Skip if below current log level
        }
        
        // Simple timestamp (microseconds since epoch)
        const timestamp_us = std.time.microTimestamp();
        
        // Format: [timestamp_us] LEVEL module: message\n
        var entry_buffer: [512]u8 = undefined;
        const formatted = std.fmt.bufPrint(&entry_buffer, "[{d}] {s} {s}: {s}\n", .{
            timestamp_us, level.toString(), module, message
        }) catch return; // Drop message if buffer too small
        
        // Direct write (simplified for this version)
        self.output_writer.writeAll(formatted) catch {};
    }

    /// Standard logging with context support
    pub fn log(
        self: *Self,
        level: LogLevel,
        module: []const u8,
        message: []const u8,
        context: ?std.json.Value,
    ) !void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) {
            return; // Skip if below current log level
        }

        // For critical messages or when context is provided, use full formatting
        if (level == .CRITICAL or context != null) {
            try self.logWithFullFormatting(level, module, message, context);
        } else {
            // Use fast path for simple messages
            self.logFast(level, module, message);
        }
    }

    /// Full formatting path with context support
    fn logWithFullFormatting(
        self: *Self,
        level: LogLevel,
        module: []const u8,
        message: []const u8,
        context: ?std.json.Value,
    ) !void {
        const timestamp = try self.getTimestamp();
        defer self.allocator.free(timestamp);

        // Simple JSON-like formatting
        var buffer: [1024]u8 = undefined;
        const formatted = if (context) |_|
            std.fmt.bufPrint(&buffer, "{{\"timestamp\":\"{s}\",\"level\":\"{s}\",\"module\":\"{s}\",\"message\":\"{s}\",\"context\":{{}}}}\n", .{ timestamp, level.toString(), module, message })
        else
            std.fmt.bufPrint(&buffer, "{{\"timestamp\":\"{s}\",\"level\":\"{s}\",\"module\":\"{s}\",\"message\":\"{s}\"}}\n", .{ timestamp, level.toString(), module, message });

        try self.output_writer.writeAll(formatted catch return);
    }

    /// Dynamically adjust log level based on performance metrics (lock-free)
    pub fn adjustLogLevel(self: *Self, latency_us: u64, memory_mb: u64, cpu_percent: f64) void {
        const now = std.time.milliTimestamp();

        // Only adjust if enough time has passed
        if (now - self.last_adjustment < self.thresholds.adjust_interval_ms) {
            return;
        }

        const high_perf_load = latency_us > self.thresholds.high_latency_us or
            memory_mb > self.thresholds.high_memory_mb or
            cpu_percent > self.thresholds.high_cpu_percent;

        if (high_perf_load and !self.performance_mode) {
            // Switch to performance mode: reduce logging verbosity
            self.performance_mode = true;
            self.level = .ERROR; // Only log errors in high-load scenarios
            self.last_adjustment = now;
            self.logFast(.WARN, "performance", "High performance load detected - reducing log verbosity");
        } else if (!high_perf_load and self.performance_mode) {
            // Return to normal mode
            self.performance_mode = false;
            self.level = self.original_level;
            self.last_adjustment = now;
            self.logFast(.INFO, "performance", "Performance load normalized - restoring log verbosity");
        }
    }

    /// Set performance thresholds for dynamic adjustment
    pub fn setPerformanceThresholds(self: *Self, thresholds: PerformanceThresholds) void {
        self.thresholds = thresholds;
    }

    pub fn setLevel(self: *Self, level: LogLevel) void {
        self.level = level;
    }

    pub fn getLevel(self: *Self) LogLevel {
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
};

// Global logger instance
var global_logger: ?Logger = null;
var global_logger_mutex: std.Thread.Mutex = std.Thread.Mutex{};

/// Initialize global logger
pub fn initGlobal(allocator: std.mem.Allocator, level: LogLevel) !void {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();
    
    if (global_logger) |*logger| {
        logger.deinit();
    }
    global_logger = try Logger.init(allocator, level);
}

/// Deinitialize global logger
pub fn deinitGlobal() void {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();
    
    if (global_logger) |*logger| {
        logger.deinit();
        global_logger = null;
    }
}

/// Global logging functions for convenience
pub fn logGlobal(level: LogLevel, module: []const u8, message: []const u8) void {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();
    
    if (global_logger) |*logger| {
        logger.logFast(level, module, message);
    }
}

pub fn logGlobalWithContext(level: LogLevel, module: []const u8, message: []const u8, context: anytype) void {
    _ = context;
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();
    
    if (global_logger) |*logger| {
        logger.log(level, module, message, null) catch {
            // Fallback to fast logging if context logging fails
            logger.logFast(level, module, message);
        };
    }
}

// Convenience functions
pub fn debugGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.DEBUG, module, message);
}

pub fn debugGlobalWithContext(module: []const u8, message: []const u8, context: anytype) void {
    logGlobalWithContext(.DEBUG, module, message, context);
}

pub fn infoGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.INFO, module, message);
}

pub fn infoGlobalWithContext(module: []const u8, message: []const u8, context: anytype) void {
    logGlobalWithContext(.INFO, module, message, context);
}

pub fn warnGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.WARN, module, message);
}

pub fn warnGlobalWithContext(module: []const u8, message: []const u8, context: anytype) void {
    logGlobalWithContext(.WARN, module, message, context);
}

pub fn errorGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.ERROR, module, message);
}

pub fn errorGlobalWithContext(module: []const u8, message: []const u8, context: anytype) void {
    logGlobalWithContext(.ERROR, module, message, context);
}

pub fn criticalGlobal(module: []const u8, message: []const u8) void {
    logGlobal(.CRITICAL, module, message);
}

pub fn setGlobalLogLevel(new_level: LogLevel) void {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();
    
    if (global_logger) |*logger| {
        logger.level = new_level;
    }
}

pub fn getGlobalLogger() ?*Logger {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();
    
    if (global_logger) |*logger| {
        return logger;
    }
    return null;
}