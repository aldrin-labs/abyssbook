# AbyssBook API Reference

## Core Types

### OrderBook

```zig
pub const ShardedOrderbook = struct {
    // Core functionality
    pub fn init(allocator: std.mem.Allocator, shard_count: usize) !ShardedOrderbook;
    pub fn deinit(self: *ShardedOrderbook) void;
    
    // Basic operations
    pub fn placeOrder(self: *ShardedOrderbook, order: Order) !void;
    pub fn cancelOrder(self: *ShardedOrderbook, order_id: u64) !void;
    pub fn matchOrder(self: *ShardedOrderbook, side: OrderSide, price: u64, amount: u64) !MatchResult;
    
    // Advanced operations
    pub fn placeTWAPOrder(self: *ShardedOrderbook, params: TWAPParams) !void;
    pub fn placeTrailingStopOrder(self: *ShardedOrderbook, params: TrailingStopParams) !void;
    pub fn placePegOrder(self: *ShardedOrderbook, params: PegParams) !void;
    
    // Bulk operations
    pub fn bulkInsertOrders(self: *ShardedOrderbook, orders: []const Order) !void;
    pub fn bulkCancelOrders(self: *ShardedOrderbook, order_ids: []const u64) !void;
    
    // Market data
    pub fn getBestBid(self: *ShardedOrderbook) ?u64;
    pub fn getBestAsk(self: *ShardedOrderbook) ?u64;
    pub fn getVolume(self: *const ShardedOrderbook, side: OrderSide, price: u64) !u64;
};
```

### Order Types

```zig
pub const Order = struct {
    price: u64,
    amount: u64,
    id: u64,
    side: OrderSide,
    order_type: OrderType,
    flags: OrderFlags,
};

pub const OrderSide = enum {
    Buy,
    Sell,
};

pub const OrderType = enum {
    Limit,
    Market,
    StopLimit,
    StopMarket,
    TrailingStop,
    TWAP,
    Peg,
    Iceberg,
};

pub const OrderFlags = packed struct {
    is_maker: bool = false,
    post_only: bool = false,
    fill_or_kill: bool = false,
    immediate_or_cancel: bool = false,
    is_stop: bool = false,
    is_trailing_stop: bool = false,
    is_peg: bool = false,
    is_twap: bool = false,
};
```

### Advanced Order Parameters

```zig
pub const TWAPParams = struct {
    total_amount: u64,
    interval_seconds: u64,
    num_intervals: u64,
    start_time: i64,
    amount_per_interval: u64,
};

pub const TrailingStopParams = struct {
    distance: u64,
    last_trigger_price: u64,
    current_stop_price: u64,
};

pub const PegParams = struct {
    peg_type: PegType,
    offset: i64,
    limit_price: ?u64,
};

pub const PegType = enum {
    BestBid,
    BestAsk,
    Midpoint,
    LastTrade,
};
```

### Performance Monitoring

```zig
pub const PerformanceMonitor = struct {
    // Initialization
    pub fn init(allocator: std.mem.Allocator) PerformanceMonitor;
    pub fn deinit(self: *PerformanceMonitor) void;
    
    // Metrics recording
    pub fn recordMetric(self: *PerformanceMonitor, metric_type: []const u8, value: f64) !void;
    pub fn generateReport(self: *const PerformanceMonitor, writer: anytype) !void;
    
    // Performance data
    pub const SIMDMetrics = struct {
        vector_operations: usize,
        scalar_operations: usize,
        cache_misses: usize,
    };
    
    pub const BatchMetrics = struct {
        total_batches: usize,
        full_batches: usize,
        partial_batches: usize,
    };
};
```

### Solana Integration

