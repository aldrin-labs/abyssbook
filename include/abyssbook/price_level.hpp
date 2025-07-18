#pragma once

#include "common.hpp"
#include "order_types.hpp"
#include <unordered_map>
#include <map>
#include <vector>
#include <atomic>
#include <shared_mutex>

namespace abyssbook {

// Price level containing aggregated order information at a specific price
struct PriceLevel {
    Amount total_volume;
    std::size_t order_count;
    
    PriceLevel() : total_volume(0), order_count(0) {}
    
    PriceLevel(Amount volume, std::size_t count) 
        : total_volume(volume), order_count(count) {}
    
    void addOrder(Amount amount) {
        total_volume += amount;
        ++order_count;
    }
    
    void removeOrder(Amount amount) {
        total_volume = (amount >= total_volume) ? 0 : total_volume - amount;
        order_count = (order_count > 0) ? order_count - 1 : 0;
    }
    
    void updateAmount(Amount old_amount, Amount new_amount) {
        total_volume = total_volume - old_amount + new_amount;
    }
    
    bool isEmpty() const {
        return order_count == 0 || total_volume == 0;
    }
};

// Price level update for batch operations
struct PriceLevelUpdate {
    Price price;
    std::int64_t volume_delta;  // Can be negative for reductions
    std::int64_t count_delta;   // Can be negative for removals
    
    PriceLevelUpdate() = default;
    
    PriceLevelUpdate(Price p, std::int64_t vol_delta, std::int64_t cnt_delta)
        : price(p), volume_delta(vol_delta), count_delta(cnt_delta) {}
};

// Thread-safe price level map with sorted access
class PriceLevelMap {
public:
    PriceLevelMap();
    ~PriceLevelMap() = default;
    
    // Non-copyable but movable
    PriceLevelMap(const PriceLevelMap&) = delete;
    PriceLevelMap& operator=(const PriceLevelMap&) = delete;
    PriceLevelMap(PriceLevelMap&&) noexcept = default;
    PriceLevelMap& operator=(PriceLevelMap&&) noexcept = default;
    
    // Add or update a price level
    void updateLevel(Price price, std::int64_t volume_delta, std::int64_t count_delta);
    
    // Batch update multiple price levels
    void updateLevels(const std::vector<PriceLevelUpdate>& updates);
    
    // Get price level information
    std::optional<PriceLevel> getLevel(Price price) const;
    
    // Get best price (highest for bids, lowest for asks)
    std::optional<Price> getBestPrice(bool is_bid) const;
    
    // Get next price level after current price
    std::optional<Price> getNextPrice(Price current_price, bool is_bid) const;
    
    // Get sorted prices (descending for bids, ascending for asks)
    std::vector<Price> getSortedPrices(bool is_bid, std::size_t max_levels = 0) const;
    
    // Get depth up to specified number of levels
    std::vector<DepthEntry> getDepth(bool is_bid, std::size_t max_levels) const;
    
    // Get total volume across all levels
    Amount getTotalVolume() const;
    
    // Get total number of orders across all levels
    std::size_t getTotalOrderCount() const;
    
    // Get number of price levels
    std::size_t getLevelCount() const;
    
    // Clear all price levels
    void clear();
    
    // Remove empty levels
    void cleanup();
    
    // Get statistics
    struct Stats {
        std::size_t level_count;
        Amount total_volume;
        std::size_t total_orders;
        std::optional<Price> best_price;
        std::optional<Price> worst_price;
        Amount avg_volume_per_level;
        double avg_orders_per_level;
    };
    
    Stats getStats(bool is_bid) const;

private:
    // Use map for automatic sorting
    mutable std::shared_mutex mutex_;
    std::map<Price, PriceLevel> levels_;
    mutable std::atomic<bool> cache_valid_;
    mutable std::atomic<Price> cached_best_price_;
};

// High-performance price level manager for hot paths
class FastPriceLevelMap {
public:
    static constexpr std::size_t MAX_CACHED_LEVELS = 64;
    
    FastPriceLevelMap();
    ~FastPriceLevelMap() = default;
    
    // Lock-free operations for hot paths
    void updateLevel(Price price, std::int64_t volume_delta, std::int64_t count_delta);
    std::optional<PriceLevel> getLevel(Price price) const;
    std::optional<Price> getBestPrice(bool is_bid) const;
    
    // Operations that may require locking
    std::vector<Price> getSortedPrices(bool is_bid, std::size_t max_levels = 0) const;
    void cleanup();
    void clear();

private:
    struct CachedLevel {
        std::atomic<Price> price;
        std::atomic<Amount> volume;
        std::atomic<std::size_t> count;
        std::atomic<bool> valid;
        
        CachedLevel() : price(0), volume(0), count(0), valid(false) {}
    };
    
    // Hot cache for frequently accessed levels
    CACHE_ALIGNED std::array<CachedLevel, MAX_CACHED_LEVELS> hot_cache_;
    std::atomic<std::size_t> cache_size_;
    
    // Fallback to slower but complete storage
    mutable std::shared_mutex mutex_;
    std::unordered_map<Price, PriceLevel> levels_;
    
    // Cache management
    std::size_t findCacheSlot(Price price) const;
    void addToCache(Price price, const PriceLevel& level);
    void invalidateCache();
};

// Price level aggregator for market data
class PriceLevelAggregator {
public:
    explicit PriceLevelAggregator(std::size_t max_levels = 100);
    
    // Add order to aggregation
    void addOrder(Price price, Amount amount, OrderSide side);
    
    // Remove order from aggregation
    void removeOrder(Price price, Amount amount, OrderSide side);
    
    // Get aggregated market depth
    MarketDepth getMarketDepth(std::size_t max_levels_per_side = 20) const;
    
    // Get best bid and ask
    std::optional<Price> getBestBid() const;
    std::optional<Price> getBestAsk() const;
    
    // Get spread
    std::optional<Price> getSpread() const;
    
    // Get midpoint price
    std::optional<Price> getMidpoint() const;
    
    // Reset aggregation
    void reset();
    
    // Get aggregation statistics
    struct AggregationStats {
        std::size_t total_bid_levels;
        std::size_t total_ask_levels;
        Amount total_bid_volume;
        Amount total_ask_volume;
        std::optional<Price> best_bid;
        std::optional<Price> best_ask;
        std::optional<Price> spread;
        std::optional<Price> midpoint;
    };
    
    AggregationStats getStats() const;

private:
    const std::size_t max_levels_;
    PriceLevelMap bid_levels_;
    PriceLevelMap ask_levels_;
};

// RAII helper for batch price level updates
class BatchPriceLevelUpdater {
public:
    explicit BatchPriceLevelUpdater(PriceLevelMap& levels);
    ~BatchPriceLevelUpdater();
    
    // Add update to batch
    void addUpdate(Price price, std::int64_t volume_delta, std::int64_t count_delta);
    
    // Manual commit (automatic on destruction)
    void commit();

private:
    PriceLevelMap& levels_;
    std::vector<PriceLevelUpdate> updates_;
    bool committed_;
};

} // namespace abyssbook