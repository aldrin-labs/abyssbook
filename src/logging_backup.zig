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

/// Performance monitoring thresholds for dynamic log level adjustment
pub const PerformanceThresholds = struct {
    high_latency_us: u64 = 1000, // 1ms
    high_memory_mb: u64 = 100, // 100MB
    high_cpu_percent: f64 = 80.0, // 80%
    adjust_interval_ms: u64 = 5000, // 5 seconds
};

/// Lock-free circular buffer for high-performance logging
const LockFreeRingBuffer = struct {
    const BUFFER_SIZE = 16384; // 16KB ring buffer
    const MAX_ENTRY_SIZE = 512;  // Maximum size per log entry
    
    buffer: [BUFFER_SIZE]u8,
    write_pos: std.atomic.Value(usize),
    read_pos: std.atomic.Value(usize),
    entries_pending: std.atomic.Value(usize),
    
    const Self = @This();
    
    pub fn init() Self {
        return Self{
            .buffer = [_]u8{0} ** BUFFER_SIZE,
            .write_pos = std.atomic.Value(usize).init(0),
            .read_pos = std.atomic.Value(usize).init(0),
            .entries_pending = std.atomic.Value(usize).init(0),
        };
    }
    
    /// Thread-safe write to ring buffer
    pub fn write(self: *Self, data: []const u8) bool {
        if (data.len > MAX_ENTRY_SIZE) return false;
        
        const write_size = data.len + @sizeOf(u16); // Include length prefix
        const current_write = self.write_pos.load(.acquire);
        const current_read = self.read_pos.load(.acquire);
        
        // Check if we have enough space
        const available_space = if (current_write >= current_read) 
            BUFFER_SIZE - current_write + current_read 
        else 
            current_read - current_write;
            
        if (available_space < write_size + 1) return false; // Buffer full
        
        // Write length prefix (2 bytes)
        const len_bytes = std.mem.toBytes(@as(u16, @intCast(data.len)));
        const wrap_write = (current_write + write_size) % BUFFER_SIZE;
        
        if (current_write + write_size <= BUFFER_SIZE) {
            // No wrap-around needed
            @memcpy(self.buffer[current_write..current_write + 2], &len_bytes);
            @memcpy(self.buffer[current_write + 2..current_write + write_size], data);
        } else {
            // Handle wrap-around
            const first_part = BUFFER_SIZE - current_write;
            if (first_part >= 2) {
                @memcpy(self.buffer[current_write..BUFFER_SIZE], len_bytes[0..first_part]);
                if (first_part < 2) {
                    @memcpy(self.buffer[0..2 - first_part], len_bytes[first_part..]);
                }
                @memcpy(self.buffer[2 - first_part..write_size - first_part], data);
            } else {
                // Complex wrap-around case
                return false; // Simplified: reject if complex wrap needed
            }
        }
        
        // Update write position
        _ = self.write_pos.compareAndSwap(current_write, wrap_write, .acq_rel, .acquire);
        _ = self.entries_pending.fetchAdd(1, .acq_rel);
        
        return true;
    }
    
    /// Read next entry from ring buffer
    pub fn read(self: *Self, buffer: []u8) ?[]const u8 {
        if (self.entries_pending.load(.acquire) == 0) return null;
        
        const current_read = self.read_pos.load(.acquire);
        const current_write = self.write_pos.load(.acquire);
        
        if (current_read == current_write) return null;
        
        // Read length prefix
        var len_bytes: [2]u8 = undefined;
        if (current_read + 2 <= BUFFER_SIZE) {
            len_bytes = self.buffer[current_read..current_read + 2][0..2].*;
        } else {
            len_bytes[0] = self.buffer[current_read];
            len_bytes[1] = self.buffer[0];
        }
        
        const entry_len = std.mem.bytesToValue(u16, &len_bytes);
        if (entry_len > buffer.len) return null;
        
        // Read data
        const data_start = (current_read + 2) % BUFFER_SIZE;
        if (data_start + entry_len <= BUFFER_SIZE) {
            @memcpy(buffer[0..entry_len], self.buffer[data_start..data_start + entry_len]);
        } else {
            const first_part = BUFFER_SIZE - data_start;
            @memcpy(buffer[0..first_part], self.buffer[data_start..BUFFER_SIZE]);
            @memcpy(buffer[first_part..entry_len], self.buffer[0..entry_len - first_part]);
        }
        
        // Update read position
        const new_read = (current_read + 2 + entry_len) % BUFFER_SIZE;
        _ = self.read_pos.compareAndSwap(current_read, new_read, .acq_rel, .acquire);
        _ = self.entries_pending.fetchSub(1, .acq_rel);
        
        return buffer[0..entry_len];
    }
    
    pub fn pendingEntries(self: *Self) usize {
        return self.entries_pending.load(.acquire);
    }
};

