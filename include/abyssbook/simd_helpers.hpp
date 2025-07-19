#pragma once

#include "common.hpp"
#include <immintrin.h>
#include <cstring>

namespace abyssbook {
namespace simd {

// SIMD helper functions for vectorized operations

#ifdef __AVX512F__

// AVX-512 optimized functions for 8x 64-bit values
constexpr std::size_t AVX512_VECTOR_WIDTH = 8;

// Load 8 64-bit values into AVX-512 register
inline __m512i load_prices_512(const Price* prices) {
    return _mm512_loadu_si512(reinterpret_cast<const __m512i*>(prices));
}

// Load 8 64-bit amounts into AVX-512 register
inline __m512i load_amounts_512(const Amount* amounts) {
    return _mm512_loadu_si512(reinterpret_cast<const __m512i*>(amounts));
}

// Store 8 64-bit values from AVX-512 register
inline void store_amounts_512(Amount* amounts, __m512i values) {
    _mm512_storeu_si512(reinterpret_cast<__m512i*>(amounts), values);
}

// Compare prices for buy orders using AVX-512
inline __mmask8 compare_buy_prices_512(__m512i our_prices, __m512i their_prices) {
    return _mm512_cmpge_epu64_mask(our_prices, their_prices);
}

// Compare prices for sell orders using AVX-512
inline __mmask8 compare_sell_prices_512(__m512i our_prices, __m512i their_prices) {
    return _mm512_cmple_epu64_mask(our_prices, their_prices);
}

// Select values based on mask using AVX-512
inline __m512i select_amounts_512(__mmask8 mask, __m512i true_values, __m512i false_values) {
    return _mm512_mask_blend_epi64(mask, false_values, true_values);
}

// Sum all elements in a 512-bit register containing 8 64-bit integers
inline Amount horizontal_sum_512(__m512i values) {
    // Extract high and low 256-bit lanes
    __m256i low = _mm512_extracti64x4_epi64(values, 0);
    __m256i high = _mm512_extracti64x4_epi64(values, 1);
    
    // Add the lanes together
    __m256i sum256 = _mm256_add_epi64(low, high);
    
    // Use manual horizontal sum for 256-bit
    __m128i low128 = _mm256_extracti128_si256(sum256, 0);
    __m128i high128 = _mm256_extracti128_si256(sum256, 1);
    
    // Add the lanes together
    __m128i sum128 = _mm_add_epi64(low128, high128);
    
    // Extract the two 64-bit values and add them
    std::uint64_t low_val = _mm_extract_epi64(sum128, 0);
    std::uint64_t high_val = _mm_extract_epi64(sum128, 1);
    
    return low_val + high_val;
}

// Vectorized minimum operation for 8 amounts using AVX-512
inline __m512i min_amounts_512(__m512i a, __m512i b) {
    return _mm512_min_epu64(a, b);
}

// Vectorized maximum operation for 8 amounts using AVX-512
inline __m512i max_amounts_512(__m512i a, __m512i b) {
    return _mm512_max_epu64(a, b);
}

// Saturating subtraction for amounts using AVX-512
inline __m512i saturating_sub_512(__m512i a, __m512i b) {
    __mmask8 underflow = _mm512_cmpgt_epu64_mask(b, a);
    __m512i result = _mm512_sub_epi64(a, b);
    return _mm512_mask_mov_epi64(result, underflow, _mm512_setzero_si512());
}

// Saturating addition with overflow protection using AVX-512
inline __m512i saturating_add_512(__m512i a, __m512i b) {
    __m512i result = _mm512_add_epi64(a, b);
    __mmask8 overflow = _mm512_cmplt_epu64_mask(result, a);
    __m512i max_val = _mm512_set1_epi64(static_cast<std::int64_t>(UINT64_MAX));
    return _mm512_mask_mov_epi64(result, overflow, max_val);
}

// Broadcast a single value to all 8 elements using AVX-512
inline __m512i broadcast_amount_512(Amount value) {
    return _mm512_set1_epi64(static_cast<std::int64_t>(value));
}

// Optimized batch matching using AVX-512
inline void vectorized_match_amounts_512(
    const Amount* our_amounts,
    const Amount* their_amounts,
    const bool* should_match,
    Amount* matched_amounts,
    std::size_t count
) {
    const std::size_t vector_count = count / AVX512_VECTOR_WIDTH;
    const std::size_t remainder = count % AVX512_VECTOR_WIDTH;
    
    for (std::size_t i = 0; i < vector_count; ++i) {
        const std::size_t idx = i * AVX512_VECTOR_WIDTH;
        
        // Load data
        __m512i our_vals = load_amounts_512(&our_amounts[idx]);
        __m512i their_vals = load_amounts_512(&their_amounts[idx]);
        
        // Create mask from boolean array
        __mmask8 match_mask = 0;
        for (int j = 0; j < AVX512_VECTOR_WIDTH; ++j) {
            if (should_match[idx + j]) {
                match_mask |= (1 << j);
            }
        }
        
        // Calculate minimum and apply mask
        __m512i min_vals = min_amounts_512(our_vals, their_vals);
        __m512i result = _mm512_mask_mov_epi64(_mm512_setzero_si512(), match_mask, min_vals);
        
        // Store result
        store_amounts_512(&matched_amounts[idx], result);
    }
    
    // Handle remainder with scalar code
    for (std::size_t i = vector_count * AVX512_VECTOR_WIDTH; i < count; ++i) {
        matched_amounts[i] = should_match[i] ? 
            std::min(our_amounts[i], their_amounts[i]) : 0;
    }
}

#elif defined(__AVX2__)

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