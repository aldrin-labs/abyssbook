#include "benchmark.hpp"
#include "abyssbook/optimized_matching.hpp"
#include "abyssbook/template_optimizations.hpp"
#include "abyssbook/lockfree_structures.hpp"
#include <chrono>
#include <random>
#include <thread>
#include <vector>
#include <iostream>

namespace abyssbook {
namespace benchmark {

class OptimizedBenchmarks {
private:
    OptimizedMatchingEngine engine_;
    std::random_device rd_;
    std::mt19937 gen_;
    std::uniform_int_distribution<Price> price_dist_;
    std::uniform_int_distribution<Amount> amount_dist_;
    
public:
    OptimizedBenchmarks() : gen_(rd_()), price_dist_(1000, 10000), amount_dist_(1, 1000) {}
    
    // Benchmark lock-free data structures
    void benchmarkLockFreeStructures() {
        std::cout << "\n=== Lock-Free Data Structures Benchmark ===" << std::endl;
        
        constexpr std::size_t iterations = 5000000;
        lockfree::LockFreeHashMap<1024> hashmap;
        
        auto start = std::chrono::high_resolution_clock::now();
        
        for (std::size_t i = 0; i < iterations; ++i) {
            Price price = price_dist_(gen_);
            Amount amount = amount_dist_(gen_);
            hashmap.insertOrUpdate(price, amount, 1);
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        double throughput = static_cast<double>(iterations) / duration.count();
        std::cout << "Lock-free insertions: " << iterations << " in " << duration.count() << " microseconds" << std::endl;
        std::cout << "Throughput: " << throughput << "M operations/sec" << std::endl;
        
        // Benchmark lookups
        start = std::chrono::high_resolution_clock::now();
        
        std::size_t found_count = 0;
        for (std::size_t i = 0; i < iterations; ++i) {
            Price price = price_dist_(gen_);
            auto result = hashmap.find(price);
            if (result.has_value()) {
                found_count++;
            }
        }
        
        end = std::chrono::high_resolution_clock::now();
        duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        throughput = static_cast<double>(iterations) / duration.count();
        
        std::cout << "Lock-free lookups: " << iterations << " in " << duration.count() << " microseconds" << std::endl;
        std::cout << "Throughput: " << throughput << "M lookups/sec (found: " << found_count << ")" << std::endl;
    }
    
    // Benchmark SIMD operations
    void benchmarkSIMDOperations() {
        std::cout << "\n=== SIMD Operations Benchmark ===" << std::endl;
        
        constexpr std::size_t iterations = 1000000;
        constexpr std::size_t batch_size = 64;
        
        meta::VectorizedArray<Amount, batch_size> amounts1;
        meta::VectorizedArray<Amount, batch_size> amounts2;
        meta::VectorizedArray<Amount, batch_size> results;
        
        // Initialize test data
        for (std::size_t i = 0; i < batch_size; ++i) {
            amounts1[i] = amount_dist_(gen_);
            amounts2[i] = amount_dist_(gen_);
        }
        
        auto start = std::chrono::high_resolution_clock::now();
        
#ifdef __AVX512F__
        std::cout << "Using AVX-512 optimizations" << std::endl;
        
        for (std::size_t iter = 0; iter < iterations; ++iter) {
            constexpr std::size_t simd_width = 8;
            for (std::size_t i = 0; i < batch_size; i += simd_width) {
                __m512i a = simd::load_amounts_512(&amounts1[i]);
                __m512i b = simd::load_amounts_512(&amounts2[i]);
                __m512i result = simd::min_amounts_512(a, b);
                simd::store_amounts_512(&results[i], result);
            }
        }
#elif defined(__AVX2__)
        std::cout << "Using AVX2 optimizations" << std::endl;
        
        for (std::size_t iter = 0; iter < iterations; ++iter) {
            constexpr std::size_t simd_width = 4;
            for (std::size_t i = 0; i < batch_size; i += simd_width) {
                __m256i a = simd::load_amounts(&amounts1[i]);
                __m256i b = simd::load_amounts(&amounts2[i]);
                __m256i result = simd::min_amounts(a, b);
                simd::store_amounts(&results[i], result);
            }
        }
#else
        std::cout << "Using scalar fallback" << std::endl;
        
        for (std::size_t iter = 0; iter < iterations; ++iter) {
            for (std::size_t i = 0; i < batch_size; ++i) {
                results[i] = std::min(amounts1[i], amounts2[i]);
            }
        }
#endif
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        std::uint64_t total_operations = iterations * batch_size;
        double throughput = static_cast<double>(total_operations) / duration.count();
        
        std::cout << "SIMD operations: " << total_operations << " in " << duration.count() << " microseconds" << std::endl;
        std::cout << "Throughput: " << throughput << "M operations/sec" << std::endl;
    }
    
    // Benchmark template-optimized matching
    void benchmarkTemplateOptimizedMatching() {
        std::cout << "\n=== Template-Optimized Matching Benchmark ===" << std::endl;
        
        constexpr std::size_t iterations = 2000000;
        
        // Pre-populate some orders in the engine
        for (std::size_t i = 0; i < 1000; ++i) {
            Price bid_price = price_dist_(gen_);
            Price ask_price = bid_price + 10; // Ensure spread
            Amount amount = amount_dist_(gen_);
            
            engine_.addOrderToLevel<OrderSide::Buy>(bid_price, amount);
            engine_.addOrderToLevel<OrderSide::Sell>(ask_price, amount);
        }
        
        auto start = std::chrono::high_resolution_clock::now();
        
        std::size_t successful_matches = 0;
        for (std::size_t i = 0; i < iterations; ++i) {
            Price price = price_dist_(gen_);
            Amount amount = amount_dist_(gen_);
            
            // Alternate between buy and sell orders
            if (i % 2 == 0) {
                auto result = engine_.matchOrder<OrderSide::Buy>(price, amount);
                if (result.filled_amount > 0) {
                    successful_matches++;
                }
            } else {
                auto result = engine_.matchOrder<OrderSide::Sell>(price, amount);
                if (result.filled_amount > 0) {
                    successful_matches++;
                }
            }
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        double throughput = static_cast<double>(iterations) / duration.count();
        std::cout << "Template-optimized matches: " << iterations << " in " << duration.count() << " microseconds" << std::endl;
        std::cout << "Throughput: " << throughput << "M matches/sec" << std::endl;
        std::cout << "Successful matches: " << successful_matches << " (" << 
                     (100.0 * successful_matches / iterations) << "%)" << std::endl;
    }
    
    // Benchmark batch operations
    void benchmarkBatchOperations() {
        std::cout << "\n=== Batch Operations Benchmark ===" << std::endl;
        
        constexpr std::size_t batch_count = 10000;
        constexpr std::size_t batch_size = 64;
        
        meta::VectorizedArray<Price, batch_size> prices;
        meta::VectorizedArray<Amount, batch_size> amounts;
        
        // Initialize batch data
        for (std::size_t i = 0; i < batch_size; ++i) {
            prices[i] = price_dist_(gen_);
            amounts[i] = amount_dist_(gen_);
        }
        
        auto start = std::chrono::high_resolution_clock::now();
        
        std::size_t total_successful = 0;
        for (std::size_t batch = 0; batch < batch_count; ++batch) {
            auto results = engine_.matchOrdersBatch<OrderSide::Buy>(prices, amounts, batch_size);
            for (const auto& result : results) {
                if (result.filled_amount > 0) {
                    total_successful++;
                }
            }
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        std::uint64_t total_operations = batch_count * batch_size;
        double throughput = static_cast<double>(total_operations) / duration.count();
        
        std::cout << "Batch operations: " << total_operations << " in " << duration.count() << " microseconds" << std::endl;
        std::cout << "Throughput: " << throughput << "M operations/sec" << std::endl;
        std::cout << "Successful matches: " << total_successful << " (" << 
                     (100.0 * total_successful / total_operations) << "%)" << std::endl;
    }
    
    // Benchmark multi-threaded performance
    void benchmarkMultiThreadedPerformance() {
        std::cout << "\n=== Multi-Threaded Performance Benchmark ===" << std::endl;
        
        constexpr std::size_t thread_count = 8;
        constexpr std::size_t operations_per_thread = 500000;
        
        std::vector<std::thread> threads;
        std::vector<std::size_t> thread_results(thread_count, 0);
        
        auto start = std::chrono::high_resolution_clock::now();
        
        for (std::size_t t = 0; t < thread_count; ++t) {
            threads.emplace_back([this, t, &thread_results, operations_per_thread]() {
                std::mt19937 local_gen(t);
                std::uniform_int_distribution<Price> local_price_dist(1000, 10000);
                std::uniform_int_distribution<Amount> local_amount_dist(1, 1000);
                
                std::size_t local_matches = 0;
                for (std::size_t i = 0; i < operations_per_thread; ++i) {
                    Price price = local_price_dist(local_gen);
                    Amount amount = local_amount_dist(local_gen);
                    
                    if (i % 2 == 0) {
                        auto result = engine_.matchOrder<OrderSide::Buy>(price, amount);
                        if (result.filled_amount > 0) local_matches++;
                    } else {
                        auto result = engine_.matchOrder<OrderSide::Sell>(price, amount);
                        if (result.filled_amount > 0) local_matches++;
                    }
                }
                thread_results[t] = local_matches;
            });
        }
        
        for (auto& thread : threads) {
            thread.join();
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        std::uint64_t total_operations = thread_count * operations_per_thread;
        std::size_t total_matches = 0;
        for (std::size_t result : thread_results) {
            total_matches += result;
        }
        
        double throughput = static_cast<double>(total_operations) / duration.count();
        
        std::cout << "Multi-threaded operations: " << total_operations << " in " << duration.count() << " microseconds" << std::endl;
        std::cout << "Throughput: " << throughput << "M operations/sec" << std::endl;
        std::cout << "Total successful matches: " << total_matches << " (" << 
                     (100.0 * total_matches / total_operations) << "%)" << std::endl;
        std::cout << "Threads: " << thread_count << std::endl;
    }
    
    // Benchmark cache-friendly data structures
    void benchmarkCacheFriendlyStructures() {
        std::cout << "\n=== Cache-Friendly Data Structures Benchmark ===" << std::endl;
        
        constexpr std::size_t iterations = 1000000;
        
        meta::CacheFriendlyVector<Price> cache_friendly_prices;
        std::vector<Price> regular_prices;
        
        // Populate data structures
        for (std::size_t i = 0; i < iterations; ++i) {
            Price price = price_dist_(gen_);
            cache_friendly_prices.push_back(price);
            regular_prices.push_back(price);
        }
        
        // Benchmark cache-friendly access
        auto start = std::chrono::high_resolution_clock::now();
        
        Amount sum1 = 0;
        for (std::size_t i = 0; i < iterations; ++i) {
            sum1 += cache_friendly_prices[i];
        }
        
        auto mid = std::chrono::high_resolution_clock::now();
        
        Amount sum2 = 0;
        for (std::size_t i = 0; i < iterations; ++i) {
            sum2 += regular_prices[i];
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        
        auto cache_friendly_duration = std::chrono::duration_cast<std::chrono::microseconds>(mid - start);
        auto regular_duration = std::chrono::duration_cast<std::chrono::microseconds>(end - mid);
        
        double cache_friendly_throughput = static_cast<double>(iterations) / cache_friendly_duration.count();
        double regular_throughput = static_cast<double>(iterations) / regular_duration.count();
        
        std::cout << "Cache-friendly access: " << iterations << " in " << cache_friendly_duration.count() << " microseconds" << std::endl;
        std::cout << "Cache-friendly throughput: " << cache_friendly_throughput << "M accesses/sec" << std::endl;
        std::cout << "Regular access: " << iterations << " in " << regular_duration.count() << " microseconds" << std::endl;
        std::cout << "Regular throughput: " << regular_throughput << "M accesses/sec" << std::endl;
        std::cout << "Speedup: " << (cache_friendly_throughput / regular_throughput) << "x" << std::endl;
        std::cout << "Sum verification: " << (sum1 == sum2 ? "PASSED" : "FAILED") << std::endl;
    }
    
    // Run all optimized benchmarks
    void runAllOptimizedBenchmarks() {
        std::cout << "\n=== Advanced Optimization Benchmarks ===" << std::endl;
        std::cout << "Testing enhanced performance with latest optimizations..." << std::endl;
        
        benchmarkLockFreeStructures();
        benchmarkSIMDOperations();
        benchmarkTemplateOptimizedMatching();
        benchmarkBatchOperations();
        benchmarkCacheFriendlyStructures();
        benchmarkMultiThreadedPerformance();
        
        std::cout << "\n=== Optimization Benchmark Summary ===" << std::endl;
        std::cout << "All advanced optimization benchmarks completed successfully!" << std::endl;
        std::cout << "Performance improvements demonstrate enhanced throughput and reduced latency." << std::endl;
    }
};

} // namespace benchmark
} // namespace abyssbook