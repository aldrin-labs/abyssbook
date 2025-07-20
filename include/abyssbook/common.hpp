#pragma once

#include <cstdint>
#include <cstddef>
#include <memory>
#include <chrono>
#include <atomic>
#include <array>
#include <vector>

namespace abyssbook {

// Type definitions for performance and consistency
using OrderId = std::uint64_t;
using Price = std::uint64_t;
using Amount = std::uint64_t;
using Timestamp = std::int64_t;
using ShardIndex = std::size_t;

// SIMD vector width - adjust based on target architecture
constexpr std::size_t VECTOR_WIDTH = 4;  // AVX2 supports 4x 64-bit values
constexpr std::size_t CACHE_LINE_SIZE = 64;
constexpr std::size_t BATCH_SIZE = VECTOR_WIDTH * 4;
constexpr std::size_t PREFETCH_DISTANCE = 8;

// Cache alignment macro
#define CACHE_ALIGNED alignas(CACHE_LINE_SIZE)

// Branch prediction hints for optimization
#ifdef __GNUC__
#define LIKELY(x)       __builtin_expect(!!(x), 1)
#define UNLIKELY(x)     __builtin_expect(!!(x), 0)
#define PREFETCH_READ(addr)   __builtin_prefetch((addr), 0, 3)
#define PREFETCH_WRITE(addr)  __builtin_prefetch((addr), 1, 3)
#define FORCE_INLINE    __attribute__((always_inline)) inline
#define NEVER_INLINE    __attribute__((noinline))
#define HOT             __attribute__((hot))
#define COLD            __attribute__((cold))
#define PURE            __attribute__((pure))
#define CONST           __attribute__((const))
#else
#define LIKELY(x)       (x)
#define UNLIKELY(x)     (x)
#define PREFETCH_READ(addr)   
#define PREFETCH_WRITE(addr)  
#define FORCE_INLINE    inline
#define NEVER_INLINE    
#define HOT             
#define COLD            
#define PURE            
#define CONST           
#endif

// Memory alignment macros for different architectures
#ifdef __AVX512F__
constexpr std::size_t SIMD_ALIGNMENT = 64; // 512-bit alignment
constexpr std::size_t SIMD_WIDTH = 8;      // 8x 64-bit values
#elif defined(__AVX2__)
constexpr std::size_t SIMD_ALIGNMENT = 32; // 256-bit alignment
constexpr std::size_t SIMD_WIDTH = 4;      // 4x 64-bit values
#else
constexpr std::size_t SIMD_ALIGNMENT = 16; // 128-bit alignment
constexpr std::size_t SIMD_WIDTH = 2;      // 2x 64-bit values
#endif

#define SIMD_ALIGNED alignas(SIMD_ALIGNMENT)

// Order side enumeration with explicit underlying type
enum class OrderSide : std::uint8_t {
    Buy = 0,
    Sell = 1
};

// Order type enumeration with explicit underlying type
enum class OrderType : std::uint8_t {
    Limit = 0,
    Market = 1,
    Stop = 2,
    StopLimit = 3,
    IOC = 4,        // Immediate or Cancel
    FOK = 5,        // Fill or Kill
    PostOnly = 6,   // Post only
    GTD = 7,        // Good Till Date
    Iceberg = 8,    // Iceberg order
    OCO = 9,        // One-Cancels-Other
    TWAP = 10,      // Time-Weighted Average Price
    OSO = 11,       // One-Sends-Other
    TrailingStop = 12,  // Trailing Stop
    Peg = 13,       // Pegged to best bid/ask
    MidpointPeg = 14,   // Pegged to spread midpoint
    Discretionary = 15, // Limit order with discretionary price
    Conditional = 16    // Executes based on custom conditions
};

// Verify OrderType fits in uint8_t (max value 16 requires 5 bits, fits in uint8_t)
static_assert(static_cast<std::uint8_t>(OrderType::Conditional) <= 255, "OrderType exceeds uint8_t range");

// Peg type for pegged orders with explicit underlying type
enum class PegType : std::uint8_t {
    BestBid = 0,
    BestAsk = 1,
    Midpoint = 2,
    LastTrade = 3
};

// Conditional order types with explicit underlying type
enum class ConditionalType : std::uint8_t {
    Price = 0,
    Time = 1,
    Volume = 2,
    Custom = 3
};

// Order flags packed into a single byte for efficiency
struct OrderFlags {
    bool is_stop : 1;
    bool is_ioc : 1;
    bool is_fok : 1;
    bool is_post_only : 1;
    bool is_gtd : 1;
    bool is_iceberg : 1;
    bool is_oco : 1;
    bool is_twap : 1;
    bool is_oso : 1;
    bool is_trailing_stop : 1;
    bool is_peg : 1;
    bool is_midpoint_peg : 1;
    bool is_discretionary : 1;
    bool is_conditional : 1;
    std::uint8_t padding : 2;
    
