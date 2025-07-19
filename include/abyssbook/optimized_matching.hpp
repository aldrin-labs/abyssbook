#pragma once

#include "common.hpp"
#include "order_types.hpp"
#include "simd_helpers.hpp"
#include "template_optimizations.hpp"
#include "lockfree_structures.hpp"
#include <vector>
#include <array>
#include <memory>

namespace abyssbook {

// High-performance optimized matching engine
class OptimizedMatchingEngine {
private:
    // Lock-free price level storage
    lockfree::LockFreeHashMap<1024> bid_levels_;
    lockfree::LockFreeHashMap<1024> ask_levels_;
    
    // Cache-aligned best price tracking
    CACHE_ALIGNED std::atomic<Price> best_bid_;
    CACHE_ALIGNED std::atomic<Price> best_ask_;
    
    // Statistics counters
    CACHE_ALIGNED std::atomic<std::uint64_t> total_matches_;
    CACHE_ALIGNED std::atomic<std::uint64_t> total_volume_;
    
    // Batch processing buffers
    static constexpr std::size_t BATCH_SIZE = 64;
    meta::VectorizedArray<Amount, BATCH_SIZE> batch_amounts_;
    meta::VectorizedArray<Price, BATCH_SIZE> batch_prices_;
    
public:
    OptimizedMatchingEngine() 
        : best_bid_(0), best_ask_(UINT64_MAX), total_matches_(0), total_volume_(0) {}
    
    // Template-optimized order matching
    template<OrderSide Side>
    HOT FORCE_INLINE MatchResult matchOrder(Price price, Amount amount) noexcept {
        constexpr bool is_buy = (Side == OrderSide::Buy);
        
        if constexpr (is_buy) {
            return matchBuyOrder(price, amount);
        } else {
            return matchSellOrder(price, amount);
        }
    }
    
    // Specialized buy order matching with branch prediction hints
    HOT MatchResult matchBuyOrder(Price price, Amount amount) noexcept {
        Price current_ask = best_ask_.load(std::memory_order_relaxed);
        
        // Fast path: check if matching is possible
        if (UNLIKELY(current_ask == UINT64_MAX || price < current_ask)) {
            return MatchResult{0, amount, 0, OrderError::Success};
        }
        
        return executeBuyMatching(price, amount);
    }
    
    // Specialized sell order matching with branch prediction hints
    HOT MatchResult matchSellOrder(Price price, Amount amount) noexcept {
        Price current_bid = best_bid_.load(std::memory_order_relaxed);
        
        // Fast path: check if matching is possible
        if (UNLIKELY(current_bid == 0 || price > current_bid)) {
            return MatchResult{0, amount, 0, OrderError::Success};
        }
        
        return executeSellMatching(price, amount);
    }
    
