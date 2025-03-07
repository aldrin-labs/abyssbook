# AbyssBook End-to-End Tests

This document describes the end-to-end (e2e) tests for the AbyssBook DEX infrastructure. These tests verify that the entire system works correctly by simulating real-world trading scenarios.

## Running the Tests

To run the e2e tests, use the following command:

```bash
zig build test-e2e
```

To run both unit tests and e2e tests together:

```bash
zig build test-all
```

## Test Coverage

The e2e tests cover the following scenarios:

### 1. Complete Trading Scenario
Tests a full trading workflow with multiple order types:
- Limit order placement and matching
- Market order execution
- TWAP (Time-Weighted Average Price) orders
- Iceberg orders
- Stop orders
- Trailing stop orders
- Peg orders
- Conditional orders
- Order cancellation

### 2. High Frequency Trading
Tests high-frequency trading patterns:
- Tight spreads
- Rapid order placement and cancellation
- Small market orders
- Burst order placement at same price level

### 3. Market Stress
Tests the system under high load:
- Wide range of price levels
- Large market orders
- Mass cancellations
- Volume verification

### 4. Advanced Order Types
Tests all advanced order types together:
- Discretionary orders
- Iceberg orders
- TWAP orders
- Trailing stop orders
- Peg orders
- Conditional orders

### 5. Edge Cases
Tests boundary conditions and error handling:
- Zero amount orders
- Duplicate order IDs
- Cancelling non-existent orders
- Market orders with no liquidity
- Extremely large orders
- Extremely small orders
- Maximum price values

### 6. Fee Calculation
Tests fee calculation logic:
- Maker fees
- Taker fees
- Fee differentials

### 7. Market Data Snapshots
Tests orderbook snapshot functionality:
- Snapshot creation
- Data integrity
- Snapshot immutability

### 8. Cross-Shard Operations
Tests operations across multiple shards:
- Order placement across shards
- Market orders crossing shards
- Volume verification across shards

### 9. Performance Characteristics
Tests performance metrics:
- Order placement latency
- Market order execution latency
- Order cancellation latency
- Performance assertions

## Adding New Tests

When adding new e2e tests:

1. Add the test to `src/e2e_tests.zig`
2. Follow the existing pattern for test structure
3. Ensure proper cleanup with `defer book.deinit()`
4. Update this documentation to reflect the new test

## Test Design Principles

The e2e tests are designed to:

1. Test the system as a whole rather than individual components
2. Simulate real-world usage patterns
3. Cover all order types and edge cases
4. Verify both functional correctness and performance characteristics
5. Ensure the system behaves correctly under various conditions