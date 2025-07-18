#pragma once

#include "common.hpp"
#include <immintrin.h>
#include <cstring>

namespace abyssbook {
namespace simd {

// SIMD helper functions for vectorized operations

#ifdef __AVX2__

// Load 4 64-bit values into AVX2 register
inline __m256i load_prices(const Price* prices) {
    return _mm256_loadu_si256(reinterpret_cast<const __m256i*>(prices));
}

// Load 4 64-bit amounts into AVX2 register
inline __m256i load_amounts(const Amount* amounts) {
    return _mm256_loadu_si256(reinterpret_cast<const __m256i*>(amounts));
}

// Store 4 64-bit values from AVX2 register
inline void store_amounts(Amount* amounts, __m256i values) {
    _mm256_storeu_si256(reinterpret_cast<__m256i*>(amounts), values);
}

// Compare prices for buy orders (our_price >= their_price)
inline __m256i compare_buy_prices(__m256i our_prices, __m256i their_prices) {
    return _mm256_cmpgt_epi64(our_prices, their_prices);
}

// Compare prices for sell orders (our_price <= their_price)
inline __m256i compare_sell_prices(__m256i our_prices, __m256i their_prices) {
    return _mm256_cmpgt_epi64(their_prices, our_prices);
}

// Select values based on mask
inline __m256i select_amounts(__m256i mask, __m256i true_values, __m256i false_values) {
    return _mm256_blendv_epi8(false_values, true_values, mask);
}

// Sum all elements in a 256-bit register containing 4 64-bit integers
inline Amount horizontal_sum(__m256i values) {
    // Extract high and low 128-bit lanes
    __m128i low = _mm256_extracti128_si256(values, 0);
    __m128i high = _mm256_extracti128_si256(values, 1);
    
    // Add the lanes together
    __m128i sum = _mm_add_epi64(low, high);
    
    // Extract the two 64-bit values and add them
    std::uint64_t low_val = _mm_extract_epi64(sum, 0);
    std::uint64_t high_val = _mm_extract_epi64(sum, 1);
    
    return low_val + high_val;
}

// Vectorized minimum operation for 4 amounts
inline __m256i min_amounts(__m256i a, __m256i b) {
    // AVX2 doesn't have direct 64-bit min, so we use compare and blend
    __m256i cmp = _mm256_cmpgt_epi64(a, b);
    return _mm256_blendv_epi8(a, b, cmp);
}

// Vectorized maximum operation for 4 amounts
inline __m256i max_amounts(__m256i a, __m256i b) {
    __m256i cmp = _mm256_cmpgt_epi64(a, b);
    return _mm256_blendv_epi8(b, a, cmp);
}

// Saturating subtraction for amounts
inline __m256i saturating_sub(__m256i a, __m256i b) {
    __m256i result = _mm256_sub_epi64(a, b);
    __m256i underflow = _mm256_cmpgt_epi64(b, a);
    return _mm256_andnot_si256(underflow, result);
}

// Saturating addition for amounts (with overflow protection)
inline __m256i saturating_add(__m256i a, __m256i b) {
    __m256i result = _mm256_add_epi64(a, b);
    // Check for overflow: if result < a, then overflow occurred
    __m256i overflow = _mm256_cmpgt_epi64(a, result);
    __m256i max_val = _mm256_set1_epi64x(static_cast<std::int64_t>(UINT64_MAX));
    return _mm256_blendv_epi8(result, max_val, overflow);
}

// Broadcast a single value to all 4 elements
inline __m256i broadcast_amount(Amount value) {
    return _mm256_set1_epi64x(static_cast<std::int64_t>(value));
}

// Create a mask from boolean array
inline __m256i create_mask(const bool* conditions) {
    CACHE_ALIGNED std::uint64_t mask_values[4];
    for (int i = 0; i < 4; ++i) {
        mask_values[i] = conditions[i] ? UINT64_MAX : 0;
    }
    return _mm256_loadu_si256(reinterpret_cast<const __m256i*>(mask_values));
}

// Extract mask to boolean array
inline void extract_mask(__m256i mask, bool* conditions) {
    CACHE_ALIGNED std::uint64_t mask_values[4];
    _mm256_storeu_si256(reinterpret_cast<__m256i*>(mask_values), mask);
    for (int i = 0; i < 4; ++i) {
        conditions[i] = (mask_values[i] != 0);
    }
}

#else // Fallback for non-AVX2 systems

// Fallback implementations using scalar operations
inline void vectorized_match_amounts(
    const Amount* our_amounts,
    const Amount* their_amounts,
    const bool* should_match,
    Amount* matched_amounts,
    std::size_t count
) {
    for (std::size_t i = 0; i < count; ++i) {
        if (should_match[i]) {
            matched_amounts[i] = std::min(our_amounts[i], their_amounts[i]);
        } else {
            matched_amounts[i] = 0;
        }
    }
}

inline Amount horizontal_sum_fallback(const Amount* values, std::size_t count) {
    Amount sum = 0;
    for (std::size_t i = 0; i < count; ++i) {
        sum += values[i];
    }
    return sum;
}

#endif

// Prefetch functions for cache optimization
inline void prefetch_read(const void* addr) {
#ifdef __GNUC__
    __builtin_prefetch(addr, 0, 3); // Read, high temporal locality
#elif defined(_MSC_VER)
    _mm_prefetch(static_cast<const char*>(addr), _MM_HINT_T0);
#endif
}

inline void prefetch_write(const void* addr) {
#ifdef __GNUC__
    __builtin_prefetch(addr, 1, 3); // Write, high temporal locality
#elif defined(_MSC_VER)
    _mm_prefetch(static_cast<const char*>(addr), _MM_HINT_T0);
#endif
}

// Memory fence operations
inline void memory_fence() {
#ifdef __GNUC__
    __sync_synchronize();
#elif defined(_MSC_VER)
    _mm_mfence();
#else
    std::atomic_thread_fence(std::memory_order_seq_cst);
#endif
}

inline void compiler_fence() {
#ifdef __GNUC__
    asm volatile("" ::: "memory");
#elif defined(_MSC_VER)
    _ReadWriteBarrier();
#else
    std::atomic_signal_fence(std::memory_order_seq_cst);
#endif
}

// Vectorized batch processing function for order matching
class VectorizedMatcher {
public:
    static constexpr std::size_t BATCH_SIZE = VECTOR_WIDTH;
    
    // Match orders in batches using SIMD
    static Amount matchOrdersBatch(
        const Price* our_prices,
        const Amount* our_amounts,
        const Price* their_prices,
        const Amount* their_amounts,
        OrderSide our_side,
        std::size_t count,
        Amount* matched_amounts
    );
    
    // Update price levels in batches
    static void updatePriceLevelsBatch(
        const Price* prices,
        const Amount* volume_deltas,
        const int* count_deltas,
        std::size_t count,
        std::function<void(Price, Amount, int)> update_func
    );
};

} // namespace simd
} // namespace abyssbook