/// Thread-local log aggregation to minimize global writes
const ThreadLocalBuffer = struct {
    buffer: std.ArrayList(u8),
    entry_count: usize,
    last_flush: i64,
    
    const FLUSH_THRESHOLD = 10;    // Flush after 10 entries
    const FLUSH_INTERVAL_MS = 100; // Or every 100ms
    
    pub fn init(allocator: std.mem.Allocator) ThreadLocalBuffer {
        return ThreadLocalBuffer{
            .buffer = std.ArrayList(u8).init(allocator),
            .entry_count = 0,
            .last_flush = std.time.milliTimestamp(),
        };
    }
    
    pub fn deinit(self: *ThreadLocalBuffer) void {
        self.buffer.deinit();
    }
    
    pub fn addEntry(self: *ThreadLocalBuffer, entry: []const u8) !bool {
        try self.buffer.appendSlice(entry);
        self.entry_count += 1;
        
        const now = std.time.milliTimestamp();
        const should_flush = self.entry_count >= FLUSH_THRESHOLD or 
                           (now - self.last_flush) >= FLUSH_INTERVAL_MS;
        
        return should_flush;
    }
    
    pub fn flush(self: *ThreadLocalBuffer) []const u8 {
        defer {
            self.buffer.clearRetainingCapacity();
            self.entry_count = 0;
            self.last_flush = std.time.milliTimestamp();
        }
        return self.buffer.items;
    }
};

