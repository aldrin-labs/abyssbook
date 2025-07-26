#include "../test_framework.hpp"
#include "../../include/abyssbook/lockfree_structures.hpp"
#include <thread>
#include <vector>
#include <chrono>
#include <random>
#include <future>
#include <atomic>

using namespace abyssbook;
using namespace abyssbook::lockfree;

namespace {

class LockFreeConcurrencyTests {
public:
    // Test concurrent insertions into LockFreeHashMap
    static bool testHashMapConcurrentInsert() {
        constexpr std::size_t NUM_THREADS = 8;
        constexpr std::size_t OPERATIONS_PER_THREAD = 10000;
        
        LockFreeHashMap<1024> hashmap;
        std::vector<std::thread> threads;
        std::atomic<std::size_t> successful_operations{0};
        std::atomic<bool> start_flag{false};
        
        // Barrier to synchronize start
        std::atomic<std::size_t> ready_threads{0};
        
        for (std::size_t i = 0; i < NUM_THREADS; ++i) {
            threads.emplace_back([&, thread_id = i]() {
                ready_threads.fetch_add(1, std::memory_order_acq_rel);
                
                // Wait for all threads to be ready
                while (!start_flag.load(std::memory_order_acquire)) {
                    std::this_thread::yield();
                }
                
                std::mt19937 rng(thread_id * 12345);
                std::uniform_int_distribution<Price> price_dist(1000, 9999);
                std::uniform_int_distribution<Amount> amount_dist(1, 1000);
                
                std::size_t local_success = 0;
                
                for (std::size_t op = 0; op < OPERATIONS_PER_THREAD; ++op) {
                    Price price = price_dist(rng);
                    Amount amount = amount_dist(rng);
                    
                    if (hashmap.insertOrUpdate(price, static_cast<std::int64_t>(amount), 1)) {
                        ++local_success;
                    }
                }
                
                successful_operations.fetch_add(local_success, std::memory_order_acq_rel);
            });
        }
        
        // Wait for all threads to be ready
        while (ready_threads.load(std::memory_order_acquire) < NUM_THREADS) {
            std::this_thread::yield();
        }
        
        // Start all threads simultaneously
        start_flag.store(true, std::memory_order_release);
        
        for (auto& thread : threads) {
            thread.join();
        }
        
        return successful_operations.load() > NUM_THREADS * OPERATIONS_PER_THREAD * 0.95;
    }
    
    // Test concurrent reads and writes on SkipList
    static bool testSkipListReaderWriter() {
        constexpr std::size_t NUM_WRITERS = 4;
        constexpr std::size_t NUM_READERS = 4;
        constexpr std::size_t OPERATIONS_PER_THREAD = 5000;
        constexpr std::chrono::seconds TEST_DURATION{10};
        
        LockFreeSkipList<16> skiplist;
        std::atomic<bool> stop_flag{false};
        std::atomic<std::size_t> write_operations{0};
        std::atomic<std::size_t> read_operations{0};
        std::atomic<std::size_t> read_hits{0};
        
        std::vector<std::thread> threads;
        
        // Writer threads
        for (std::size_t i = 0; i < NUM_WRITERS; ++i) {
            threads.emplace_back([&, thread_id = i]() {
                std::mt19937 rng(thread_id * 54321);
                std::uniform_int_distribution<Price> price_dist(100, 999);
                std::uniform_int_distribution<Amount> amount_dist(1, 500);
                
                std::size_t ops = 0;
                while (!stop_flag.load(std::memory_order_acquire) && ops < OPERATIONS_PER_THREAD) {
                    Price price = price_dist(rng);
                    Amount amount = amount_dist(rng);
                    
                    if (skiplist.insertOrUpdate(price, static_cast<std::int64_t>(amount), 1)) {
                        ++ops;
                    }
                }
                
                write_operations.fetch_add(ops, std::memory_order_acq_rel);
            });
        }
        
        // Reader threads
        for (std::size_t i = 0; i < NUM_READERS; ++i) {
            threads.emplace_back([&, thread_id = i + NUM_WRITERS]() {
                std::mt19937 rng(thread_id * 98765);
                std::uniform_int_distribution<Price> price_dist(100, 999);
                
                std::size_t ops = 0;
                std::size_t hits = 0;
                
                while (!stop_flag.load(std::memory_order_acquire) && ops < OPERATIONS_PER_THREAD) {
                    Price price = price_dist(rng);
                    
                    if (skiplist.find(price).has_value()) {
                        ++hits;
                    }
                    ++ops;
                }
                
                read_operations.fetch_add(ops, std::memory_order_acq_rel);
                read_hits.fetch_add(hits, std::memory_order_acq_rel);
            });
        }
        
        // Let test run for duration
        std::this_thread::sleep_for(TEST_DURATION);
        stop_flag.store(true, std::memory_order_release);
        
        for (auto& thread : threads) {
            thread.join();
        }
        
        // Verify reasonable operation counts
        return write_operations.load() > 1000 && read_operations.load() > 1000;
    }
    
