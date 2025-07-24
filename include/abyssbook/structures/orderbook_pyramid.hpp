#pragma once

#include "../common.hpp"
#include <array>
#include <vector>
#include <memory>
#include <atomic>
#include <unordered_map>

namespace abyssbook {
namespace novel {

//=============================================================================
// Order Book Pyramid - Specialized Hierarchical Structure
//=============================================================================

class OrderBookPyramid {
private:
    struct CACHE_ALIGNED PyramidLevel {
        std::atomic<double> price_level;
        std::atomic<std::uint64_t> volume;
        std::atomic<std::uint32_t> order_count;
        std::atomic<PyramidLevel*> next;
        std::atomic<PyramidLevel*> prev;
        
        PyramidLevel(double price, std::uint64_t vol = 0)
            : price_level(price), volume(vol), order_count(0), next(nullptr), prev(nullptr) {}
    };
    
    std::atomic<PyramidLevel*> bid_top;
    std::atomic<PyramidLevel*> ask_top;
    std::atomic<std::uint32_t> total_levels;
    
public:
    OrderBookPyramid() : bid_top(nullptr), ask_top(nullptr), total_levels(0) {}
    
    ~OrderBookPyramid() {
        clear();
    }
    
    HOT FORCE_INLINE void addOrder(double price, std::uint64_t volume, bool is_buy) {
        if (is_buy) {
            addBidOrder(price, volume);
        } else {
            addAskOrder(price, volume);
        }
    }
    
    HOT FORCE_INLINE void removeOrder(double price, std::uint64_t volume, bool is_buy) {
        if (is_buy) {
            removeBidOrder(price, volume);
        } else {
            removeAskOrder(price, volume);
        }
    }
    
    HOT FORCE_INLINE std::optional<double> getBestBid() const {
        PyramidLevel* top = bid_top.load(std::memory_order_acquire);
        return top ? std::optional<double>(top->price_level.load(std::memory_order_relaxed)) : std::nullopt;
    }
    
    HOT FORCE_INLINE std::optional<double> getBestAsk() const {
        PyramidLevel* top = ask_top.load(std::memory_order_acquire);
        return top ? std::optional<double>(top->price_level.load(std::memory_order_relaxed)) : std::nullopt;
    }
    
    FORCE_INLINE std::uint32_t getLevelCount() const {
        return total_levels.load(std::memory_order_relaxed);
    }
    
    struct MarketDepth {
        std::vector<std::pair<double, std::uint64_t>> bids;
        std::vector<std::pair<double, std::uint64_t>> asks;
    };
    
    FORCE_INLINE MarketDepth getMarketDepth(std::uint32_t levels = 10) const {
        MarketDepth depth;
        
        // Collect bid levels
        PyramidLevel* current = bid_top.load(std::memory_order_acquire);
        for (std::uint32_t i = 0; i < levels && current; ++i) {
            double price = current->price_level.load(std::memory_order_relaxed);
            std::uint64_t volume = current->volume.load(std::memory_order_relaxed);
            depth.bids.emplace_back(price, volume);
            current = current->next.load(std::memory_order_relaxed);
        }
        
        // Collect ask levels
        current = ask_top.load(std::memory_order_acquire);
        for (std::uint32_t i = 0; i < levels && current; ++i) {
            double price = current->price_level.load(std::memory_order_relaxed);
            std::uint64_t volume = current->volume.load(std::memory_order_relaxed);
            depth.asks.emplace_back(price, volume);
            current = current->next.load(std::memory_order_relaxed);
        }
        
        return depth;
    }
    
private:
    void addBidOrder(double price, std::uint64_t volume) {
        PyramidLevel* current = bid_top.load(std::memory_order_acquire);
        
        // Find or create price level
        while (current) {
            double current_price = current->price_level.load(std::memory_order_relaxed);
            if (current_price == price) {
                // Add to existing level
                current->volume.fetch_add(volume, std::memory_order_relaxed);
                current->order_count.fetch_add(1, std::memory_order_relaxed);
                return;
            } else if (current_price < price) {
                // Insert new level before current
                auto new_level = new PyramidLevel(price, volume);
                new_level->order_count.store(1, std::memory_order_relaxed);
                
                PyramidLevel* prev = current->prev.load(std::memory_order_relaxed);
                new_level->next.store(current, std::memory_order_relaxed);
                new_level->prev.store(prev, std::memory_order_relaxed);
                current->prev.store(new_level, std::memory_order_relaxed);
                
                if (prev) {
                    prev->next.store(new_level, std::memory_order_relaxed);
                } else {
                    bid_top.store(new_level, std::memory_order_release);
                }
                
                total_levels.fetch_add(1, std::memory_order_relaxed);
                return;
            }
            current = current->next.load(std::memory_order_relaxed);
        }
        
        // Add as new bottom level
        auto new_level = new PyramidLevel(price, volume);
        new_level->order_count.store(1, std::memory_order_relaxed);
        
        if (!bid_top.load(std::memory_order_relaxed)) {
            bid_top.store(new_level, std::memory_order_release);
        } else {
            // Link to end of list (simplified)
            // In production, would maintain proper ordering
        }
        
        total_levels.fetch_add(1, std::memory_order_relaxed);
    }
    
