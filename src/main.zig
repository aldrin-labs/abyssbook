const std = @import("std");
const bench = @import("bench.zig");

pub fn main() !void {
    try bench.runBenchmarks();
}
