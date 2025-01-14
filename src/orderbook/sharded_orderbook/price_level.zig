const std = @import("std");
const builtin = @import("builtin");

// Cache line size optimization
const CACHE_LINE_SIZE = 64;
const VECTOR_WIDTH = if (builtin.cpu.arch == .x86_64) @as(usize, 8) else @as(usize, 4);

// Cache-aligned price level structure
pub const PriceLevel = struct {
    total_volume: u64 align(CACHE_LINE_SIZE),
    order_count: u32 align(8),
    padding: u32 = 0, // Ensure alignment
    last_update_timestamp: i64 align(8),

    // SIMD-friendly volume array for batch processing
    volume_buffer: [VECTOR_WIDTH]u64 align(32) = [_]u64{0} ** VECTOR_WIDTH,
    volume_buffer_count: usize = 0,

    pub fn init() PriceLevel {
        return .{
            .total_volume = 0,
            .order_count = 0,
            .last_update_timestamp = std.time.timestamp(),
        };
    }

    // Optimized batch volume update
    pub fn updateVolumeBatch(self: *PriceLevel, volumes: []const u64) void {
        var i: usize = 0;
        while (i + VECTOR_WIDTH <= volumes.len) : (i += VECTOR_WIDTH) {
            // SIMD addition of volumes
            inline for (0..VECTOR_WIDTH) |j| {
                self.total_volume += volumes[i + j];
            }
        }
        // Handle remaining volumes
        while (i < volumes.len) : (i += 1) {
            self.total_volume += volumes[i];
        }
        self.last_update_timestamp = std.time.timestamp();
    }

    // Buffer small volume updates for batch processing
    pub fn bufferVolumeUpdate(self: *PriceLevel, volume: u64) void {
        self.volume_buffer[self.volume_buffer_count] = volume;
        self.volume_buffer_count += 1;

        if (self.volume_buffer_count == VECTOR_WIDTH) {
            self.flushVolumeBuffer();
        }
    }

    // Process buffered volumes using SIMD
    pub fn flushVolumeBuffer(self: *PriceLevel) void {
        if (self.volume_buffer_count == 0) return;

        var total: u64 = 0;
        inline for (0..VECTOR_WIDTH) |i| {
            if (i < self.volume_buffer_count) {
                total += self.volume_buffer[i];
            }
        }
        self.total_volume += total;
        self.volume_buffer_count = 0;
        self.last_update_timestamp = std.time.timestamp();
    }
};

// Optimized price level map operations
pub fn updatePriceLevel(levels: anytype, price: u64, volume_delta: i64, count_delta: i32) !void {
    var level = try levels.getOrPut(price);
    if (!level.found_existing) {
        level.value_ptr.* = PriceLevel.init();
    }

    if (volume_delta > 0) {
        level.value_ptr.bufferVolumeUpdate(@intCast(volume_delta));
    } else {
        level.value_ptr.total_volume = if (@as(u64, @intCast(-volume_delta)) > level.value_ptr.total_volume)
            0
        else
            level.value_ptr.total_volume - @as(u64, @intCast(-volume_delta));
    }

    const new_count = @as(i32, @intCast(level.value_ptr.order_count)) + count_delta;
    level.value_ptr.order_count = if (new_count < 0) 0 else @intCast(new_count);

    // Remove empty levels
    if (level.value_ptr.total_volume == 0 and level.value_ptr.order_count == 0) {
        _ = levels.remove(price);
    } else {
        level.value_ptr.flushVolumeBuffer();
    }
}