    // SIMD-optimized batch matching
    template<OrderSide Side>
    HOT std::vector<MatchResult> matchOrdersBatch(
        const meta::VectorizedArray<Price, BATCH_SIZE>& prices,
        const meta::VectorizedArray<Amount, BATCH_SIZE>& amounts,
        std::size_t count) noexcept {
        
        std::vector<MatchResult> results;
        results.reserve(count);
        
#ifdef __AVX512F__
        // Use AVX-512 for 8-way parallel matching
        constexpr std::size_t SIMD_WIDTH = 8;
        const std::size_t vector_batches = count / SIMD_WIDTH;
        
        for (std::size_t batch = 0; batch < vector_batches; ++batch) {
            const std::size_t start_idx = batch * SIMD_WIDTH;
            
            // Load prices and amounts
            __m512i price_vec = simd::load_prices_512(&prices[start_idx]);
            __m512i amount_vec = simd::load_amounts_512(&amounts[start_idx]);
            
            // Get best opposing price
            Price opposing_price;
            if constexpr (Side == OrderSide::Buy) {
                opposing_price = best_ask_.load(std::memory_order_relaxed);
            } else {
                opposing_price = best_bid_.load(std::memory_order_relaxed);
            }
            
            __m512i opposing_vec = simd::broadcast_amount_512(opposing_price);
            
            // Compare prices for matching
            __mmask8 can_match_mask;
            if constexpr (Side == OrderSide::Buy) {
                can_match_mask = simd::compare_buy_prices_512(price_vec, opposing_vec);
            } else {
                can_match_mask = simd::compare_sell_prices_512(price_vec, opposing_vec);
            }
            
            // Process matches
            for (int i = 0; i < SIMD_WIDTH; ++i) {
                if (can_match_mask & (1 << i)) {
                    // Execute individual match
                    results.emplace_back(matchOrder<Side>(prices[start_idx + i], amounts[start_idx + i]));
                } else {
                    // No match possible
                    results.emplace_back(0, amounts[start_idx + i], 0, OrderError::Success);
                }
            }
        }
        
        // Handle remainder
        for (std::size_t i = vector_batches * SIMD_WIDTH; i < count; ++i) {
            results.emplace_back(matchOrder<Side>(prices[i], amounts[i]));
        }
        
#elif defined(__AVX2__)
        // Use AVX2 for 4-way parallel matching
        constexpr std::size_t SIMD_WIDTH = 4;
        const std::size_t vector_batches = count / SIMD_WIDTH;
        
        for (std::size_t batch = 0; batch < vector_batches; ++batch) {
            const std::size_t start_idx = batch * SIMD_WIDTH;
            
            // Similar AVX2 implementation...
            for (int i = 0; i < SIMD_WIDTH; ++i) {
                results.emplace_back(matchOrder<Side>(prices[start_idx + i], amounts[start_idx + i]));
            }
        }
        
        // Handle remainder
        for (std::size_t i = vector_batches * SIMD_WIDTH; i < count; ++i) {
            results.emplace_back(matchOrder<Side>(prices[i], amounts[i]));
        }
#else
        // Fallback scalar implementation
        for (std::size_t i = 0; i < count; ++i) {
            results.emplace_back(matchOrder<Side>(prices[i], amounts[i]));
        }
#endif
        
        return results;
    }
    
    // Add order to price level with lock-free updates
    template<OrderSide Side>
    HOT void addOrderToLevel(Price price, Amount amount) noexcept {
        if constexpr (Side == OrderSide::Buy) {
            bid_levels_.insertOrUpdate(price, static_cast<std::int64_t>(amount), 1);
            updateBestBid(price);
        } else {
            ask_levels_.insertOrUpdate(price, static_cast<std::int64_t>(amount), 1);
            updateBestAsk(price);
        }
    }
    
    // Remove order from price level
    template<OrderSide Side>
    HOT void removeOrderFromLevel(Price price, Amount amount) noexcept {
        if constexpr (Side == OrderSide::Buy) {
            bid_levels_.insertOrUpdate(price, -static_cast<std::int64_t>(amount), -1);
        } else {
            ask_levels_.insertOrUpdate(price, -static_cast<std::int64_t>(amount), -1);
        }
        
        // Check if we need to update best prices
        updateBestPrices();
    }
    
    // Get market data with optimized access patterns
    HOT std::optional<Price> getBestBid() const noexcept {
        Price bid = best_bid_.load(std::memory_order_relaxed);
        return (bid > 0) ? std::optional<Price>(bid) : std::nullopt;
    }
    
    HOT std::optional<Price> getBestAsk() const noexcept {
        Price ask = best_ask_.load(std::memory_order_relaxed);
        return (ask < UINT64_MAX) ? std::optional<Price>(ask) : std::nullopt;
    }
    
    HOT std::optional<Price> getSpread() const noexcept {
        Price bid = best_bid_.load(std::memory_order_relaxed);
        Price ask = best_ask_.load(std::memory_order_relaxed);
        
        if (LIKELY(bid > 0 && ask < UINT64_MAX && ask > bid)) {
            return ask - bid;
        }
        return std::nullopt;
    }
    
    HOT std::optional<Price> getMidpoint() const noexcept {
        Price bid = best_bid_.load(std::memory_order_relaxed);
        Price ask = best_ask_.load(std::memory_order_relaxed);
        
        if (LIKELY(bid > 0 && ask < UINT64_MAX && ask > bid)) {
            return (bid + ask) / 2;
        }
        return std::nullopt;
    }
    
    // Performance statistics
    struct PerformanceStats {
        std::uint64_t total_matches;
        std::uint64_t total_volume;
        double matches_per_second;
        double volume_per_second;
    };
    
