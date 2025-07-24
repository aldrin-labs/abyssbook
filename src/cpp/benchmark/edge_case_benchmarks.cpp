#include "../benchmark.hpp"
#include "../../include/abyssbook/orderbook.hpp"
#include "../../include/abyssbook/order_types.hpp"
#include <random>
#include <vector>
#include <chrono>
#include <algorithm>
#include <memory>

using namespace abyssbook;

namespace edge_case_benchmarks {

// Edge case: Memory fragmentation under high churn
static void BenchmarkMemoryFragmentation(benchmark::State& state) {
    OrderBook orderbook;
    std::mt19937 rng(42);
    std::uniform_int_distribution<OrderId> id_dist(1, 1000000);
    std::uniform_int_distribution<Price> price_dist(9900, 10100);
    std::uniform_int_distribution<Amount> amount_dist(1, 100);
    std::uniform_real_distribution<> action_dist(0.0, 1.0);
    
    // Pre-fragment memory with many small allocations
    std::vector<OrderId> active_orders;
    for (int i = 0; i < 1000; ++i) {
        OrderId id = id_dist(rng);
        Price price = price_dist(rng);
        Amount amount = amount_dist(rng);
        bool is_buy = rng() % 2;
        
        if (orderbook.placeLimitOrder(id, is_buy, amount, price)) {
            active_orders.push_back(id);
        }
    }
    
    // Cancel half to create fragmentation
    for (size_t i = 0; i < active_orders.size() / 2; ++i) {
        orderbook.cancelOrder(active_orders[i]);
    }
    
    for (auto _ : state) {
        double action = action_dist(rng);
        
        if (action < 0.6) {  // 60% new orders
            OrderId id = id_dist(rng);
            Price price = price_dist(rng);
            Amount amount = amount_dist(rng);
            bool is_buy = rng() % 2;
            
            orderbook.placeLimitOrder(id, is_buy, amount, price);
        } else {  // 40% cancellations
            if (!active_orders.empty()) {
                size_t idx = rng() % active_orders.size();
                orderbook.cancelOrder(active_orders[idx]);
                active_orders.erase(active_orders.begin() + idx);
            }
        }
    }
    
    state.SetItemsProcessed(state.iterations());
}

// Edge case: Cache miss patterns with scattered price levels
static void BenchmarkCacheMissPatterns(benchmark::State& state) {
    OrderBook orderbook;
    std::mt19937 rng(123);
    
    // Create widely scattered price levels to force cache misses
    std::vector<Price> scattered_prices;
    for (int i = 0; i < 1000; ++i) {
        scattered_prices.push_back(1000 + i * 100);  // Prices: 1000, 1100, 1200, ...
    }
    std::shuffle(scattered_prices.begin(), scattered_prices.end(), rng);
    
    std::uniform_int_distribution<OrderId> id_dist(1, 1000000);
    std::uniform_int_distribution<Amount> amount_dist(1, 50);
    
    for (auto _ : state) {
        // Access prices in pseudo-random order to maximize cache misses
        Price price = scattered_prices[rng() % scattered_prices.size()];
        OrderId id = id_dist(rng);
        Amount amount = amount_dist(rng);
        bool is_buy = rng() % 2;
        
        benchmark::DoNotOptimize(orderbook.placeLimitOrder(id, is_buy, amount, price));
    }
    
    state.SetItemsProcessed(state.iterations());
}

// Edge case: Extreme price volatility simulation
static void BenchmarkExtremeVolatility(benchmark::State& state) {
    OrderBook orderbook;
    std::mt19937 rng(456);
    std::uniform_int_distribution<OrderId> id_dist(1, 1000000);
    std::uniform_int_distribution<Amount> amount_dist(1, 200);
    
    Price base_price = 10000;
    Price current_price = base_price;
    
    for (auto _ : state) {
        // Simulate extreme price volatility (±50% swings)
        int volatility = (rng() % 200) - 100;  // -100 to +99
        current_price = base_price + (base_price * volatility / 200);
        
        // Clamp to reasonable bounds
        current_price = std::max(Price(1000), std::min(Price(50000), current_price));
        
        OrderId id = id_dist(rng);
        Amount amount = amount_dist(rng);
        bool is_buy = rng() % 2;
        
        benchmark::DoNotOptimize(orderbook.placeLimitOrder(id, is_buy, amount, current_price));
        
        // Occasionally place market orders during volatility
        if (rng() % 10 == 0) {
            OrderId market_id = id_dist(rng);
            Amount market_amount = amount_dist(rng);
            benchmark::DoNotOptimize(orderbook.placeMarketOrder(market_id, !is_buy, market_amount));
        }
    }
    
    state.SetItemsProcessed(state.iterations());
}

// Combination test: Mixed order types under stress
static void BenchmarkMixedOrderCombinations(benchmark::State& state) {
    OrderBook orderbook;
    std::mt19937 rng(789);
    std::uniform_int_distribution<OrderId> id_dist(1, 1000000);
    std::uniform_int_distribution<Price> price_dist(9500, 10500);
    std::uniform_int_distribution<Amount> amount_dist(1, 500);
    std::uniform_real_distribution<> type_dist(0.0, 1.0);
    
    for (auto _ : state) {
        double order_type = type_dist(rng);
        OrderId id = id_dist(rng);
        Price price = price_dist(rng);
        Amount amount = amount_dist(rng);
        bool is_buy = rng() % 2;
        
        if (order_type < 0.4) {
            // 40% limit orders
            benchmark::DoNotOptimize(orderbook.placeLimitOrder(id, is_buy, amount, price));
        } else if (order_type < 0.6) {
            // 20% market orders
            benchmark::DoNotOptimize(orderbook.placeMarketOrder(id, is_buy, amount));
        } else if (order_type < 0.75) {
            // 15% stop orders
            Price stop_price = is_buy ? price + 50 : price - 50;
            benchmark::DoNotOptimize(orderbook.placeStopOrder(id, is_buy, amount, stop_price));
        } else if (order_type < 0.9) {
            // 15% iceberg orders
            Amount display_amount = amount / 3;
            if (display_amount > 0) {
                benchmark::DoNotOptimize(orderbook.icebergOrder(id, is_buy, amount, price, display_amount));
            }
        } else {
            // 10% cancellations
            OrderId cancel_id = id_dist(rng);
            benchmark::DoNotOptimize(orderbook.cancelOrder(cancel_id));
        }
    }
    
    state.SetItemsProcessed(state.iterations());
}

// Edge case: Pathological order sequences
static void BenchmarkPathologicalSequences(benchmark::State& state) {
    OrderBook orderbook;
    std::mt19937 rng(101112);
    std::uniform_int_distribution<OrderId> id_dist(1, 1000000);
    
    for (auto _ : state) {
        OrderId id = id_dist(rng);
        
        // Pathological case 1: Immediate cancel after place
        if (state.iterations() % 3 == 0) {
            orderbook.placeLimitOrder(id, true, 100, 10000);
            benchmark::DoNotOptimize(orderbook.cancelOrder(id));
        }
        // Pathological case 2: Same price, alternating sides
        else if (state.iterations() % 3 == 1) {
            bool is_buy = (state.iterations() / 3) % 2 == 0;
            benchmark::DoNotOptimize(orderbook.placeLimitOrder(id, is_buy, 50, 10000));
        }
        // Pathological case 3: Micro-orders at same price
        else {
            benchmark::DoNotOptimize(orderbook.placeLimitOrder(id, true, 1, 10000));
        }
    }
    
    state.SetItemsProcessed(state.iterations());
}

// Edge case: Deep order book stress test
static void BenchmarkDeepOrderBook(benchmark::State& state) {
    OrderBook orderbook;
    std::mt19937 rng(131415);
    std::uniform_int_distribution<OrderId> id_dist(1, 10000000);
    std::uniform_int_distribution<Amount> amount_dist(1, 100);
    
    // Pre-populate with deep order book (1000 price levels each side)
    for (int i = 1; i <= 1000; ++i) {
        // Buy side: 9000, 8999, 8998, ...
        orderbook.placeLimitOrder(id_dist(rng), true, amount_dist(rng), 9000 - i);
        // Sell side: 11000, 11001, 11002, ...
        orderbook.placeLimitOrder(id_dist(rng), false, amount_dist(rng), 11000 + i);
    }
    
    std::uniform_int_distribution<Price> buy_price_dist(8000, 8999);
    std::uniform_int_distribution<Price> sell_price_dist(11001, 12000);
    
    for (auto _ : state) {
        OrderId id = id_dist(rng);
        Amount amount = amount_dist(rng);
        
        if (rng() % 2) {
            // Add to buy side
            Price price = buy_price_dist(rng);
            benchmark::DoNotOptimize(orderbook.placeLimitOrder(id, true, amount, price));
        } else {
            // Add to sell side
            Price price = sell_price_dist(rng);
            benchmark::DoNotOptimize(orderbook.placeLimitOrder(id, false, amount, price));
        }
    }
    
    state.SetItemsProcessed(state.iterations());
}

// Combination test: Concurrent-style access patterns (single-threaded simulation)
static void BenchmarkConcurrentStyleAccess(benchmark::State& state) {
    OrderBook orderbook;
    std::mt19937 rng(161718);
    std::uniform_int_distribution<OrderId> id_dist(1, 1000000);
    std::uniform_int_distribution<Price> price_dist(9900, 10100);
    std::uniform_int_distribution<Amount> amount_dist(1, 200);
    
    // Simulate concurrent access patterns by interleaving operations
    std::vector<std::function<void()>> operations;
    
    for (auto _ : state) {
        // Add operations to queue (simulating concurrent threads)
        for (int i = 0; i < 10; ++i) {
            OrderId id = id_dist(rng);
            Price price = price_dist(rng);
            Amount amount = amount_dist(rng);
            bool is_buy = rng() % 2;
            
            operations.push_back([&orderbook, id, price, amount, is_buy]() {
                orderbook.placeLimitOrder(id, is_buy, amount, price);
            });
        }
        
        // Execute operations in pseudo-random order (simulating thread scheduling)
        std::shuffle(operations.begin(), operations.end(), rng);
        
        for (auto& op : operations) {
            benchmark::DoNotOptimize(op());
        }
        
        operations.clear();
    }
    
    state.SetItemsProcessed(state.iterations() * 10);
}

} // namespace edge_case_benchmarks

// Register benchmarks
BENCHMARK(edge_case_benchmarks::BenchmarkMemoryFragmentation)
    ->Range(1000, 100000)
    ->Unit(benchmark::kMicrosecond);

BENCHMARK(edge_case_benchmarks::BenchmarkCacheMissPatterns)
    ->Range(1000, 50000)
    ->Unit(benchmark::kMicrosecond);

BENCHMARK(edge_case_benchmarks::BenchmarkExtremeVolatility)
    ->Range(1000, 100000)
    ->Unit(benchmark::kMicrosecond);

BENCHMARK(edge_case_benchmarks::BenchmarkMixedOrderCombinations)
    ->Range(5000, 200000)
    ->Unit(benchmark::kMicrosecond);

BENCHMARK(edge_case_benchmarks::BenchmarkPathologicalSequences)
    ->Range(1000, 100000)
    ->Unit(benchmark::kMicrosecond);

BENCHMARK(edge_case_benchmarks::BenchmarkDeepOrderBook)
    ->Range(500, 50000)
    ->Unit(benchmark::kMicrosecond);

BENCHMARK(edge_case_benchmarks::BenchmarkConcurrentStyleAccess)
    ->Range(100, 10000)
    ->Unit(benchmark::kMicrosecond);