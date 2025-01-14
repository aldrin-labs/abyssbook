const std = @import("std");
const builtin = @import("builtin");
const perf = @import("perf_monitor.zig");

// Enhanced SIMD configuration
const VECTOR_WIDTH = if (builtin.cpu.arch == .x86_64) @as(usize, 8) else @as(usize, 4);
const BITONIC_SORT_SIZE = VECTOR_WIDTH * 8; // Increased for better vectorization
const CACHE_LINE_SIZE = 64;
const PREFETCH_DISTANCE = 8;

pub fn SortContext(comptime T: type) type {
    return struct {
        items: []T,
        scratch: []T,
        is_ascending: bool,
        metrics: ?*perf.SortMetrics,

        const Self = @This();

        pub fn init(items: []T, scratch: []T, is_ascending: bool, metrics: ?*perf.SortMetrics) Self {
            return .{
                .items = items,
                .scratch = scratch,
                .is_ascending = is_ascending,
                .metrics = metrics,
            };
        }

        // Prefetch next cache lines
        inline fn prefetchNext(self: *Self, idx: usize) void {
            if (idx + PREFETCH_DISTANCE < self.items.len) {
                const addr = @intFromPtr(&self.items[idx + PREFETCH_DISTANCE]);
                asm volatile ("prefetcht0 (%[addr])"
                    : // no outputs
                    : [addr] "r" (addr),
                );
            }
        }
    };
}

// SIMD-optimized bitonic sort with cache prefetching
pub fn bitonicSort(comptime T: type, ctx: *SortContext(T)) void {
    const len = ctx.items.len;
    if (len <= 1) return;

    const Vector = @Vector(VECTOR_WIDTH, T);
    var step: usize = 2;

    // Process VECTOR_WIDTH elements at a time
    while (step <= len) : (step *= 2) {
        var substep = step / 2;
        while (substep > 0) : (substep /= 2) {
            if (ctx.metrics) |m| {
                m.bitonic_phases += 1;
            }

            var i: usize = 0;
            while (i + VECTOR_WIDTH <= len) : (i += VECTOR_WIDTH) {
                // Prefetch next cache line
                ctx.prefetchNext(i);

                const vec: Vector = ctx.items[i..][0..VECTOR_WIDTH].*;
                const reversed = @shuffle(T, vec, undefined, blk: {
                    var indices: [VECTOR_WIDTH]i32 = undefined;
                    for (&indices, 0..) |*idx, j| {
                        idx.* = @intCast(VECTOR_WIDTH - 1 - j);
                    }
                    break :blk indices;
                });

                const compare_vec = if ((i / substep) % 2 == 0) vec else reversed;
                const min_vec = @min(vec, compare_vec);
                const max_vec = @max(vec, compare_vec);
                const result = if (ctx.is_ascending) min_vec else max_vec;

                if (ctx.metrics) |m| {
                    m.comparisons += VECTOR_WIDTH;
                }

                var needs_swap = false;
                for (0..VECTOR_WIDTH) |j| {
                    if (ctx.items[i + j] != result[j]) {
                        needs_swap = true;
                    }
                    ctx.items[i + j] = result[j];
                }

                if (ctx.metrics) |m| {
                    if (needs_swap) {
                        m.swaps += 1;
                    }
                }
            }

            // Handle remaining elements
            while (i < len) : (i += 1) {
                const j = i ^ substep;
                if (j > i and j < len) {
                    if (ctx.metrics) |m| {
                        m.comparisons += 1;
                    }

                    const should_swap = if (ctx.is_ascending)
                        ctx.items[i] > ctx.items[j]
                    else
                        ctx.items[i] < ctx.items[j];

                    if (should_swap) {
                        if (ctx.metrics) |m| {
                            m.swaps += 1;
                        }
                        const temp = ctx.items[i];
                        ctx.items[i] = ctx.items[j];
                        ctx.items[j] = temp;
                    }
                }
            }
        }
    }
}

// SIMD-optimized merge for merge sort
fn vectorizedMerge(comptime T: type, ctx: *SortContext(T), start: usize, mid: usize, end: usize, metrics: ?*perf.SortMetrics) void {
    const Vector = @Vector(VECTOR_WIDTH, T);
    var left = start;
    var right = mid;
    var out = start;

    // Handle full vector merges
    while (left + VECTOR_WIDTH <= mid and right + VECTOR_WIDTH <= end) {
        const left_vec: Vector = ctx.items[left..][0..VECTOR_WIDTH].*;
        const right_vec: Vector = ctx.items[right..][0..VECTOR_WIDTH].*;

        if (metrics) |m| {
            m.comparisons += VECTOR_WIDTH;
        }

        const compare = if (ctx.is_ascending)
            left_vec <= right_vec
        else
            left_vec >= right_vec;

        const merged = @select(T, compare, left_vec, right_vec);
        for (0..VECTOR_WIDTH) |i| {
            ctx.scratch[out + i] = merged[i];
        }

        // Update pointers based on comparison results
        var advance_left: usize = 0;
        var advance_right: usize = 0;
        for (0..VECTOR_WIDTH) |i| {
            if (compare[i]) {
                advance_left += 1;
            } else {
                advance_right += 1;
            }
        }

        left += advance_left;
        right += advance_right;
        out += VECTOR_WIDTH;
    }

    // Handle remaining elements
    while (left < mid and right < end) {
        if (metrics) |m| {
            m.comparisons += 1;
        }

        const should_take_left = if (ctx.is_ascending)
            ctx.items[left] <= ctx.items[right]
        else
            ctx.items[left] >= ctx.items[right];

        if (should_take_left) {
            ctx.scratch[out] = ctx.items[left];
            left += 1;
        } else {
            ctx.scratch[out] = ctx.items[right];
            right += 1;
        }
        out += 1;
    }

    // Copy remaining elements
    while (left < mid) : ({
        left += 1;
        out += 1;
    }) {
        ctx.scratch[out] = ctx.items[left];
    }
    while (right < end) : ({
        right += 1;
        out += 1;
    }) {
        ctx.scratch[out] = ctx.items[right];
    }

    // Copy back to original array
    @memcpy(ctx.items[start..end], ctx.scratch[start..end]);
}

// SIMD-optimized merge sort
fn mergeSortInternal(comptime T: type, ctx: *SortContext(T), start: usize, end: usize, metrics: ?*perf.SortMetrics) void {
    const len = end - start;
    if (len <= BITONIC_SORT_SIZE) {
        // Use bitonic sort for small chunks
        var subctx = SortContext(T).init(ctx.items[start..end], ctx.scratch[start..end], ctx.is_ascending, ctx.metrics);
        bitonicSort(T, &subctx);
        return;
    }

    const mid = start + (len / 2);
    mergeSortInternal(T, ctx, start, mid, metrics);
    mergeSortInternal(T, ctx, mid, end, metrics);
    vectorizedMerge(T, ctx, start, mid, end, metrics);

    if (metrics) |m| {
        m.merge_operations += 1;
    }
}

pub fn simdSort(comptime T: type, items: []T, scratch: []T, is_ascending: bool, metrics: ?*perf.SortMetrics) void {
    if (items.len <= 1) return;
    var ctx = SortContext(T).init(items, scratch, is_ascending, metrics);
    mergeSortInternal(T, &ctx, 0, items.len, metrics);
}
