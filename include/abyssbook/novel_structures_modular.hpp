#pragma once

//=============================================================================
// Modular Novel Structures - High-Performance Financial Data Structures
//=============================================================================
// This header provides a modular approach to including novel data structures
// optimized for financial trading applications. Each structure is now in its
// own header file for faster compilation and better maintainability.

// Individual structure headers
#include "structures/financial_btree.hpp"
#include "structures/van_emde_boas.hpp"
#include "structures/orderbook_pyramid.hpp"

namespace abyssbook {
namespace novel {

//=============================================================================
// Structure Factory and Utilities
//=============================================================================

template<typename Key, typename Value>
using DefaultFinancialTree = FinancialBPlusTree<Key, Value, 64>;

using DefaultVEB = VanEmdeBoas<16>;
using OrderPyramid = OrderBookPyramid;

// Type aliases for common use cases
using PriceTree = DefaultFinancialTree<double, uint64_t>;
using OrderIdTree = DefaultFinancialTree<uint64_t, uint32_t>;
using TimestampVEB = VanEmdeBoas<32>;

//=============================================================================
// Performance Benchmarking Utilities
//=============================================================================

struct StructureMetrics {
    uint64_t insert_operations = 0;
    uint64_t lookup_operations = 0;
    uint64_t delete_operations = 0;
    uint64_t total_time_ns = 0;
    
    double getOpsPerSecond() const {
        if (total_time_ns == 0) return 0.0;
        uint64_t total_ops = insert_operations + lookup_operations + delete_operations;
        return (total_ops * 1e9) / total_time_ns;
    }
};

} // namespace novel
} // namespace abyssbook