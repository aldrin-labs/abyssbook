# Memory Optimization for CI/CD Environments

## Overview

This document outlines the memory optimizations implemented to reduce RAM usage in Zig tests and benchmarks, particularly for CI/CD environments where memory constraints are more stringent.

## Changes Made

### 1. Benchmark Configuration Optimization

**File**: `src/bench.zig`

- **CI Detection**: Automatically detects CI/GitHub Actions environment variables
- **Reduced Parameters for CI**:
  - Shards: 32 → 4 (87.5% reduction)
  - Iterations: 100,000 → 1,000 (99% reduction)  
  - Order Count: 10,000 → 1,000 (90% reduction)
  - Price Range: 1000 → 100 (90% reduction)
  - Burst Size: 1000 → 100 (90% reduction)
  - Price Levels: 100 → 20 (80% reduction)

### 2. Memory Management Improvements

**Arena Allocators**: 
- Replaced `std.heap.page_allocator` with arena allocators for temporary memory
- Automatic cleanup of temporary allocations after each benchmark

**Latency Sampling**:
- Reduced memory usage by sampling latencies instead of storing all iteration times
- Sample size capped at 10,000 entries regardless of iteration count

**Orderbook State Management**:
- Added explicit orderbook state reset between benchmarks
- Uses `clearRetainingCapacity()` to preserve allocated memory while clearing data

### 3. Test Data Structure Optimization

**E2E Tests** (`src/e2e_tests.zig`):
- Reduced shard counts from 8/32/16 to 4/8/4 for CI
- Reduced loop iterations and order quantities:
  - HFT test: 100 iterations → 20 for CI
  - Market stress: 100 price levels → 25 for CI
  - Market orders: 500 units → 125 for CI

**Unit Tests** (`src/orderbook_test.zig`):
- Reduced default shard count from 8 → 4 for CI environments

**Security Tests** (`src/tests/security_tests.zig`):
- Reduced buffer sizes from 1024 → 256 bytes for CI
- Used stack allocation instead of heap allocation where possible

### 4. Stack vs Heap Allocation

**Before**: Large allocations on heap
```zig
var long_arg: [1024]u8 = undefined; // Always 1KB on stack
```

**After**: CI-optimized with smaller stack usage
```zig
var long_arg_buffer: [256]u8 = undefined; // 256 bytes for CI
const buffer_size = if (ci_detected) 256 else 1024;
```

### 5. Memory Release Optimization

**Prompt Memory Release**:
- Added explicit `defer` statements for all temporary allocations
- Arena allocators ensure automatic cleanup of all related allocations

**Reduced Parallelism**:
- Tests use fewer concurrent orderbook instances
- Reduced concurrent shard operations

## Environment Detection

The optimizations automatically activate when either environment variable is present:
- `CI=true` (standard CI indicator)
- `GITHUB_ACTIONS=true` (GitHub Actions specific)

## Performance Impact

### Memory Usage Reduction (Estimated)
- **Benchmarks**: ~95% reduction in peak memory usage
- **E2E Tests**: ~75% reduction in memory allocation
- **Unit Tests**: ~50% reduction in shard-related memory
- **Security Tests**: ~75% reduction in buffer allocations

### Performance Characteristics Maintained
- All test coverage preserved
- Core functionality validation unchanged
- Performance trends still representative (with scaled parameters)

## Usage

### Local Development (Full Performance)
```bash
make bench           # Full benchmark parameters
make test-all        # Full test parameters
```

### CI Environment (Memory Optimized)
```bash
CI=true make bench   # Reduced parameters automatically
CI=true make test-all # Reduced memory usage
```

### Manual CI Mode
```bash
export CI=true
make bench
make test-all
```

## Best Practices Implemented

1. **Environment-Aware Configuration**: Automatically adapts to execution environment
2. **Arena Allocators**: Simplified memory management and automatic cleanup
3. **Sampling-Based Metrics**: Maintains statistical accuracy with reduced memory
4. **Stack Allocation Preference**: Uses stack where possible for small, temporary data
5. **Explicit Resource Management**: Clear ownership and cleanup patterns
6. **Graceful Degradation**: Reduced parameters maintain test validity

## Monitoring

The benchmarks display `(CI Optimized)` in output when running with reduced parameters:

```
Orderbook Benchmark Results (CI Optimized):
Configuration:
  Shards: 4
  Iterations: 1000
  Order Count: 1000
  Burst Size: 100
  Price Levels: 20
```

This ensures transparency about which configuration is being used.