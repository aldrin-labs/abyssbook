#pragma once

#include "common.hpp"
#include "order_types.hpp"
#include "price_level.hpp"
#include "memory_pool.hpp"
#include "simd_helpers.hpp"
#include <unordered_map>
#include <vector>
#include <memory>
#include <atomic>
#include <shared_mutex>
#include <thread>

namespace abyssbook {

// Forward declarations
class OrderMatcher;
class AdvancedOrderManager;

// Sharded orderbook for high-performance order management
class ShardedOrderbook {
public:
    explicit ShardedOrderbook(std::size_t shard_count = 32);
    ~ShardedOrderbook();
    
    // Non-copyable but movable
    ShardedOrderbook(const ShardedOrderbook&) = delete;
    ShardedOrderbook& operator=(const ShardedOrderbook&) = delete;
    ShardedOrderbook(ShardedOrderbook&&) noexcept;
    ShardedOrderbook& operator=(ShardedOrderbook&&) noexcept;
    
    // Basic order operations
    OrderError placeOrder(OrderSide side, Price price, Amount amount, OrderId id);
    OrderError placeOrder(const CacheAlignedOrder& order);
    OrderError cancelOrder(OrderId id);
    OrderError modifyOrder(OrderId id, const OrderModification& modification);
    
    // Advanced order types
    OrderError placeStopOrder(OrderSide side, Price price, Amount amount, OrderId id, Price stop_price);
    OrderError placeStopLimitOrder(OrderSide side, Price price, Amount amount, OrderId id, Price stop_price);
    OrderError placeIOCOrder(OrderSide side, Price price, Amount amount, OrderId id);
    OrderError placeFOKOrder(OrderSide side, Price price, Amount amount, OrderId id);
    OrderError placePostOnlyOrder(OrderSide side, Price price, Amount amount, OrderId id);
    OrderError placeGTDOrder(OrderSide side, Price price, Amount amount, OrderId id, Timestamp expiry_time);
    OrderError placeIcebergOrder(OrderSide side, Price price, Amount total_amount, Amount display_amount, OrderId id);
    OrderError placeTWAPOrder(OrderSide side, Price price, Amount total_amount, OrderId id, 
                             std::uint64_t num_intervals, std::uint64_t interval_seconds);
    OrderError placeTrailingStopOrder(OrderSide side, Price price, Amount amount, OrderId id, Amount distance);
    OrderError placePegOrder(OrderSide side, Amount amount, PegType peg_type, std::int64_t offset, 
                           std::optional<Price> limit_price, OrderId id);
    OrderError placeDiscretionaryOrder(OrderSide side, Price base_price, Amount amount, OrderId id, Price discretionary_price);
    OrderError placeConditionalOrder(OrderSide side, Price price, Amount amount, OrderId id, 
                                   ConditionalType condition_type, Price threshold);
    
    // OCO and OSO orders
    OrderError placeOCOOrder(const CacheAlignedOrder& order1, const CacheAlignedOrder& order2);
    OrderError placeOSOOrder(const CacheAlignedOrder& primary_order, const CacheAlignedOrder& child_order);
    
    // Order execution
    MatchResult executeOrder(OrderSide side, Price price, Amount amount, OrderId id);
    MatchResult executeMarketOrder(OrderSide side, Amount amount);
    
    // Bulk operations for high-frequency trading
    std::vector<OrderError> placeBulkOrders(const std::vector<CacheAlignedOrder>& orders);
    std::vector<OrderError> cancelBulkOrders(const std::vector<OrderId>& order_ids);
    
    // Market data queries
    std::optional<Price> getBestBid() const;
    std::optional<Price> getBestAsk() const;
    std::optional<Price> getSpread() const;
    std::optional<Price> getMidpoint() const;
    Amount getVolumeAtLevel(Price price, OrderSide side) const;
    std::size_t getOrderCountAtLevel(Price price, OrderSide side) const;
    MarketDepth getMarketDepth(std::size_t max_levels_per_side = 20) const;
    
    // Order queries
    std::optional<CacheAlignedOrder> getOrder(OrderId id) const;
    std::vector<CacheAlignedOrder> getOrdersAtPrice(Price price, OrderSide side) const;
    std::vector<CacheAlignedOrder> getAllOrders() const;
    
    // Statistics and monitoring
    struct OrderbookStats {
        std::size_t total_orders;
        std::size_t total_bid_orders;
        std::size_t total_ask_orders;
        Amount total_bid_volume;
        Amount total_ask_volume;
        std::size_t total_price_levels;
        std::size_t bid_levels;
        std::size_t ask_levels;
        std::optional<Price> best_bid;
        std::optional<Price> best_ask;
        std::optional<Price> spread;
        std::optional<Price> midpoint;
        double memory_utilization;
        std::size_t orders_per_shard;
    };
    
    OrderbookStats getStats() const;
    
    // Performance monitoring
    struct PerformanceMetrics {
        std::atomic<std::uint64_t> orders_placed;
        std::atomic<std::uint64_t> orders_cancelled;
        std::atomic<std::uint64_t> orders_matched;
        std::atomic<std::uint64_t> total_latency_ns;
        std::atomic<std::uint64_t> min_latency_ns;
        std::atomic<std::uint64_t> max_latency_ns;
        
