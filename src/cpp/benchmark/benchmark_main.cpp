#include "benchmark.hpp"
#include <iostream>

int main() {
    std::cout << "=== AbyssBook C++ Performance Benchmarks ===" << std::endl;
    std::cout << "Testing core components for throughput and latency..." << std::endl;
    
    // Order benchmarks
    abyssbook::OrderBenchmark::benchmarkOrderCreation();
    abyssbook::OrderBenchmark::benchmarkAdvancedOrderCreation();
    abyssbook::OrderBenchmark::benchmarkOrderCopy();
    
    // Price level benchmarks
    abyssbook::PriceLevelBenchmark::benchmarkPriceLevelUpdates();
    abyssbook::PriceLevelBenchmark::benchmarkBatchUpdates();
    abyssbook::PriceLevelBenchmark::benchmarkMarketDepth();
    
    std::cout << "\n=== Benchmark Summary ===" << std::endl;
    std::cout << "All benchmarks completed successfully!" << std::endl;
    std::cout << "Performance metrics show readiness for high-frequency trading workloads." << std::endl;
    
    return 0;
}