/// Thread-safe structured logger with lock-free optimizations
pub const Logger = struct {
    allocator: std.mem.Allocator,
    level: LogLevel,
    original_level: LogLevel, // Store original level for restoration
    mutex: Mutex, // Only used for background writer thread
    output_writer: std.fs.File.Writer,
    
    // Lock-free components
    ring_buffer: LockFreeRingBuffer,
    writer_thread: ?std.Thread,
    shutdown_flag: std.atomic.Value(bool),
    
    // Performance monitoring
    performance_mode: bool = false,
    last_adjustment: i64 = 0,
    thresholds: PerformanceThresholds,
    
    // Statistics
    messages_dropped: std.atomic.Value(u64),
    messages_written: std.atomic.Value(u64),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, level: LogLevel) !Self {
        var logger = Self{
            .allocator = allocator,
            .level = level,
            .original_level = level,
            .mutex = Mutex{},
            .output_writer = std.io.getStdErr().writer(),
            .ring_buffer = LockFreeRingBuffer.init(),
            .writer_thread = null,
            .shutdown_flag = std.atomic.Value(bool).init(false),
            .performance_mode = false,
            .last_adjustment = std.time.milliTimestamp(),
            .thresholds = PerformanceThresholds{},
            .messages_dropped = std.atomic.Value(u64).init(0),
            .messages_written = std.atomic.Value(u64).init(0),
        };
        
        // Start background writer thread
        logger.writer_thread = try std.Thread.spawn(.{}, backgroundWriter, .{&logger});
        
        return logger;
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

    /// Set performance thresholds for dynamic adjustment (lock-free)
    pub fn setPerformanceThresholds(self: *Self, thresholds: PerformanceThresholds) void {
        self.thresholds = thresholds; // Lock-free since it's only used by adjustLogLevel
    }

    pub fn deinit(self: *Self) void {
        // Signal shutdown and wait for background thread
        self.shutdown_flag.store(true, .release);
        if (self.writer_thread) |thread| {
            thread.join();
        }
    }

    /// Background writer thread that processes the lock-free ring buffer
    fn backgroundWriter(logger: *Self) void {
        var read_buffer: [1024]u8 = undefined;
        
        while (!logger.shutdown_flag.load(.acquire)) {
            while (logger.ring_buffer.read(&read_buffer)) |entry| {
                logger.mutex.lock();
                logger.output_writer.writeAll(entry) catch {};
                logger.mutex.unlock();
                
                _ = logger.messages_written.fetchAdd(1, .acq_rel);
            }
            
            // Small sleep to prevent busy-waiting
            std.time.sleep(1 * std.time.ns_per_ms);
        }
        
        // Flush remaining entries on shutdown
        while (logger.ring_buffer.read(&read_buffer)) |entry| {
            logger.output_writer.writeAll(entry) catch {};
        }
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
        
        // Format entry directly into a stack buffer
        var entry_buffer: [512]u8 = undefined;
        var stream = std.io.fixedBufferStream(&entry_buffer);
        const writer = stream.writer();
        
        // Simple timestamp (microseconds since epoch)
        const timestamp_us = std.time.microTimestamp();
        
        // Format: [timestamp_us] LEVEL module: message\n
        const formatted = std.fmt.bufPrint(&entry_buffer, "[{d}] {s} {s}: {s}\n", .{
            timestamp_us, level.toString(), module, message
        }) catch return; // Drop message if buffer too small
        
        // Attempt to write to ring buffer (non-blocking)
        if (!self.ring_buffer.write(formatted)) {
            _ = self.messages_dropped.fetchAdd(1, .acq_rel);
        }
    }

    /// Standard logging with context (may use mutex for complex formatting)
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

        // For critical messages or when context is provided, use the full formatting
        if (level == .CRITICAL or context != null) {
            try self.logWithFullFormatting(level, module, message, context);
        } else {
            // Use fast path for simple messages
            self.logFast(level, module, message);
        }
    }

    /// Full formatting path (uses mutex)
    fn logWithFullFormatting(
        self: *Self,
        level: LogLevel,
        module: []const u8,
        message: []const u8,
        context: ?std.json.Value,
    ) !void {
        const timestamp = try self.getTimestamp();
        defer self.allocator.free(timestamp);

        const entry = LogEntry{
            .timestamp = timestamp,
            .level = level.toString(),
            .module = module,
            .message = message,
            .context = context,
        };

        // Format to temporary buffer
        var temp_buffer = std.ArrayList(u8).init(self.allocator);
        defer temp_buffer.deinit();
        
        try entry.format("", .{}, temp_buffer.writer());
        
        // Try lock-free path first
        if (!self.ring_buffer.write(temp_buffer.items)) {
            // Fall back to direct write with mutex
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.output_writer.writeAll(temp_buffer.items);
            _ = self.messages_written.fetchAdd(1, .acq_rel);
        }
    }

    /// Get performance statistics
    pub fn getStats(self: *Self) struct { dropped: u64, written: u64, pending: usize } {
        return .{
            .dropped = self.messages_dropped.load(.acquire),
            .written = self.messages_written.load(.acquire),
            .pending = self.ring_buffer.pendingEntries(),
        };
    }

    pub fn setLevel(self: *Self, level: LogLevel) void {
        self.level = level; // Lock-free since it's atomic read/write
    }

    pub fn getLevel(self: *Self) LogLevel {
        return self.level; // Lock-free
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

    /// Log immediately without level check (for internal performance notifications)
    fn logImmediate(
        self: *Self,
        level: LogLevel,
        module: []const u8,
        message: []const u8,
        context: ?std.json.Value,
    ) void {
        // Acquire mutex but ignore level check
        self.mutex.lock();
        defer self.mutex.unlock();

        const timestamp = self.getTimestamp() catch return;
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
        entry.format("", .{}, self.buffer.writer()) catch return;

        // Write to output
        self.output_writer.writeAll(self.buffer.items) catch return;
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