        double getAverageLatency() const {
            auto total_ops = orders_placed.load() + orders_cancelled.load();
            return total_ops > 0 ? static_cast<double>(total_latency_ns.load()) / total_ops : 0.0;
        }
        
        void reset() {
            orders_placed.store(0);
            orders_cancelled.store(0);
            orders_matched.store(0);
            total_latency_ns.store(0);
            min_latency_ns.store(UINT64_MAX);
            max_latency_ns.store(0);
        }
    };
    
    PerformanceMetrics& getMetrics() { return metrics_; }
    const PerformanceMetrics& getMetrics() const { return metrics_; }
    
    // Persistence and recovery
    OrderError saveToFile(const std::string& filename) const;
    OrderError loadFromFile(const std::string& filename);
    
    // Snapshot operations
    struct OrderbookSnapshot {
        std::vector<OrderSnapshot> orders;
        std::vector<OrderSnapshot> stop_orders;
        Timestamp timestamp;
        
        OrderbookSnapshot() : timestamp(getCurrentTimestamp()) {}
    };
    
    OrderbookSnapshot takeSnapshot() const;
    OrderError restoreFromSnapshot(const OrderbookSnapshot& snapshot);
    
    // Advanced features
    void enableExpiredOrderCleanup(bool enable);
    void setTWAPProcessor(std::function<void(const CacheAlignedOrder&)> processor);
    void setStopOrderTrigger(std::function<void(const CacheAlignedOrder&, Price)> trigger);
    
    // Thread safety
    void enableThreadSafety(bool enable);
    
    // Memory management
    void reserveCapacity(std::size_t expected_orders);
    void cleanup();  // Remove empty price levels and expired orders

private:
    // Internal structures
    struct Shard {
        std::unordered_map<OrderKey, CacheAlignedOrder, OrderKeyHash> orders;
        std::unordered_map<OrderKey, CacheAlignedOrder, OrderKeyHash> stop_orders;
        PriceLevelMap bid_levels;
        PriceLevelMap ask_levels;
        mutable std::shared_mutex mutex;
        
        Shard() = default;
        Shard(Shard&&) = default;
        Shard& operator=(Shard&&) = default;
    };
    
    // Core data
    std::vector<std::unique_ptr<Shard>> shards_;
    const std::size_t shard_count_;
    
    // Memory management
    std::unique_ptr<MemoryPool> order_pool_;
    std::unique_ptr<MemoryPool> params_pool_;
    
    // Advanced order management
    std::unique_ptr<OrderMatcher> matcher_;
    std::unique_ptr<AdvancedOrderManager> advanced_manager_;
    
    // Caching for performance
    mutable std::atomic<Price> cached_best_bid_;
    mutable std::atomic<Price> cached_best_ask_;
    mutable std::atomic<bool> cache_valid_;
    
    // Configuration
    std::atomic<bool> thread_safety_enabled_;
    std::atomic<bool> expired_order_cleanup_enabled_;
    
    // Performance metrics
    mutable PerformanceMetrics metrics_;
    
    // Background tasks
    std::unique_ptr<std::thread> cleanup_thread_;
    std::atomic<bool> cleanup_running_;
    
    // Helper methods
    ShardIndex getShardIndex(Price price) const;
    ShardIndex getShardIndex(OrderId id) const;
    Shard& getShard(ShardIndex index);
    const Shard& getShard(ShardIndex index) const;
    
    // Internal order operations
    OrderError placeOrderInternal(const CacheAlignedOrder& order);
    OrderError cancelOrderInternal(OrderId id, ShardIndex shard_hint = SIZE_MAX);
    MatchResult matchOrderInternal(const CacheAlignedOrder& order);
    
    // Cache management
    void invalidateCache() const;
    void updateBestPriceCache(Price price, OrderSide side) const;
    
    // Advanced order processing
    void processExpiredOrders();
    void processTWAPOrders();
    void processConditionalOrders();
    void processTrailingStops();
    
    // Cleanup operations
    void cleanupEmptyLevels();
    void cleanupExpiredOrders();
    void backgroundCleanupTask();
    
    // Latency measurement
    class LatencyMeasurer {
    public:
        LatencyMeasurer(PerformanceMetrics& metrics);
        ~LatencyMeasurer();
    private:
        PerformanceMetrics& metrics_;
        Timestamp start_time_;
    };
    
    // Lock management for thread safety
    template<typename Func>
    auto withShardLock(ShardIndex index, Func&& func) const -> decltype(func());
    
    template<typename Func>
    auto withShardLock(ShardIndex index, Func&& func) -> decltype(func());
};

// Orderbook builder for configuration
class OrderbookBuilder {
public:
    OrderbookBuilder();
    
    OrderbookBuilder& withShardCount(std::size_t count);
    OrderbookBuilder& withMemoryPoolSize(std::size_t size);
    OrderbookBuilder& withThreadSafety(bool enable);
    OrderbookBuilder& withExpiredOrderCleanup(bool enable);
    OrderbookBuilder& withCapacityReservation(std::size_t expected_orders);
    
    std::unique_ptr<ShardedOrderbook> build();

private:
    std::size_t shard_count_;
    std::size_t memory_pool_size_;
    bool thread_safety_;
    bool expired_order_cleanup_;
    std::size_t capacity_reservation_;
};

} // namespace abyssbook