    void addAskOrder(double price, std::uint64_t volume) {
        // Similar implementation to addBidOrder but with reverse price ordering
        PyramidLevel* current = ask_top.load(std::memory_order_acquire);
        
        while (current) {
            double current_price = current->price_level.load(std::memory_order_relaxed);
            if (current_price == price) {
                current->volume.fetch_add(volume, std::memory_order_relaxed);
                current->order_count.fetch_add(1, std::memory_order_relaxed);
                return;
            } else if (current_price > price) {
                // Insert new level before current (asks sorted ascending)
                auto new_level = new PyramidLevel(price, volume);
                new_level->order_count.store(1, std::memory_order_relaxed);
                
                PyramidLevel* prev = current->prev.load(std::memory_order_relaxed);
                new_level->next.store(current, std::memory_order_relaxed);
                new_level->prev.store(prev, std::memory_order_relaxed);
                current->prev.store(new_level, std::memory_order_relaxed);
                
                if (prev) {
                    prev->next.store(new_level, std::memory_order_relaxed);
                } else {
                    ask_top.store(new_level, std::memory_order_release);
                }
                
                total_levels.fetch_add(1, std::memory_order_relaxed);
                return;
            }
            current = current->next.load(std::memory_order_relaxed);
        }
        
        // Add as new level
        auto new_level = new PyramidLevel(price, volume);
        new_level->order_count.store(1, std::memory_order_relaxed);
        
        if (!ask_top.load(std::memory_order_relaxed)) {
            ask_top.store(new_level, std::memory_order_release);
        }
        
        total_levels.fetch_add(1, std::memory_order_relaxed);
    }
    
    void removeBidOrder(double price, std::uint64_t volume) {
        PyramidLevel* current = bid_top.load(std::memory_order_acquire);
        
        while (current) {
            double current_price = current->price_level.load(std::memory_order_relaxed);
            if (current_price == price) {
                std::uint64_t current_volume = current->volume.fetch_sub(volume, std::memory_order_relaxed);
                current->order_count.fetch_sub(1, std::memory_order_relaxed);
                
                if (current_volume <= volume) {
                    // Remove level if empty
                    PyramidLevel* next = current->next.load(std::memory_order_relaxed);
                    PyramidLevel* prev = current->prev.load(std::memory_order_relaxed);
                    
                    if (prev) {
                        prev->next.store(next, std::memory_order_relaxed);
                    } else {
                        bid_top.store(next, std::memory_order_release);
                    }
                    
                    if (next) {
                        next->prev.store(prev, std::memory_order_relaxed);
                    }
                    
                    delete current;
                    total_levels.fetch_sub(1, std::memory_order_relaxed);
                }
                return;
            }
            current = current->next.load(std::memory_order_relaxed);
        }
    }
    
    void removeAskOrder(double price, std::uint64_t volume) {
        // Similar to removeBidOrder
        PyramidLevel* current = ask_top.load(std::memory_order_acquire);
        
        while (current) {
            double current_price = current->price_level.load(std::memory_order_relaxed);
            if (current_price == price) {
                std::uint64_t current_volume = current->volume.fetch_sub(volume, std::memory_order_relaxed);
                current->order_count.fetch_sub(1, std::memory_order_relaxed);
                
                if (current_volume <= volume) {
                    // Remove level if empty
                    PyramidLevel* next = current->next.load(std::memory_order_relaxed);
                    PyramidLevel* prev = current->prev.load(std::memory_order_relaxed);
                    
                    if (prev) {
                        prev->next.store(next, std::memory_order_relaxed);
                    } else {
                        ask_top.store(next, std::memory_order_release);
                    }
                    
                    if (next) {
                        next->prev.store(prev, std::memory_order_relaxed);
                    }
                    
                    delete current;
                    total_levels.fetch_sub(1, std::memory_order_relaxed);
                }
                return;
            }
            current = current->next.load(std::memory_order_relaxed);
        }
    }
    
    void clear() {
        // Clear bid levels
        PyramidLevel* current = bid_top.exchange(nullptr, std::memory_order_acq_rel);
        while (current) {
            PyramidLevel* next = current->next.load(std::memory_order_relaxed);
            delete current;
            current = next;
        }
        
        // Clear ask levels
        current = ask_top.exchange(nullptr, std::memory_order_acq_rel);
        while (current) {
            PyramidLevel* next = current->next.load(std::memory_order_relaxed);
            delete current;
            current = next;
        }
        
        total_levels.store(0, std::memory_order_relaxed);
    }
};

} // namespace novel
} // namespace abyssbook