    OrderFlags() : is_stop(false), is_ioc(false), is_fok(false), is_post_only(false),
                   is_gtd(false), is_iceberg(false), is_oco(false), is_twap(false),
                   is_oso(false), is_trailing_stop(false), is_peg(false),
                   is_midpoint_peg(false), is_discretionary(false), 
                   is_conditional(false), padding(0) {}
};

// Verify OrderFlags bit-field layout - ensure consistent packing across compilers
static_assert(sizeof(OrderFlags) == 2, "OrderFlags must be exactly 2 bytes for optimal packing");
static_assert(alignof(OrderFlags) <= 2, "OrderFlags alignment must not exceed 2 bytes");

// High resolution timestamp with caching for performance
namespace {
    thread_local Timestamp cached_timestamp = 0;
    thread_local std::uint64_t timestamp_generation = 0;
    std::atomic<std::uint64_t> global_timestamp_generation{0};
}

// Optimized timestamp function with caching
inline Timestamp getCurrentTimestamp() {
    // Check if we need to refresh the cached timestamp
    const auto current_gen = global_timestamp_generation.load(std::memory_order_relaxed);
    if (UNLIKELY(timestamp_generation != current_gen)) {
        cached_timestamp = std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::high_resolution_clock::now().time_since_epoch()
        ).count();
        timestamp_generation = current_gen;
    }
    return cached_timestamp;
}

// Force refresh of timestamp cache (call periodically in event loop)
inline void refreshTimestampCache() {
    global_timestamp_generation.fetch_add(1, std::memory_order_relaxed);
}

// Error types
enum class OrderError {
    Success = 0,
    OutOfMemory,
    InvalidPrice,
    InvalidAmount,
    OrderNotFound,
    DuplicateOrder,
    NoBestBid,
    NoBestAsk,
    LastTradeNotImplemented,
    InvalidOrderType,
    InsufficientLiquidity,
    MarketClosed,
    InvalidParameters,
    ThreadingError
};

// Match result structure
struct MatchResult {
    Amount filled_amount;
    Amount remaining_amount;
    Price execution_price;
    OrderError error;
    
    MatchResult() : filled_amount(0), remaining_amount(0), 
                   execution_price(0), error(OrderError::Success) {}
    
    MatchResult(Amount filled, Amount remaining, Price price, OrderError err = OrderError::Success)
        : filled_amount(filled), remaining_amount(remaining), 
          execution_price(price), error(err) {}
};

// Order modification structure
struct OrderModification {
    std::optional<Price> new_price;
    std::optional<Amount> new_amount;
    
    OrderModification() = default;
    
    static OrderModification withPrice(Price price) {
        OrderModification mod;
        mod.new_price = price;
        return mod;
    }
    
    static OrderModification withAmount(Amount amount) {
        OrderModification mod;
        mod.new_amount = amount;
        return mod;
    }
    
    OrderModification(Price price, Amount amount) 
        : new_price(price), new_amount(amount) {}
};

// Price level statistics
struct PriceLevelStats {
    Amount total_volume;
    std::size_t order_count;
    Amount min_amount;
    Amount max_amount;
    Amount avg_amount;
    
    PriceLevelStats() : total_volume(0), order_count(0), min_amount(0), 
                       max_amount(0), avg_amount(0) {}
};

// Market depth entry
struct DepthEntry {
    Price price;
    Amount volume;
    
    DepthEntry() : price(0), volume(0) {}
    DepthEntry(Price p, Amount v) : price(p), volume(v) {}
};

// Market depth structure
struct MarketDepth {
    std::vector<DepthEntry> bids;
    std::vector<DepthEntry> asks;
    
    void clear() {
        bids.clear();
        asks.clear();
    }
};

// Utility functions
inline bool isBuyOrder(OrderSide side) {
    return side == OrderSide::Buy;
}

inline bool isSellOrder(OrderSide side) {
    return side == OrderSide::Sell;
}

inline OrderSide oppositeSide(OrderSide side) {
    return isBuyOrder(side) ? OrderSide::Sell : OrderSide::Buy;
}

// Hash function for OrderId
struct OrderIdHash {
    std::size_t operator()(OrderId id) const noexcept {
        return std::hash<std::uint64_t>{}(id);
    }
};

} // namespace abyssbook