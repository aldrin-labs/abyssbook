#pragma once

#include "common.hpp"
#include <immintrin.h>
#include <cpuid.h>

namespace abyssbook {
namespace simd {

//=============================================================================
// Runtime SIMD Feature Detection
//=============================================================================

struct SIMDCapabilities {
    bool sse42;
    bool avx;
    bool avx2;
    bool avx512f;
    bool avx512dq;
    bool avx512bw;
    bool bmi1;
    bool bmi2;
    bool lzcnt;
    bool popcnt;
    
    SIMDCapabilities() : sse42(false), avx(false), avx2(false), avx512f(false),
                        avx512dq(false), avx512bw(false), bmi1(false), bmi2(false),
                        lzcnt(false), popcnt(false) {}
};

class SIMDDetector {
private:
    static SIMDCapabilities capabilities_;
    static bool initialized_;
    
    static void detectCPUID() {
        unsigned int eax, ebx, ecx, edx;
        
        // Check for CPUID support
        if (__get_cpuid(1, &eax, &ebx, &ecx, &edx)) {
            capabilities_.sse42 = (ecx & bit_SSE4_2) != 0;
            capabilities_.avx = (ecx & bit_AVX) != 0;
            capabilities_.popcnt = (ecx & bit_POPCNT) != 0;
        }
        
        // Check for AVX2 and other extended features
        if (__get_cpuid_count(7, 0, &eax, &ebx, &ecx, &edx)) {
            capabilities_.avx2 = (ebx & bit_AVX2) != 0;
            capabilities_.bmi1 = (ebx & bit_BMI) != 0;
            capabilities_.bmi2 = (ebx & bit_BMI2) != 0;
            capabilities_.avx512f = (ebx & bit_AVX512F) != 0;
            capabilities_.avx512dq = (ebx & bit_AVX512DQ) != 0;
            capabilities_.avx512bw = (ebx & bit_AVX512BW) != 0;
        }
        
        // Check for LZCNT (part of ABM/LZCNT)
        if (__get_cpuid(0x80000001, &eax, &ebx, &ecx, &edx)) {
            capabilities_.lzcnt = (ecx & bit_LZCNT) != 0;
        }
    }
    
public:
    static const SIMDCapabilities& getCapabilities() {
        if (!initialized_) {
            detectCPUID();
            initialized_ = true;
        }
        return capabilities_;
    }
    
    static bool hasSSE42() { return getCapabilities().sse42; }
    static bool hasAVX() { return getCapabilities().avx; }
    static bool hasAVX2() { return getCapabilities().avx2; }
    static bool hasAVX512F() { return getCapabilities().avx512f; }
    static bool hasAVX512DQ() { return getCapabilities().avx512dq; }
    static bool hasAVX512BW() { return getCapabilities().avx512bw; }
    static bool hasBMI1() { return getCapabilities().bmi1; }
    static bool hasBMI2() { return getCapabilities().bmi2; }
    static bool hasLZCNT() { return getCapabilities().lzcnt; }
    static bool hasPOPCNT() { return getCapabilities().popcnt; }
    
