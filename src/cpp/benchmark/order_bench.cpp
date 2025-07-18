#include "benchmark.hpp"
#include "abyssbook/order_types.hpp"
#include "abyssbook/price_level.hpp"
#include <iostream>
#include <chrono>
#include <random>
#include <vector>

namespace abyssbook {

void OrderBenchmark::benchmarkOrderCreation() {
        std::cout << "\n=== Order Creation Benchmark ===" << std::endl;
        
        const int num_orders = 1000000;
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> price_dist(9000, 11000);
        std::uniform_int_distribution<> amount_dist(1, 1000);
        std::uniform_int_distribution<> side_dist(0, 1);
        
        auto start = std::chrono::high_resolution_clock::now();
        
        std::vector<CacheAlignedOrder> orders;
        orders.reserve(num_orders);
        
        for (int i = 0; i < num_orders; ++i) {
            orders.emplace_back(
                price_dist(gen),
                amount_dist(gen),
                i,
                static_cast<OrderSide>(side_dist(gen)),
                OrderType::Limit
            );
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        double orders_per_second = (num_orders * 1000000.0) / duration.count();
        std::cout << "Created " << num_orders << " orders in " << duration.count() 
                  << " microseconds" << std::endl;
        std::cout << "Throughput: " << orders_per_second << " orders/sec" << std::endl;
        std::cout << "Average latency: " << (duration.count() / (double)num_orders) 
                  << " microseconds per order" << std::endl;
    }
    
void OrderBenchmark::benchmarkAdvancedOrderCreation() {
        std::cout << "\n=== Advanced Order Creation Benchmark ===" << std::endl;
        
        const int num_orders = 100000;
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> price_dist(9000, 11000);
        std::uniform_int_distribution<> amount_dist(1, 1000);
        std::uniform_int_distribution<> type_dist(0, 5); // Basic types only for benchmark
        
        auto start = std::chrono::high_resolution_clock::now();
        
        std::vector<CacheAlignedOrder> orders;
        orders.reserve(num_orders);
        
        for (int i = 0; i < num_orders; ++i) {
            OrderType type = static_cast<OrderType>(type_dist(gen));
            switch (type) {
                case OrderType::Limit:
                    orders.push_back(OrderFactory::createLimit(price_dist(gen), amount_dist(gen), i, OrderSide::Buy));
                    break;
                case OrderType::Market:
                    orders.push_back(OrderFactory::createMarket(amount_dist(gen), i, OrderSide::Buy));
                    break;
                case OrderType::IOC:
                    orders.push_back(OrderFactory::createIOC(price_dist(gen), amount_dist(gen), i, OrderSide::Buy));
                    break;
                case OrderType::FOK:
                    orders.push_back(OrderFactory::createFOK(price_dist(gen), amount_dist(gen), i, OrderSide::Buy));
                    break;
                case OrderType::PostOnly:
                    orders.push_back(OrderFactory::createPostOnly(price_dist(gen), amount_dist(gen), i, OrderSide::Buy));
                    break;
                case OrderType::Iceberg:
                    orders.push_back(OrderFactory::createIceberg(price_dist(gen), amount_dist(gen), amount_dist(gen)/4, i, OrderSide::Buy));
                    break;
                default:
                    orders.push_back(OrderFactory::createLimit(price_dist(gen), amount_dist(gen), i, OrderSide::Buy));
                    break;
            }
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        double orders_per_second = (num_orders * 1000000.0) / duration.count();
        std::cout << "Created " << num_orders << " advanced orders in " << duration.count() 
                  << " microseconds" << std::endl;
        std::cout << "Throughput: " << orders_per_second << " orders/sec" << std::endl;
    }
    
void OrderBenchmark::benchmarkOrderCopy() {
        std::cout << "\n=== Order Copy Benchmark ===" << std::endl;
        
        const int num_copies = 100000;
        auto original = OrderFactory::createTWAP(1000, 500, 1, OrderSide::Buy, 5, 60);
        
        auto start = std::chrono::high_resolution_clock::now();
        
        std::vector<CacheAlignedOrder> copies;
        copies.reserve(num_copies);
        
        for (int i = 0; i < num_copies; ++i) {
            copies.push_back(original); // Copy constructor
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        double copies_per_second = (num_copies * 1000000.0) / duration.count();
        std::cout << "Copied " << num_copies << " complex orders in " << duration.count() 
                  << " microseconds" << std::endl;
        std::cout << "Throughput: " << copies_per_second << " copies/sec" << std::endl;
    }

void PriceLevelBenchmark::benchmarkPriceLevelUpdates() {
        std::cout << "\n=== Price Level Update Benchmark ===" << std::endl;
        
        PriceLevelMap levels;
        const int num_updates = 1000000;
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> price_dist(9000, 11000);
        std::uniform_int_distribution<> amount_dist(1, 1000);
        std::uniform_int_distribution<> delta_dist(-500, 500);
        
        auto start = std::chrono::high_resolution_clock::now();
        
        for (int i = 0; i < num_updates; ++i) {
            levels.updateLevel(price_dist(gen), delta_dist(gen), (i % 100 == 0) ? 1 : 0);
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        double updates_per_second = (num_updates * 1000000.0) / duration.count();
        std::cout << "Processed " << num_updates << " price level updates in " << duration.count() 
                  << " microseconds" << std::endl;
        std::cout << "Throughput: " << updates_per_second << " updates/sec" << std::endl;
        std::cout << "Final level count: " << levels.getLevelCount() << std::endl;
    }
    
void PriceLevelBenchmark::benchmarkBatchUpdates() {
        std::cout << "\n=== Batch Price Level Update Benchmark ===" << std::endl;
        
        PriceLevelMap levels;
        const int num_batches = 10000;
        const int batch_size = 100;
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> price_dist(9000, 11000);
        std::uniform_int_distribution<> amount_dist(1, 1000);
        
        auto start = std::chrono::high_resolution_clock::now();
        
        for (int b = 0; b < num_batches; ++b) {
            std::vector<PriceLevelUpdate> updates;
            updates.reserve(batch_size);
            
            for (int i = 0; i < batch_size; ++i) {
                updates.emplace_back(price_dist(gen), amount_dist(gen), 1);
            }
            
            levels.updateLevels(updates);
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        double total_updates = num_batches * batch_size;
        double updates_per_second = (total_updates * 1000000.0) / duration.count();
        std::cout << "Processed " << total_updates << " batch updates in " << duration.count() 
                  << " microseconds" << std::endl;
        std::cout << "Throughput: " << updates_per_second << " updates/sec" << std::endl;
        std::cout << "Batch throughput: " << (num_batches * 1000000.0) / duration.count() << " batches/sec" << std::endl;
    }
    
void PriceLevelBenchmark::benchmarkMarketDepth() {
        std::cout << "\n=== Market Depth Calculation Benchmark ===" << std::endl;
        
        PriceLevelAggregator aggregator;
        const int num_orders = 100000;
        const int num_queries = 10000;
        
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> price_dist(9000, 11000);
        std::uniform_int_distribution<> amount_dist(1, 1000);
        std::uniform_int_distribution<> side_dist(0, 1);
        
        // Populate with orders
        for (int i = 0; i < num_orders; ++i) {
            aggregator.addOrder(
                price_dist(gen),
                amount_dist(gen),
                static_cast<OrderSide>(side_dist(gen))
            );
        }
        
        auto start = std::chrono::high_resolution_clock::now();
        
        for (int i = 0; i < num_queries; ++i) {
            auto depth = aggregator.getMarketDepth(20); // Top 20 levels
            volatile auto bid_count = depth.bids.size();
            volatile auto ask_count = depth.asks.size();
            (void)bid_count; (void)ask_count; // Prevent optimization
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        
        double queries_per_second = (num_queries * 1000000.0) / duration.count();
        std::cout << "Calculated market depth " << num_queries << " times in " << duration.count() 
                  << " microseconds" << std::endl;
        std::cout << "Throughput: " << queries_per_second << " queries/sec" << std::endl;
    }

} // namespace abyssbook