    // Test memory consistency under stress
    static bool testMemoryConsistency() {
        constexpr std::size_t NUM_THREADS = 16;
        constexpr std::size_t PRICE_RANGE = 100;
        constexpr std::chrono::seconds TEST_DURATION{5};
        
        LockFreeHashMap<512> hashmap;
        std::atomic<bool> stop_flag{false};
        std::atomic<std::size_t> inconsistencies{0};
        
        // Pre-populate with known values
        for (Price p = 1; p <= PRICE_RANGE; ++p) {
            hashmap.insertOrUpdate(p, 100, 1); // Each price starts with volume 100
        }
        
        std::vector<std::thread> threads;
        
        for (std::size_t i = 0; i < NUM_THREADS; ++i) {
            threads.emplace_back([&, thread_id = i]() {
                std::mt19937 rng(thread_id * 11111);
                std::uniform_int_distribution<Price> price_dist(1, PRICE_RANGE);
                std::uniform_int_distribution<int> delta_dist(-10, 10);
                
                while (!stop_flag.load(std::memory_order_acquire)) {
                    Price price = price_dist(rng);
                    int delta = delta_dist(rng);
                    
                    // Update price level
                    hashmap.insertOrUpdate(price, delta, 0);
                    
                    // Immediately read back and verify consistency
                    auto result = hashmap.find(price);
                    if (result.has_value()) {
                        auto [volume, count] = result.value();
                        // Volume should never be negative due to our implementation
                        if (volume > 1000000) { // Unreasonably large volume indicates inconsistency
                            inconsistencies.fetch_add(1, std::memory_order_acq_rel);
                        }
                    }
                    
                    std::this_thread::yield();
                }
            });
        }
        
        std::this_thread::sleep_for(TEST_DURATION);
        stop_flag.store(true, std::memory_order_release);
        
        for (auto& thread : threads) {
            thread.join();
        }
        
        return inconsistencies.load() == 0;
    }
    
    // Test race conditions in best price updates
    static bool testBestPriceRaceConditions() {
        constexpr std::size_t NUM_THREADS = 8;
        constexpr std::size_t OPERATIONS_PER_THREAD = 1000;
        
        LockFreeSkipList<16> skiplist;
        std::vector<std::thread> threads;
        std::atomic<std::size_t> price_inconsistencies{0};
        
        for (std::size_t i = 0; i < NUM_THREADS; ++i) {
            threads.emplace_back([&, thread_id = i]() {
                std::mt19937 rng(thread_id * 22222);
                std::uniform_int_distribution<Price> price_dist(1000, 2000);
                std::uniform_int_distribution<Amount> amount_dist(1, 100);
                
                for (std::size_t op = 0; op < OPERATIONS_PER_THREAD; ++op) {
                    Price price = price_dist(rng);
                    Amount amount = amount_dist(rng);
                    
                    // Insert order
                    skiplist.insertOrUpdate(price, static_cast<std::int64_t>(amount), 1);
                    
                    // Check best prices consistency
                    auto best_bid = skiplist.getBestPrice(true);
                    auto best_ask = skiplist.getBestPrice(false);
                    
                    // If both exist, bid should be <= ask
                    if (best_bid.has_value() && best_ask.has_value()) {
                        if (best_bid.value() > best_ask.value()) {
                            price_inconsistencies.fetch_add(1, std::memory_order_acq_rel);
                        }
                    }
                }
            });
        }
        
        for (auto& thread : threads) {
            thread.join();
        }
        
        return price_inconsistencies.load() == 0;
    }
    