    static void printCapabilities() {
        const auto& caps = getCapabilities();
        printf("SIMD Capabilities:\n");
        printf("  SSE4.2: %s\n", caps.sse42 ? "Yes" : "No");
        printf("  AVX:    %s\n", caps.avx ? "Yes" : "No");
        printf("  AVX2:   %s\n", caps.avx2 ? "Yes" : "No");
        printf("  AVX512F: %s\n", caps.avx512f ? "Yes" : "No");
        printf("  AVX512DQ: %s\n", caps.avx512dq ? "Yes" : "No");
        printf("  AVX512BW: %s\n", caps.avx512bw ? "Yes" : "No");
        printf("  BMI1:   %s\n", caps.bmi1 ? "Yes" : "No");
        printf("  BMI2:   %s\n", caps.bmi2 ? "Yes" : "No");
        printf("  LZCNT:  %s\n", caps.lzcnt ? "Yes" : "No");
        printf("  POPCNT: %s\n", caps.popcnt ? "Yes" : "No");
    }
};

// Static member definitions
SIMDCapabilities SIMDDetector::capabilities_;
bool SIMDDetector::initialized_ = false;

//=============================================================================
// Optimized SIMD Comparison Functions with Runtime Dispatch
//=============================================================================

// Price comparison with runtime SIMD dispatch
template<typename PriceType>
HOT FORCE_INLINE int comparePricesOptimized(const PriceType* prices1, const PriceType* prices2, size_t count) {
    static_assert(std::is_arithmetic_v<PriceType>, "PriceType must be arithmetic");
    
    // Ensure proper type handling for signed/unsigned comparisons
    if constexpr (std::is_floating_point_v<PriceType>) {
        // Floating point comparison
        #ifdef HAS_AVX2_SUPPORT
        if (SIMDDetector::hasAVX2() && count >= 8) {
            return comparePricesAVX2(prices1, prices2, count);
        }
        #endif
        
        #ifdef HAS_AVX_SUPPORT
        if (SIMDDetector::hasAVX() && count >= 4) {
            return comparePricesAVX(prices1, prices2, count);
        }
        #endif
        
        return comparePricesScalar(prices1, prices2, count);
    } else {
        // Integer comparison with proper signed/unsigned handling
        if constexpr (std::is_signed_v<PriceType>) {
            return comparePricesIntegerSigned(prices1, prices2, count);
        } else {
            return comparePricesIntegerUnsigned(prices1, prices2, count);
        }
    }
}

// AVX2 float comparison
HOT FORCE_INLINE int comparePricesAVX2(const float* prices1, const float* prices2, size_t count) {
    size_t simd_count = count - (count % 8);
    
    for (size_t i = 0; i < simd_count; i += 8) {
        __m256 p1 = _mm256_load_ps(&prices1[i]);
        __m256 p2 = _mm256_load_ps(&prices2[i]);
        __m256 cmp = _mm256_cmp_ps(p1, p2, _CMP_LT_OQ);
        
        int mask = _mm256_movemask_ps(cmp);
        if (mask != 0) {
            // Find first different element
            return __builtin_ctz(mask) + i;
        }
    }
    
    // Handle remaining elements
    for (size_t i = simd_count; i < count; ++i) {
        if (prices1[i] != prices2[i]) {
            return static_cast<int>(i);
        }
    }
    
    return -1; // All equal
}

// AVX float comparison
HOT FORCE_INLINE int comparePricesAVX(const float* prices1, const float* prices2, size_t count) {
    size_t simd_count = count - (count % 4);
    
    for (size_t i = 0; i < simd_count; i += 4) {
        __m128 p1 = _mm_load_ps(&prices1[i]);
        __m128 p2 = _mm_load_ps(&prices2[i]);
        __m128 cmp = _mm_cmp_ps(p1, p2, _CMP_NEQ_OQ);
        
        int mask = _mm_movemask_ps(cmp);
        if (mask != 0) {
            return __builtin_ctz(mask) + i;
        }
    }
    
    // Handle remaining elements
    for (size_t i = simd_count; i < count; ++i) {
        if (prices1[i] != prices2[i]) {
            return static_cast<int>(i);
        }
    }
    
    return -1; // All equal
}

// Scalar comparison fallback
template<typename PriceType>
HOT FORCE_INLINE int comparePricesScalar(const PriceType* prices1, const PriceType* prices2, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        if (prices1[i] != prices2[i]) {
            return static_cast<int>(i);
        }
    }
    return -1; // All equal
}

// Signed integer comparison with proper handling
template<typename SignedInt>
HOT FORCE_INLINE int comparePricesIntegerSigned(const SignedInt* prices1, const SignedInt* prices2, size_t count) {
    static_assert(std::is_signed_v<SignedInt>, "Type must be signed integer");
    
    for (size_t i = 0; i < count; ++i) {
        // Use proper signed comparison
        if (prices1[i] != prices2[i]) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

// Unsigned integer comparison with proper handling
template<typename UnsignedInt>
HOT FORCE_INLINE int comparePricesIntegerUnsigned(const UnsignedInt* prices1, const UnsignedInt* prices2, size_t count) {
    static_assert(std::is_unsigned_v<UnsignedInt>, "Type must be unsigned integer");
    
    for (size_t i = 0; i < count; ++i) {
        // Use proper unsigned comparison
        if (prices1[i] != prices2[i]) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

//=============================================================================
// SIMD-Optimized Search Functions
//=============================================================================

template<typename T>
HOT FORCE_INLINE size_t vectorizedSearch(const T* array, size_t count, T target) {
    static_assert(std::is_arithmetic_v<T>, "T must be arithmetic type");
    
    if constexpr (std::is_same_v<T, float>) {
        #ifdef HAS_AVX2_SUPPORT
        if (SIMDDetector::hasAVX2() && count >= 8) {
            return vectorizedSearchFloatAVX2(array, count, target);
        }
        #endif
        
        #ifdef HAS_AVX_SUPPORT
        if (SIMDDetector::hasAVX() && count >= 4) {
            return vectorizedSearchFloatAVX(array, count, target);
        }
        #endif
    }
    
    // Fallback to scalar search
    for (size_t i = 0; i < count; ++i) {
        if (array[i] == target) {
            return i;
        }
    }
    return count; // Not found
}

HOT FORCE_INLINE size_t vectorizedSearchFloatAVX2(const float* array, size_t count, float target) {
    __m256 target_vec = _mm256_set1_ps(target);
    size_t simd_count = count - (count % 8);
    
    for (size_t i = 0; i < simd_count; i += 8) {
        __m256 data = _mm256_load_ps(&array[i]);
        __m256 cmp = _mm256_cmp_ps(data, target_vec, _CMP_EQ_OQ);
        int mask = _mm256_movemask_ps(cmp);
        
        if (mask != 0) {
            return i + __builtin_ctz(mask);
        }
    }
    
    // Check remaining elements
    for (size_t i = simd_count; i < count; ++i) {
        if (array[i] == target) {
            return i;
        }
    }
    
    return count; // Not found
}

HOT FORCE_INLINE size_t vectorizedSearchFloatAVX(const float* array, size_t count, float target) {
    __m128 target_vec = _mm_set1_ps(target);
    size_t simd_count = count - (count % 4);
    
    for (size_t i = 0; i < simd_count; i += 4) {
        __m128 data = _mm_load_ps(&array[i]);
        __m128 cmp = _mm_cmp_ps(data, target_vec, _CMP_EQ_OQ);
        int mask = _mm_movemask_ps(cmp);
        
        if (mask != 0) {
            return i + __builtin_ctz(mask);
        }
    }
    
    // Check remaining elements
    for (size_t i = simd_count; i < count; ++i) {
        if (array[i] == target) {
            return i;
        }
    }
    
    return count; // Not found
}

} // namespace simd
} // namespace abyssbook