```zig
pub const Processor = struct {
    // Initialization
    pub fn init(
        state: *OrderbookState,
        account_data: []u8,
        clock: i64,
        state_manager: *StateManager,
    ) Processor;
    
    // Instruction processing
    pub fn process(
        self: *Processor,
        instruction_data: []const u8,
        accounts: []const u8
    ) ProcessorError!void;
    
    // Token operations
    pub fn transferBaseTokens(
        self: *Processor,
        from: Pubkey,
        to: Pubkey,
        amount: u64
    ) !void;
    
    pub fn transferQuoteTokens(
        self: *Processor,
        from: Pubkey,
        to: Pubkey,
        amount: u64
    ) !void;
};
```

## Error Types

```zig
pub const OrderError = error{
    InvalidPrice,
    InvalidSize,
    OrderNotFound,
    InsufficientFunds,
    InvalidOrderType,
    InvalidSide,
    DuplicateOrder,
    OrderbookFull,
    PriceLevelFull,
};

pub const ProcessorError = error{
    InvalidInstruction,
    OrderbookNotInitialized,
    TokenAccountNotFound,
    InsufficientFunds,
    InvalidAccount,
    InvalidOwner,
    InvalidMint,
};
```

## Constants

```zig
// System constants
pub const CACHE_LINE_SIZE = 64;
pub const MAX_ORDERS_PER_BATCH = 128;
pub const PREFETCH_DISTANCE = 8;
pub const VECTOR_WIDTH = if (builtin.cpu.arch == .x86_64) 8 else 4;

// Market constants
pub const MIN_TICK_SIZE = 1;
pub const MAX_PRICE_LEVELS = 1_000_000;
pub const MAX_ORDERS_PER_LEVEL = 10_000;
pub const MAX_ORDER_SIZE = std.math.maxInt(u64);
```

## Type Definitions

```zig
// Basic types
pub const Price = u64;
pub const Amount = u64;
pub const OrderId = u64;
pub const Timestamp = i64;

// Complex types
pub const OrderKey = struct {
    price: Price,
    id: OrderId,
};

pub const PriceLevel = struct {
    total_volume: Amount,
    order_count: usize,
};

pub const MatchResult = struct {
    filled_amount: Amount,
    remaining_amount: Amount,
    execution_price: Price,
};
```

## Events

```zig
pub const OrderEvent = union(enum) {
    OrderPlaced: struct {
        order_id: OrderId,
        price: Price,
        amount: Amount,
        side: OrderSide,
    },
    OrderCancelled: struct {
        order_id: OrderId,
    },
    OrderMatched: struct {
        maker_id: OrderId,
        taker_id: OrderId,
        price: Price,
        amount: Amount,
    },
    OrderModified: struct {
        order_id: OrderId,
        new_price: Price,
        new_amount: Amount,
    },
};
```

## Best Practices

### Order Management
```zig
// Place limit order
try book.placeOrder(.{
    .price = 1000,
    .amount = 10,
    .id = next_order_id(),
    .side = .Buy,
    .order_type = .Limit,
    .flags = .{ .post_only = true },
});

// Cancel order
try book.cancelOrder(order_id);
```

### Batch Operations
```zig
// Bulk order placement
var orders: [MAX_ORDERS_PER_BATCH]Order = undefined;
for (orders) |*order, i| {
    order.* = Order.init(
        price + @intCast(u64, i),
        1,
        next_order_id(),
        .Buy
    );
}
try book.bulkInsertOrders(&orders);
```

### Error Handling
```zig
// Handle common errors
book.placeOrder(order) catch |err| switch (err) {
    error.InvalidPrice => log.err("Invalid price"),
    error.InvalidSize => log.err("Invalid size"),
    error.InsufficientFunds => log.err("Insufficient funds"),
    else => log.err("Unexpected error: {}", .{err}),
};
```

### Performance Monitoring
```zig
// Track performance
var monitor = try PerformanceMonitor.init(allocator);
defer monitor.deinit();

const start = std.time.nanoTimestamp();
try book.placeOrder(order);
const end = std.time.nanoTimestamp();

try monitor.recordMetric("order_latency", @intToFloat(f64, end - start));