    PerformanceStats getPerformanceStats() const noexcept {
        return {
            total_matches_.load(std::memory_order_relaxed),
            total_volume_.load(std::memory_order_relaxed),
            0.0, // Would need timing data
            0.0  // Would need timing data
        };
    }

private:
    // Internal matching implementations
    NEVER_INLINE MatchResult executeBuyMatching(Price price, Amount amount) noexcept {
        // Complex matching logic moved to separate function to keep hot path lean
        Amount filled = 0;
        Price execution_price = 0;
        
        // TODO: Implement detailed matching logic
        // This is a simplified version for compilation
        
        total_matches_.fetch_add(1, std::memory_order_relaxed);
        total_volume_.fetch_add(filled, std::memory_order_relaxed);
        
        return MatchResult{filled, amount - filled, execution_price, OrderError::Success};
    }
    
    NEVER_INLINE MatchResult executeSellMatching(Price price, Amount amount) noexcept {
        // Complex matching logic moved to separate function to keep hot path lean
        Amount filled = 0;
        Price execution_price = 0;
        
        // TODO: Implement detailed matching logic
        // This is a simplified version for compilation
        
        total_matches_.fetch_add(1, std::memory_order_relaxed);
        total_volume_.fetch_add(filled, std::memory_order_relaxed);
        
        return MatchResult{filled, amount - filled, execution_price, OrderError::Success};
    }
    
    // Update best bid price
    HOT void updateBestBid(Price price) noexcept {
        Price current_best = best_bid_.load(std::memory_order_relaxed);
        while (price > current_best) {
            if (best_bid_.compare_exchange_weak(current_best, price, std::memory_order_relaxed)) {
                break;
            }
        }
    }
    
    // Update best ask price
    HOT void updateBestAsk(Price price) noexcept {
        Price current_best = best_ask_.load(std::memory_order_relaxed);
        while (price < current_best) {
            if (best_ask_.compare_exchange_weak(current_best, price, std::memory_order_relaxed)) {
                break;
            }
        }
    }
    
    // Periodically update best prices (cold path)
    COLD void updateBestPrices() noexcept {
        // This would involve scanning the price levels
        // Implementation omitted for brevity
    }
};

// Template specializations for different order types
template<OrderType Type>
class SpecializedMatcher;

template<>
class SpecializedMatcher<OrderType::Market> {
public:
    template<OrderSide Side>
    static HOT MatchResult match(OptimizedMatchingEngine& engine, Amount amount) noexcept {
        // Market orders always execute at best available price
        if constexpr (Side == OrderSide::Buy) {
            auto best_ask = engine.getBestAsk();
            if (UNLIKELY(!best_ask.has_value())) {
                return MatchResult{0, amount, 0, OrderError::NoBestAsk};
            }
            return engine.matchOrder<Side>(best_ask.value(), amount);
        } else {
            auto best_bid = engine.getBestBid();
            if (UNLIKELY(!best_bid.has_value())) {
                return MatchResult{0, amount, 0, OrderError::NoBestBid};
            }
            return engine.matchOrder<Side>(best_bid.value(), amount);
        }
    }
};

template<>
class SpecializedMatcher<OrderType::IOC> {
public:
    template<OrderSide Side>
    static HOT MatchResult match(OptimizedMatchingEngine& engine, Price price, Amount amount) noexcept {
        // IOC orders: execute immediately or cancel
        auto result = engine.matchOrder<Side>(price, amount);
        
        // For IOC, any unfilled amount is cancelled
        if (result.remaining_amount > 0) {
            result.remaining_amount = 0;
        }
        
        return result;
    }
};

template<>
class SpecializedMatcher<OrderType::FOK> {
public:
    template<OrderSide Side>
    static HOT MatchResult match(OptimizedMatchingEngine& engine, Price price, Amount amount) noexcept {
        // FOK orders: fill completely or not at all
        auto result = engine.matchOrder<Side>(price, amount);
        
        // For FOK, must fill completely
        if (result.filled_amount < amount) {
            return MatchResult{0, amount, 0, OrderError::InsufficientLiquidity};
        }
        
        return result;
    }
};

} // namespace abyssbook