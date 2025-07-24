#include "abyssbook/price_level.hpp"
#include <algorithm>
#include <mutex>
#include <shared_mutex>

namespace abyssbook {

// PriceLevelMap implementation

PriceLevelMap::PriceLevelMap() : cache_valid_(false), cached_best_price_(0) {}

void PriceLevelMap::updateLevel(Price price, std::int64_t volume_delta, std::int64_t count_delta) {
    std::unique_lock<std::shared_mutex> lock(mutex_);
    
    auto it = levels_.find(price);
    if (it == levels_.end()) {
        if (volume_delta > 0 && count_delta > 0) {
            levels_[price] = PriceLevel(static_cast<Amount>(volume_delta), static_cast<std::size_t>(count_delta));
        }
    } else {
        auto& level = it->second;
        
        // Update volume with bounds checking
        if (volume_delta < 0) {
            Amount abs_delta = static_cast<Amount>(-volume_delta);
            level.total_volume = (abs_delta > level.total_volume) ? 0 : level.total_volume - abs_delta;
        } else {
            level.total_volume += static_cast<Amount>(volume_delta);
        }
        
        // Update count with bounds checking
        if (count_delta < 0) {
            std::size_t abs_delta = static_cast<std::size_t>(-count_delta);
            level.order_count = (abs_delta > level.order_count) ? 0 : level.order_count - abs_delta;
        } else {
            level.order_count += static_cast<std::size_t>(count_delta);
        }
        
        // Remove empty levels
        if (level.isEmpty()) {
            levels_.erase(it);
        }
    }
    
    // Invalidate cache
    cache_valid_.store(false, std::memory_order_release);
}

void PriceLevelMap::updateLevels(const std::vector<PriceLevelUpdate>& updates) {
    std::unique_lock<std::shared_mutex> lock(mutex_);
    
    for (const auto& update : updates) {
        auto it = levels_.find(update.price);
        if (it == levels_.end()) {
            if (update.volume_delta > 0 && update.count_delta > 0) {
                levels_[update.price] = PriceLevel(
                    static_cast<Amount>(update.volume_delta), 
                    static_cast<std::size_t>(update.count_delta)
                );
            }
        } else {
            auto& level = it->second;
            
            // Update volume
            if (update.volume_delta < 0) {
                Amount abs_delta = static_cast<Amount>(-update.volume_delta);
                level.total_volume = (abs_delta > level.total_volume) ? 0 : level.total_volume - abs_delta;
            } else {
                level.total_volume += static_cast<Amount>(update.volume_delta);
            }
            
            // Update count
            if (update.count_delta < 0) {
                std::size_t abs_delta = static_cast<std::size_t>(-update.count_delta);
                level.order_count = (abs_delta > level.order_count) ? 0 : level.order_count - abs_delta;
            } else {
                level.order_count += static_cast<std::size_t>(update.count_delta);
            }
            
            // Remove empty levels
            if (level.isEmpty()) {
                levels_.erase(it);
            }
        }
    }
    
    // Invalidate cache
    cache_valid_.store(false, std::memory_order_release);
}

std::optional<PriceLevel> PriceLevelMap::getLevel(Price price) const {
    std::shared_lock<std::shared_mutex> lock(mutex_);
    
    auto it = levels_.find(price);
    if (it != levels_.end()) {
        return it->second;
    }
    return std::nullopt;
}

std::optional<Price> PriceLevelMap::getBestPrice(bool is_bid) const {
    std::shared_lock<std::shared_mutex> lock(mutex_);
    
    if (levels_.empty()) {
        return std::nullopt;
    }
    
    if (is_bid) {
        // For bids, we want the highest price
        auto it = levels_.rbegin();
        while (it != levels_.rend() && it->second.isEmpty()) {
            ++it;
        }
        return (it != levels_.rend()) ? std::optional<Price>(it->first) : std::nullopt;
    } else {
        // For asks, we want the lowest price
        auto it = levels_.begin();
        while (it != levels_.end() && it->second.isEmpty()) {
            ++it;
        }
        return (it != levels_.end()) ? std::optional<Price>(it->first) : std::nullopt;
    }
}

std::optional<Price> PriceLevelMap::getNextPrice(Price current_price, bool is_bid) const {
    std::shared_lock<std::shared_mutex> lock(mutex_);
    
    if (is_bid) {
        // For bids, find the next lower price
        auto it = levels_.lower_bound(current_price);
        if (it != levels_.begin()) {
            --it;
            while (it->second.isEmpty() && it != levels_.begin()) {
                --it;
            }
            if (!it->second.isEmpty()) {
                return it->first;
            }
        }
    } else {
        // For asks, find the next higher price
        auto it = levels_.upper_bound(current_price);
        while (it != levels_.end() && it->second.isEmpty()) {
            ++it;
        }
        if (it != levels_.end()) {
            return it->first;
        }
    }
    
    return std::nullopt;
}

std::vector<Price> PriceLevelMap::getSortedPrices(bool is_bid, std::size_t max_levels) const {
    std::shared_lock<std::shared_mutex> lock(mutex_);
    
    std::vector<Price> prices;
    prices.reserve(std::min(levels_.size(), max_levels > 0 ? max_levels : levels_.size()));
    
    if (is_bid) {
        // For bids, iterate in descending order
        for (auto it = levels_.rbegin(); it != levels_.rend() && (max_levels == 0 || prices.size() < max_levels); ++it) {
            if (!it->second.isEmpty()) {
                prices.push_back(it->first);
            }
        }
    } else {
        // For asks, iterate in ascending order
        for (auto it = levels_.begin(); it != levels_.end() && (max_levels == 0 || prices.size() < max_levels); ++it) {
            if (!it->second.isEmpty()) {
                prices.push_back(it->first);
            }
        }
    }
    
    return prices;
}

std::vector<DepthEntry> PriceLevelMap::getDepth(bool is_bid, std::size_t max_levels) const {
    std::shared_lock<std::shared_mutex> lock(mutex_);
    
    std::vector<DepthEntry> depth;
    depth.reserve(std::min(levels_.size(), max_levels));
    
    if (is_bid) {
        // For bids, iterate in descending order
        for (auto it = levels_.rbegin(); it != levels_.rend() && depth.size() < max_levels; ++it) {
            if (!it->second.isEmpty()) {
                depth.emplace_back(it->first, it->second.total_volume);
            }
        }
    } else {
        // For asks, iterate in ascending order
        for (auto it = levels_.begin(); it != levels_.end() && depth.size() < max_levels; ++it) {
            if (!it->second.isEmpty()) {
                depth.emplace_back(it->first, it->second.total_volume);
            }
        }
    }
    
    return depth;
}

Amount PriceLevelMap::getTotalVolume() const {
    std::shared_lock<std::shared_mutex> lock(mutex_);
    
    Amount total = 0;
    for (const auto& [price, level] : levels_) {
        total += level.total_volume;
    }
    return total;
}

std::size_t PriceLevelMap::getTotalOrderCount() const {
    std::shared_lock<std::shared_mutex> lock(mutex_);
    
    std::size_t total = 0;
    for (const auto& [price, level] : levels_) {
        total += level.order_count;
    }
    return total;
}

std::size_t PriceLevelMap::getLevelCount() const {
    std::shared_lock<std::shared_mutex> lock(mutex_);
    
    std::size_t count = 0;
    for (const auto& [price, level] : levels_) {
        if (!level.isEmpty()) {
            count++;
        }
    }
    return count;
}

void PriceLevelMap::clear() {
    std::unique_lock<std::shared_mutex> lock(mutex_);
    levels_.clear();
    cache_valid_.store(false, std::memory_order_release);
}

void PriceLevelMap::cleanup() {
    std::unique_lock<std::shared_mutex> lock(mutex_);
    
    auto it = levels_.begin();
    while (it != levels_.end()) {
        if (it->second.isEmpty()) {
            it = levels_.erase(it);
        } else {
            ++it;
        }
    }
    
    cache_valid_.store(false, std::memory_order_release);
}

PriceLevelMap::Stats PriceLevelMap::getStats(bool is_bid) const {
    std::shared_lock<std::shared_mutex> lock(mutex_);
    
    Stats stats{};
    Amount total_volume = 0;
    std::size_t total_orders = 0;
    std::size_t non_empty_levels = 0;
    
    std::optional<Price> best_price;
    std::optional<Price> worst_price;
    
    for (const auto& [price, level] : levels_) {
        if (!level.isEmpty()) {
            non_empty_levels++;
            total_volume += level.total_volume;
            total_orders += level.order_count;
            
            if (!best_price) {
                best_price = price;
                worst_price = price;
            } else {
                if (is_bid) {
                    best_price = std::max(*best_price, price);
                    worst_price = std::min(*worst_price, price);
                } else {
                    best_price = std::min(*best_price, price);
                    worst_price = std::max(*worst_price, price);
                }
            }
        }
    }
    
    stats.level_count = non_empty_levels;
    stats.total_volume = total_volume;
    stats.total_orders = total_orders;
    stats.best_price = best_price;
    stats.worst_price = worst_price;
    stats.avg_volume_per_level = non_empty_levels > 0 ? total_volume / non_empty_levels : 0;
    stats.avg_orders_per_level = non_empty_levels > 0 ? static_cast<double>(total_orders) / non_empty_levels : 0.0;
    
    return stats;
}

// PriceLevelAggregator implementation

PriceLevelAggregator::PriceLevelAggregator(std::size_t max_levels) : max_levels_(max_levels) {}

void PriceLevelAggregator::addOrder(Price price, Amount amount, OrderSide side) {
    if (side == OrderSide::Buy) {
        bid_levels_.updateLevel(price, static_cast<std::int64_t>(amount), 1);
    } else {
        ask_levels_.updateLevel(price, static_cast<std::int64_t>(amount), 1);
    }
}

void PriceLevelAggregator::removeOrder(Price price, Amount amount, OrderSide side) {
    if (side == OrderSide::Buy) {
        bid_levels_.updateLevel(price, -static_cast<std::int64_t>(amount), -1);
    } else {
        ask_levels_.updateLevel(price, -static_cast<std::int64_t>(amount), -1);
    }
}

MarketDepth PriceLevelAggregator::getMarketDepth(std::size_t max_levels_per_side) const {
    MarketDepth depth;
    depth.bids = bid_levels_.getDepth(true, max_levels_per_side);
    depth.asks = ask_levels_.getDepth(false, max_levels_per_side);
    return depth;
}

std::optional<Price> PriceLevelAggregator::getBestBid() const {
    return bid_levels_.getBestPrice(true);
}

std::optional<Price> PriceLevelAggregator::getBestAsk() const {
    return ask_levels_.getBestPrice(false);
}

std::optional<Price> PriceLevelAggregator::getSpread() const {
    auto best_bid = getBestBid();
    auto best_ask = getBestAsk();
    
    if (best_bid && best_ask) {
        return *best_ask - *best_bid;
    }
    
    return std::nullopt;
}

std::optional<Price> PriceLevelAggregator::getMidpoint() const {
    auto best_bid = getBestBid();
    auto best_ask = getBestAsk();
    
    if (best_bid && best_ask) {
        return (*best_bid + *best_ask) / 2;
    }
    
    return std::nullopt;
}

void PriceLevelAggregator::reset() {
    bid_levels_.clear();
    ask_levels_.clear();
}

PriceLevelAggregator::AggregationStats PriceLevelAggregator::getStats() const {
    AggregationStats stats{};
    
    auto bid_stats = bid_levels_.getStats(true);
    auto ask_stats = ask_levels_.getStats(false);
    
    stats.total_bid_levels = bid_stats.level_count;
    stats.total_ask_levels = ask_stats.level_count;
    stats.total_bid_volume = bid_stats.total_volume;
    stats.total_ask_volume = ask_stats.total_volume;
    stats.best_bid = bid_stats.best_price;
    stats.best_ask = ask_stats.best_price;
    stats.spread = getSpread();
    stats.midpoint = getMidpoint();
    
    return stats;
}

// BatchPriceLevelUpdater implementation

BatchPriceLevelUpdater::BatchPriceLevelUpdater(PriceLevelMap& levels) 
    : levels_(levels), committed_(false) {
    updates_.reserve(64); // Reserve space for typical batch size
}

BatchPriceLevelUpdater::~BatchPriceLevelUpdater() {
    if (!committed_) {
        commit();
    }
}

void BatchPriceLevelUpdater::addUpdate(Price price, std::int64_t volume_delta, std::int64_t count_delta) {
    updates_.emplace_back(price, volume_delta, count_delta);
}

void BatchPriceLevelUpdater::commit() {
    if (!committed_) {
        levels_.updateLevels(updates_);
        committed_ = true;
    }
}

} // namespace abyssbook
