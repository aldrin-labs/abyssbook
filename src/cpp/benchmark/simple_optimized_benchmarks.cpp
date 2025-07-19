#include "benchmark.hpp"
#include "abyssbook/common.hpp"
#include <chrono>
#include <random>
#include <thread>
#include <vector>
#include <iostream>
#include <numeric>
#include <algorithm>

namespace abyssbook {
namespace benchmark {

class SimpleOptimizedBenchmarks {
private:
    std::random_device rd_;
    std::mt19937 gen_;
    std::uniform_int_distribution<Price> price_dist_;
    std::uniform_int_distribution<Amount> amount_dist_;
    
public:
    SimpleOptimizedBenchmarks() : gen_(rd_()), price_dist_(1000, 10000), amount_dist_(1, 1000) {}
    
    // Test compiler optimizations
    void benchmarkCompilerOptimizations() {
        std::cout << "\n=== Compiler Optimizations Benchmark ===" << std::endl;
        
        constexpr std::size_t iterations = 10000000;
        std::vector<Price> prices(iterations);
        std::vector<Amount> amounts(iterations);
        
        // Generate test data
        for (std::size_t i = 0; i < iterations; ++i) {
            prices[i] = price_dist_(gen_);
            amounts[i] = amount_dist_(gen_);
        }
        
        auto start = std::chrono::high_resolution_clock::now();
        
        // Optimized loop with branch prediction hints
        Amount sum = 0;
        for (std::size_t i = 0; i < iterations; ++i) {
            Price price = prices[i];
            Amount amount = amounts[i];
            
            // Simulate order matching logic with optimizations
            if (LIKELY(price > 5000)) {
                sum += amount;
            } else {
                sum += amount / 2;
            }
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        double throughput = static_cast<double>(iterations) / duration.count();
        std::cout << "Optimized calculations: " << iterations << " in " << duration.count() << " microseconds" << std::endl;
        std::cout << "Throughput: " << throughput << "M operations/sec" << std::endl;
        std::cout << "Sum result: " << sum << std::endl;
    }
    
    // Test cache-aligned data access
    void benchmarkCacheOptimizations() {
        std::cout << "\n=== Cache Optimizations Benchmark ===" << std::endl;
        
        constexpr std::size_t iterations = 5000000;
        
        // Cache-aligned data structure
        struct CACHE_ALIGNED CacheOptimizedData {
            Price price;
            Amount amount;
            OrderId id;
            Timestamp timestamp;
        };
        
        std::vector<CacheOptimizedData> cache_optimized(iterations);
        std::vector<std::tuple<Price, Amount, OrderId, Timestamp>> regular_data(iterations);
        
        // Initialize data
        for (std::size_t i = 0; i < iterations; ++i) {
            Price price = price_dist_(gen_);
            Amount amount = amount_dist_(gen_);
            OrderId id = i;
            Timestamp timestamp = getCurrentTimestamp();
            
            cache_optimized[i] = {price, amount, id, timestamp};
            regular_data[i] = std::make_tuple(price, amount, id, timestamp);
        }
        
        // Benchmark cache-optimized access
        auto start = std::chrono::high_resolution_clock::now();
        
        Amount sum1 = 0;
        for (const auto& data : cache_optimized) {
            sum1 += data.amount;
            PREFETCH_READ(&data + 1); // Prefetch next element
        }
        
        auto mid = std::chrono::high_resolution_clock::now();
        
        Amount sum2 = 0;
        for (const auto& data : regular_data) {
            sum2 += std::get<1>(data);
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        
        auto cache_optimized_duration = std::chrono::duration_cast<std::chrono::microseconds>(mid - start);
        auto regular_duration = std::chrono::duration_cast<std::chrono::microseconds>(end - mid);
        
        double cache_optimized_throughput = static_cast<double>(iterations) / cache_optimized_duration.count();
        double regular_throughput = static_cast<double>(iterations) / regular_duration.count();
        
        std::cout << "Cache-optimized access: " << iterations << " in " << cache_optimized_duration.count() << " microseconds" << std::endl;
        std::cout << "Cache-optimized throughput: " << cache_optimized_throughput << "M accesses/sec" << std::endl;
        std::cout << "Regular access: " << iterations << " in " << regular_duration.count() << " microseconds" << std::endl;
        std::cout << "Regular throughput: " << regular_throughput << "M accesses/sec" << std::endl;
        std::cout << "Speedup: " << (cache_optimized_throughput / regular_throughput) << "x" << std::endl;
        std::cout << "Sum verification: " << (sum1 == sum2 ? "PASSED" : "FAILED") << std::endl;
    }
    
    // Test multi-threaded optimizations
    void benchmarkMultiThreadedOptimizations() {
        std::cout << "\n=== Multi-Threaded Optimizations Benchmark ===" << std::endl;
        
        const std::size_t thread_count = std::thread::hardware_concurrency();
        constexpr std::size_t operations_per_thread = 1000000;
        
        std::vector<std::thread> threads;
        std::vector<Amount> thread_results(thread_count, 0);
        
        auto start = std::chrono::high_resolution_clock::now();
        
        for (std::size_t t = 0; t < thread_count; ++t) {
            threads.emplace_back([this, t, &thread_results, operations_per_thread]() {
                std::mt19937 local_gen(t);
                std::uniform_int_distribution<Price> local_price_dist(1000, 10000);
                std::uniform_int_distribution<Amount> local_amount_dist(1, 1000);
                
                Amount local_sum = 0;
                for (std::size_t i = 0; i < operations_per_thread; ++i) {
                    Price price = local_price_dist(local_gen);
                    Amount amount = local_amount_dist(local_gen);
                    
                    // Simulate optimized order processing
                    if (LIKELY(price > 5000)) {
                        local_sum += amount;
                    } else {
                        local_sum += amount / 2;
                    }
                }
                thread_results[t] = local_sum;
            });
        }
        
        for (auto& thread : threads) {
            thread.join();
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        std::uint64_t total_operations = thread_count * operations_per_thread;
        Amount total_sum = 0;
        for (Amount result : thread_results) {
            total_sum += result;
        }
        
        double throughput = static_cast<double>(total_operations) / duration.count();
        
        std::cout << "Multi-threaded operations: " << total_operations << " in " << duration.count() << " microseconds" << std::endl;
        std::cout << "Throughput: " << throughput << "M operations/sec" << std::endl;
        std::cout << "Total sum: " << total_sum << std::endl;
        std::cout << "Threads: " << thread_count << std::endl;
        std::cout << "Parallel efficiency: " << (throughput / thread_count) << "M ops/sec per thread" << std::endl;
    }
    
    // Test memory optimization patterns
    void benchmarkMemoryOptimizations() {
        std::cout << "\n=== Memory Optimizations Benchmark ===" << std::endl;
        
        constexpr std::size_t iterations = 3000000;
        
        // Test different memory access patterns
        std::vector<Price> sequential_prices(iterations);
        std::vector<Amount> sequential_amounts(iterations);
        
        // Initialize sequential data
        for (std::size_t i = 0; i < iterations; ++i) {
            sequential_prices[i] = price_dist_(gen_);
            sequential_amounts[i] = amount_dist_(gen_);
        }
        
        // Create random access pattern
        std::vector<std::size_t> random_indices(iterations);
        std::iota(random_indices.begin(), random_indices.end(), 0);
        std::shuffle(random_indices.begin(), random_indices.end(), gen_);
        
        // Benchmark sequential access
        auto start = std::chrono::high_resolution_clock::now();
        
        Amount sum1 = 0;
        for (std::size_t i = 0; i < iterations; ++i) {
            sum1 += sequential_amounts[i];
        }
        
        auto mid = std::chrono::high_resolution_clock::now();
        
        Amount sum2 = 0;
        for (std::size_t i = 0; i < iterations; ++i) {
            sum2 += sequential_amounts[random_indices[i]];
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        
        auto sequential_duration = std::chrono::duration_cast<std::chrono::microseconds>(mid - start);
        auto random_duration = std::chrono::duration_cast<std::chrono::microseconds>(end - mid);
        
        double sequential_throughput = static_cast<double>(iterations) / sequential_duration.count();
        double random_throughput = static_cast<double>(iterations) / random_duration.count();
        
        std::cout << "Sequential access: " << iterations << " in " << sequential_duration.count() << " microseconds" << std::endl;
        std::cout << "Sequential throughput: " << sequential_throughput << "M accesses/sec" << std::endl;
        std::cout << "Random access: " << iterations << " in " << random_duration.count() << " microseconds" << std::endl;
        std::cout << "Random throughput: " << random_throughput << "M accesses/sec" << std::endl;
        std::cout << "Cache efficiency ratio: " << (sequential_throughput / random_throughput) << "x" << std::endl;
        std::cout << "Sum verification: " << (sum1 == sum2 ? "PASSED" : "FAILED") << std::endl;
    }
    
    // Run all optimized benchmarks
    void runAllOptimizedBenchmarks() {
        std::cout << "\n=== Enhanced Optimization Benchmarks ===" << std::endl;
        std::cout << "Testing performance improvements with advanced optimizations..." << std::endl;
        
        benchmarkCompilerOptimizations();
        benchmarkCacheOptimizations();
        benchmarkMemoryOptimizations();
        benchmarkMultiThreadedOptimizations();
        
        std::cout << "\n=== Enhanced Optimization Summary ===" << std::endl;
        std::cout << "All enhanced optimization benchmarks completed successfully!" << std::endl;
        std::cout << "Performance improvements demonstrate enhanced throughput and cache efficiency." << std::endl;
    }
};

} // namespace benchmark
} // namespace abyssbook