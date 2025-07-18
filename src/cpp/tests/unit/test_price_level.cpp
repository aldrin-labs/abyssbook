#include "abyssbook/price_level.hpp"
#include "../test_framework.hpp"
#include <iostream>
#include <cassert>
#include <chrono>

void test_price_level_basic() {
    using namespace abyssbook;
    
    PriceLevel level;
    assert(level.total_volume == 0);
    assert(level.order_count == 0);
    assert(level.isEmpty());
    
    level.addOrder(100);
    assert(level.total_volume == 100);
    assert(level.order_count == 1);
    assert(!level.isEmpty());
    
    level.addOrder(50);
    assert(level.total_volume == 150);
    assert(level.order_count == 2);
    
    level.removeOrder(50);
    assert(level.total_volume == 100);
    assert(level.order_count == 1);
    
    level.updateAmount(100, 200);
    assert(level.total_volume == 200);
}

void test_price_level_map() {
    using namespace abyssbook;
    
    PriceLevelMap levels;
    
    // Add some levels
    levels.updateLevel(1000, 100, 1);
    levels.updateLevel(1001, 150, 2);
    levels.updateLevel(999, 200, 1);
    
    // Test get level
    auto level = levels.getLevel(1000);
    assert(level.has_value());
    assert(level->total_volume == 100);
    assert(level->order_count == 1);
    
    // Test best prices
    auto best_bid = levels.getBestPrice(true);  // Highest price for bids
    assert(best_bid.has_value());
    assert(*best_bid == 1001);
    
    auto best_ask = levels.getBestPrice(false); // Lowest price for asks
    assert(best_ask.has_value());
    assert(*best_ask == 999);
    
    // Test sorted prices
    auto bid_prices = levels.getSortedPrices(true, 0);
    assert(bid_prices.size() == 3);
    assert(bid_prices[0] == 1001); // Highest first for bids
    assert(bid_prices[1] == 1000);
    assert(bid_prices[2] == 999);
    
    auto ask_prices = levels.getSortedPrices(false, 0);
    assert(ask_prices.size() == 3);
    assert(ask_prices[0] == 999);  // Lowest first for asks
    assert(ask_prices[1] == 1000);
    assert(ask_prices[2] == 1001);
}

void test_price_level_aggregator() {
    using namespace abyssbook;
    
    PriceLevelAggregator aggregator;
    
    // Add some orders
    aggregator.addOrder(1000, 100, OrderSide::Buy);
    aggregator.addOrder(1001, 150, OrderSide::Buy);
    aggregator.addOrder(1002, 200, OrderSide::Sell);
    aggregator.addOrder(1003, 250, OrderSide::Sell);
    
    // Test best bid/ask
    auto best_bid = aggregator.getBestBid();
    auto best_ask = aggregator.getBestAsk();
    
    assert(best_bid.has_value());
    assert(best_ask.has_value());
    assert(*best_bid == 1001);  // Highest bid
    assert(*best_ask == 1002);  // Lowest ask
    
    // Test spread and midpoint
    auto spread = aggregator.getSpread();
    auto midpoint = aggregator.getMidpoint();
    
    assert(spread.has_value());
    assert(midpoint.has_value());
    assert(*spread == 1);        // 1002 - 1001
    assert(*midpoint == 1001);   // (1001 + 1002) / 2 = 1001.5 -> 1001 (integer division)
    
    // Test market depth
    auto depth = aggregator.getMarketDepth(10);
    assert(depth.bids.size() == 2);
    assert(depth.asks.size() == 2);
    assert(depth.bids[0].price == 1001);
    assert(depth.bids[0].volume == 150);
    assert(depth.asks[0].price == 1002);
    assert(depth.asks[0].volume == 200);
}

void test_batch_price_level_updater() {
    using namespace abyssbook;
    
    PriceLevelMap levels;
    
    {
        BatchPriceLevelUpdater updater(levels);
        updater.addUpdate(1000, 100, 1);
        updater.addUpdate(1001, 150, 1);
        updater.addUpdate(1002, 200, 1);
        // Updates will be committed on destruction
    }
    
    // Verify updates were applied
    assert(levels.getLevelCount() == 3);
    
    auto level = levels.getLevel(1000);
    assert(level.has_value());
    assert(level->total_volume == 100);
}

void test_price_level_performance() {
    using namespace abyssbook;
    
    PriceLevelMap levels;
    const int num_updates = 100000;
    
    auto start = std::chrono::high_resolution_clock::now();
    
    for (int i = 0; i < num_updates; ++i) {
        levels.updateLevel(1000 + (i % 100), 100, 1);
    }
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
    
    double updates_per_second = (num_updates * 1000000.0) / duration.count();
    std::cout << "Price level updates: " << updates_per_second << " updates/sec";
    
    // Should be able to handle at least 1M updates per second
    assert(updates_per_second > 1000000);
}

int test_price_level_main() {
    std::cout << "Running C++ AbyssBook Price Level Tests\n" << std::endl;
    
    TestRunner::run_test("Price Level Basic", test_price_level_basic);
    TestRunner::run_test("Price Level Map", test_price_level_map);
    TestRunner::run_test("Price Level Aggregator", test_price_level_aggregator);
    TestRunner::run_test("Batch Price Level Updater", test_batch_price_level_updater);
    TestRunner::run_test("Price Level Performance", test_price_level_performance);
    
    TestRunner::print_summary();
    return TestRunner::get_exit_code();
}
