#pragma once

#include "common.hpp"
#include <type_traits>
#include <concepts>

namespace abyssbook {
namespace meta {

// Concepts for type constraints
template<typename T>
concept NumericType = std::is_arithmetic_v<T>;

template<typename T>
concept OrderIdType = std::is_same_v<T, OrderId> || std::is_convertible_v<T, OrderId>;

template<typename T>
concept PriceType = std::is_same_v<T, Price> || std::is_convertible_v<T, Price>;

template<typename T>
concept AmountType = std::is_same_v<T, Amount> || std::is_convertible_v<T, Amount>;

// Compile-time string hash for switch statements on order types
constexpr std::uint64_t string_hash(const char* str, std::size_t len) {
    std::uint64_t hash = 14695981039346656037ULL;
    for (std::size_t i = 0; i < len; ++i) {
        hash ^= static_cast<std::uint64_t>(str[i]);
        hash *= 1099511628211ULL;
    }
    return hash;
}

constexpr std::uint64_t operator""_hash(const char* str, std::size_t len) {
    return string_hash(str, len);
}

// Template for fast bit operations
template<NumericType T>
constexpr T bit_count(T value) noexcept {
    if constexpr (sizeof(T) <= sizeof(unsigned int)) {
        return __builtin_popcount(static_cast<unsigned int>(value));
    } else if constexpr (sizeof(T) <= sizeof(unsigned long)) {
        return __builtin_popcountl(static_cast<unsigned long>(value));
    } else {
        return __builtin_popcountll(static_cast<unsigned long long>(value));
    }
}

template<NumericType T>
constexpr T leading_zeros(T value) noexcept {
    if (value == 0) return sizeof(T) * 8;
    
    if constexpr (sizeof(T) <= sizeof(unsigned int)) {
        return __builtin_clz(static_cast<unsigned int>(value)) - (sizeof(unsigned int) - sizeof(T)) * 8;
    } else if constexpr (sizeof(T) <= sizeof(unsigned long)) {
        return __builtin_clzl(static_cast<unsigned long>(value)) - (sizeof(unsigned long) - sizeof(T)) * 8;
    } else {
        return __builtin_clzll(static_cast<unsigned long long>(value)) - (sizeof(unsigned long long) - sizeof(T)) * 8;
    }
}

template<NumericType T>
constexpr T trailing_zeros(T value) noexcept {
    if (value == 0) return sizeof(T) * 8;
    
    if constexpr (sizeof(T) <= sizeof(unsigned int)) {
        return __builtin_ctz(static_cast<unsigned int>(value));
    } else if constexpr (sizeof(T) <= sizeof(unsigned long)) {
        return __builtin_ctzl(static_cast<unsigned long>(value));
    } else {
        return __builtin_ctzll(static_cast<unsigned long long>(value));
    }
}

// Fast log2 for power-of-two sizes
template<NumericType T>
constexpr T fast_log2(T value) noexcept {
    return sizeof(T) * 8 - 1 - leading_zeros(value);
}

// Check if value is power of 2
template<NumericType T>
constexpr bool is_power_of_2(T value) noexcept {
    return value > 0 && (value & (value - 1)) == 0;
}

// Round up to next power of 2
template<NumericType T>
constexpr T next_power_of_2(T value) noexcept {
    if (value <= 1) return 1;
    return T(1) << (fast_log2(value - 1) + 1);
}

// Template specializations for order type operations
template<OrderType Type>
struct OrderTypeTraits;

template<>
struct OrderTypeTraits<OrderType::Limit> {
    static constexpr bool requires_price = true;
    static constexpr bool requires_amount = true;
    static constexpr bool can_be_partially_filled = true;
    static constexpr bool triggers_immediately = false;
    static constexpr bool has_time_priority = true;
};

template<>
struct OrderTypeTraits<OrderType::Market> {
    static constexpr bool requires_price = false;
    static constexpr bool requires_amount = true;
    static constexpr bool can_be_partially_filled = true;
    static constexpr bool triggers_immediately = true;
    static constexpr bool has_time_priority = false;
};

template<>
struct OrderTypeTraits<OrderType::IOC> {
    static constexpr bool requires_price = true;
    static constexpr bool requires_amount = true;
    static constexpr bool can_be_partially_filled = true;
    static constexpr bool triggers_immediately = true;
    static constexpr bool has_time_priority = true;
};

template<>
struct OrderTypeTraits<OrderType::FOK> {
    static constexpr bool requires_price = true;
    static constexpr bool requires_amount = true;
    static constexpr bool can_be_partially_filled = false;
    static constexpr bool triggers_immediately = true;
    static constexpr bool has_time_priority = true;
};

// Template for optimized order matching based on side
template<OrderSide Side>
struct OrderSideTraits;

template<>
struct OrderSideTraits<OrderSide::Buy> {
    static constexpr bool is_buy = true;
    static constexpr OrderSide opposite = OrderSide::Sell;
    
    template<PriceType P1, PriceType P2>
    static constexpr bool can_match(P1 our_price, P2 their_price) noexcept {
        return our_price >= their_price;
    }
    