    // Test high-frequency trading simulation
    static bool testHFTSimulation() {
        constexpr std::size_t NUM_TRADERS = 12;
        constexpr std::chrono::seconds SIMULATION_TIME{8};
        
        LockFreeSkipList<16> bid_book;
        LockFreeSkipList<16> ask_book;
        
        std::atomic<bool> stop_flag{false};
        std::atomic<std::size_t> total_trades{0};
        std::atomic<std::size_t> arbitrage_opportunities{0};
        
        std::vector<std::thread> traders;
        
        for (std::size_t i = 0; i < NUM_TRADERS; ++i) {
            traders.emplace_back([&, trader_id = i]() {
                std::mt19937 rng(trader_id * 33333);
                std::uniform_real_distribution<double> action_dist(0.0, 1.0);
                std::uniform_int_distribution<Price> price_dist(9500, 10500);
                std::uniform_int_distribution<Amount> amount_dist(1, 50);
                
                std::size_t local_trades = 0;
                std::size_t local_arbitrage = 0;
                
                while (!stop_flag.load(std::memory_order_acquire)) {
                    double action = action_dist(rng);
                    Price price = price_dist(rng);
                    Amount amount = amount_dist(rng);
                    
                    if (action < 0.4) {
                        // Place bid
                        bid_book.insertOrUpdate(price, static_cast<std::int64_t>(amount), 1);
                        ++local_trades;
                    } else if (action < 0.8) {
                        // Place ask
                        ask_book.insertOrUpdate(price, static_cast<std::int64_t>(amount), 1);
                        ++local_trades;
                    } else {
                        // Check for arbitrage (best bid > best ask)
                        auto best_bid = bid_book.getBestPrice(true);
                        auto best_ask = ask_book.getBestPrice(false);
                        
                        if (best_bid.has_value() && best_ask.has_value() &&
                            best_bid.value() > best_ask.value()) {
                            ++local_arbitrage;
                        }
                    }
                    
                    // High-frequency: minimal delay
                    if (local_trades % 100 == 0) {
                        std::this_thread::yield();
                    }
                }
                
                total_trades.fetch_add(local_trades, std::memory_order_acq_rel);
                arbitrage_opportunities.fetch_add(local_arbitrage, std::memory_order_acq_rel);
            });
        }
        
        std::this_thread::sleep_for(SIMULATION_TIME);
        stop_flag.store(true, std::memory_order_release);
        
        for (auto& trader : traders) {
            trader.join();
        }
        
        // Verify significant activity occurred
        return total_trades.load() > 10000 && arbitrage_opportunities.load() < 100;
    }
};

} // anonymous namespace

// Test registration
TEST_CASE("Lock-free HashMap Concurrent Insert") {
    REQUIRE(LockFreeConcurrencyTests::testHashMapConcurrentInsert());
}

TEST_CASE("Lock-free SkipList Reader-Writer") {
    REQUIRE(LockFreeConcurrencyTests::testSkipListReaderWriter());
}

TEST_CASE("Lock-free Memory Consistency") {
    REQUIRE(LockFreeConcurrencyTests::testMemoryConsistency());
}

TEST_CASE("Lock-free Best Price Race Conditions") {
    REQUIRE(LockFreeConcurrencyTests::testBestPriceRaceConditions());
}

TEST_CASE("Lock-free HFT Simulation") {
    REQUIRE(LockFreeConcurrencyTests::testHFTSimulation());
}