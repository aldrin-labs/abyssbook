#pragma once

namespace abyssbook {

class OrderBenchmark {
public:
    static void benchmarkOrderCreation();
    static void benchmarkAdvancedOrderCreation();
    static void benchmarkOrderCopy();
};

class PriceLevelBenchmark {
public:
    static void benchmarkPriceLevelUpdates();
    static void benchmarkBatchUpdates();
    static void benchmarkMarketDepth();
};

} // namespace abyssbook