    template<PriceType P1, PriceType P2>
    static constexpr bool is_better_price(P1 price1, P2 price2) noexcept {
        return price1 > price2; // Higher is better for buy orders
    }
};

template<>
struct OrderSideTraits<OrderSide::Sell> {
    static constexpr bool is_buy = false;
    static constexpr OrderSide opposite = OrderSide::Buy;
    
    template<PriceType P1, PriceType P2>
    static constexpr bool can_match(P1 our_price, P2 their_price) noexcept {
        return our_price <= their_price;
    }
    
    template<PriceType P1, PriceType P2>
    static constexpr bool is_better_price(P1 price1, P2 price2) noexcept {
        return price1 < price2; // Lower is better for sell orders
    }
};

// Optimized order matching function using templates
template<OrderSide Side>
constexpr bool can_orders_match(Price our_price, Price their_price) noexcept {
    return OrderSideTraits<Side>::can_match(our_price, their_price);
}

// SFINAE helper for template specialization
template<typename T, typename = void>
struct has_simd_support : std::false_type {};

template<typename T>
struct has_simd_support<T, std::void_t<decltype(sizeof(T) == 8)>> : std::true_type {};

// Template for vectorized operations
template<typename T, std::size_t N>
struct VectorizedArray {
    static_assert(has_simd_support<T>::value, "Type must support SIMD operations");
    static_assert(is_power_of_2(N), "Array size must be power of 2");
    
    alignas(SIMD_ALIGNMENT) T data[N];
    
    constexpr VectorizedArray() : data{} {}
    
    template<typename... Args>
    constexpr VectorizedArray(Args... args) : data{static_cast<T>(args)...} {
        static_assert(sizeof...(args) <= N, "Too many initializers");
    }
    
    HOT FORCE_INLINE T& operator[](std::size_t idx) noexcept {
        return data[idx];
    }
    
    HOT FORCE_INLINE const T& operator[](std::size_t idx) const noexcept {
        return data[idx];
    }
    
    HOT FORCE_INLINE constexpr std::size_t size() const noexcept {
        return N;
    }
    
    HOT FORCE_INLINE T* begin() noexcept { return data; }
    HOT FORCE_INLINE T* end() noexcept { return data + N; }
    HOT FORCE_INLINE const T* begin() const noexcept { return data; }
    HOT FORCE_INLINE const T* end() const noexcept { return data + N; }
};

// Optimized compile-time lookups
template<std::size_t N>
constexpr std::array<std::uint64_t, N> generate_fibonacci_hash_table() {
    std::array<std::uint64_t, N> table{};
    constexpr std::uint64_t golden_ratio = 11400714819323198485ULL;
    
    for (std::size_t i = 0; i < N; ++i) {
        table[i] = (i * golden_ratio) >> (64 - fast_log2(N));
    }
    return table;
}

// Template for cache-friendly data structures
template<typename T>
struct CacheFriendlyVector {
    static_assert(sizeof(T) <= CACHE_LINE_SIZE, "Type too large for cache optimization");
    
    static constexpr std::size_t elements_per_cache_line = CACHE_LINE_SIZE / sizeof(T);
    
    struct CACHE_ALIGNED CacheLine {
        T elements[elements_per_cache_line];
    };
    
    std::vector<CacheLine> cache_lines;
    std::size_t size_;
    
    CacheFriendlyVector() : size_(0) {}
    
    HOT void push_back(const T& value) {
        std::size_t cache_line_idx = size_ / elements_per_cache_line;
        std::size_t element_idx = size_ % elements_per_cache_line;
        
        if (cache_line_idx >= cache_lines.size()) {
            cache_lines.emplace_back();
        }
        
        cache_lines[cache_line_idx].elements[element_idx] = value;
        ++size_;
    }
    
    HOT const T& operator[](std::size_t idx) const {
        std::size_t cache_line_idx = idx / elements_per_cache_line;
        std::size_t element_idx = idx % elements_per_cache_line;
        return cache_lines[cache_line_idx].elements[element_idx];
    }
    
    HOT T& operator[](std::size_t idx) {
        std::size_t cache_line_idx = idx / elements_per_cache_line;
        std::size_t element_idx = idx % elements_per_cache_line;
        return cache_lines[cache_line_idx].elements[element_idx];
    }
    
    HOT std::size_t size() const noexcept { return size_; }
    HOT bool empty() const noexcept { return size_ == 0; }
};

// Compile-time order validation
template<OrderType Type>
constexpr bool validate_order_type_requirements(bool has_price, bool has_amount) noexcept {
    return (!OrderTypeTraits<Type>::requires_price || has_price) &&
           (!OrderTypeTraits<Type>::requires_amount || has_amount);
}

// Template for optimized sorting based on order side
template<OrderSide Side>
struct PriceComparator {
    template<PriceType P1, PriceType P2>
    constexpr bool operator()(P1 a, P2 b) const noexcept {
        if constexpr (Side == OrderSide::Buy) {
            return a > b; // Descending for bids
        } else {
            return a < b; // Ascending for asks
        }
    }
};

} // namespace meta
} // namespace abyssbook