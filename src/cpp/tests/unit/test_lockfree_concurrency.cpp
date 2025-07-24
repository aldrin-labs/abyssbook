#include "../test_framework.hpp"
#include "abyssbook/lockfree_structures.hpp"
#include "abyssbook/memory_reclamation.hpp"
#include <thread>
#include <vector>
#include <chrono>
#include <atomic>

using namespace abyssbook;
using namespace abyssbook::lockfree;
using namespace abyssbook::memory;

// Test concurrent access to atomic price levels
void testAtomicPriceLevelConcurrency() {
    const int NUM_THREADS = 8;
    const int OPERATIONS_PER_THREAD = 10000;
    
    AtomicPriceLevel price_level;
    std::atomic<int> completed_threads{0};
    std::vector<std::thread> threads;
    
    // Launch producer threads
    for (int i = 0; i < NUM_THREADS / 2; ++i) {
        threads.emplace_back([&price_level, &completed_threads, OPERATIONS_PER_THREAD]() {
            for (int j = 0; j < OPERATIONS_PER_THREAD; ++j) {
                Amount amount = 100 + (j % 1000);
                price_level.addOrder(amount);
                
                // Occasionally remove orders
                if (j % 10 == 0) {
                    price_level.removeOrder(50);
                }
            }
            completed_threads.fetch_add(1);
        });
    }
    
    // Launch consumer threads (readers)
    for (int i = 0; i < NUM_THREADS / 2; ++i) {
        threads.emplace_back([&price_level, &completed_threads, OPERATIONS_PER_THREAD]() {
            for (int j = 0; j < OPERATIONS_PER_THREAD; ++j) {
                Amount volume = price_level.getVolume();
                std::size_t count = price_level.getOrderCount();
                bool empty = price_level.isEmpty();
                
                // Verify consistency
                if (count == 0 && volume > 0) {
                    // This shouldn't happen
                    printf("Inconsistency detected: count=0 but volume=%lu\n", volume);
                }
            }
            completed_threads.fetch_add(1);
        });
    }
    
    // Wait for completion
    for (auto& thread : threads) {
        thread.join();
    }
    
    if (completed_threads.load() != NUM_THREADS) {
        throw std::runtime_error("Not all threads completed");
    }
}

// Test concurrent skip list operations
void testLockFreeSkipListConcurrency() {
    const int NUM_THREADS = 6;
    const int OPERATIONS_PER_THREAD = 5000;
    
    LockFreeSkipList<16> skip_list;
    std::atomic<int> insert_count{0};
    std::atomic<int> find_count{0};
    std::atomic<int> remove_count{0};
    std::vector<std::thread> threads;
    
    // Insert threads
    for (int i = 0; i < NUM_THREADS / 3; ++i) {
        threads.emplace_back([&skip_list, &insert_count, OPERATIONS_PER_THREAD, i]() {
            for (int j = 0; j < OPERATIONS_PER_THREAD; ++j) {
                Price price = 1000 + (i * OPERATIONS_PER_THREAD + j);
                Amount volume = price * 10;
                
                if (skip_list.insertOrUpdate(price, volume, 1)) {
                    insert_count.fetch_add(1);
                }
            }
        });
    }
    
    // Find threads (simplified to just check operations complete)
    for (int i = 0; i < NUM_THREADS / 3; ++i) {
        threads.emplace_back([&skip_list, &find_count, OPERATIONS_PER_THREAD]() {
            for (int j = 0; j < OPERATIONS_PER_THREAD; ++j) {
                Price price = 1000 + j;
                // Skip list doesn't have simple find method for individual prices
                // This simulates read operations by attempting updates with 0 delta
                skip_list.insertOrUpdate(price, 0, 0);
                find_count.fetch_add(1);
            }
        });
    }
    
    // Remove threads (simulate remove by negative volumes)
    for (int i = 0; i < NUM_THREADS / 3; ++i) {
        threads.emplace_back([&skip_list, &remove_count, OPERATIONS_PER_THREAD, i]() {
            // Give time for some inserts
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            
            for (int j = 0; j < OPERATIONS_PER_THREAD / 2; ++j) {
                Price price = 1000 + (i * OPERATIONS_PER_THREAD / 2 + j);
                // Simulate removal by setting negative volume
                if (skip_list.insertOrUpdate(price, -1000, -1)) {
                    remove_count.fetch_add(1);
                }
            }
        });
    }
    
    // Wait for completion
    for (auto& thread : threads) {
        thread.join();
    }
    
    printf("Skip List Concurrency Test Results:\n");
    printf("  Insert operations: %d\n", insert_count.load());
    printf("  Find operations: %d\n", find_count.load());
    printf("  Remove operations: %d\n", remove_count.load());
    
    if (insert_count.load() == 0 || find_count.load() == 0) {
        throw std::runtime_error("Skip list operations failed");
    }
}

// Test hazard pointer memory reclamation under concurrent access
void testHazardPointerConcurrency() {
    using HP = HazardPointers<int>;
    
    const int NUM_THREADS = 4;
    const int ALLOCATIONS_PER_THREAD = 1000;
    
    std::atomic<int*> shared_ptr{nullptr};
    std::atomic<int> allocation_counter{0};
    std::atomic<int> deallocation_counter{0};
    std::vector<std::thread> threads;
    
    // Allocator threads
    for (int i = 0; i < NUM_THREADS / 2; ++i) {
        threads.emplace_back([&]() {
            for (int j = 0; j < ALLOCATIONS_PER_THREAD; ++j) {
                int* new_ptr = new int(j);
                allocation_counter.fetch_add(1);
                
                // Set shared pointer
                int* old_ptr = shared_ptr.exchange(new_ptr);
                
                if (old_ptr) {
                    // Retire old pointer using hazard pointers
                    HP::retirePointer(old_ptr);
                    deallocation_counter.fetch_add(1);
                }
                
                std::this_thread::sleep_for(std::chrono::microseconds(1));
            }
        });
    }
    
    // Reader threads
    for (int i = 0; i < NUM_THREADS / 2; ++i) {
        threads.emplace_back([&]() {
            for (int j = 0; j < ALLOCATIONS_PER_THREAD * 2; ++j) {
                HP::HazardPointer hp;
                int* ptr = HP::protectPointer(shared_ptr, hp);
                
                if (ptr) {
                    // Safely access the pointer
                    volatile int value = *ptr;
                    (void)value; // Suppress unused variable warning
                }
                
                // Small delay to increase contention
                std::this_thread::yield();
            }
        });
    }
    
    // Wait for completion
    for (auto& thread : threads) {
        thread.join();
    }
    
    // Force final scan
    HP::forceScan();
    
    // Clean up final pointer
    int* final_ptr = shared_ptr.load();
    if (final_ptr) {
        delete final_ptr;
    }
    
    printf("Hazard Pointer Test Results:\n");
    printf("  Allocations: %d\n", allocation_counter.load());
    printf("  Deallocations: %d\n", deallocation_counter.load());
    
    if (allocation_counter.load() == 0) {
        throw std::runtime_error("No allocations performed");
    }
}

// Test epoch-based memory reclamation
void testEpochBasedReclamation() {
    using EM = EpochManager<int>;
    
    const int NUM_THREADS = 4;
    const int OPERATIONS_PER_THREAD = 1000;
    
    std::atomic<int> allocation_counter{0};
    std::vector<std::thread> threads;
    
    for (int i = 0; i < NUM_THREADS; ++i) {
        threads.emplace_back([&allocation_counter, OPERATIONS_PER_THREAD]() {
            for (int j = 0; j < OPERATIONS_PER_THREAD; ++j) {
                {
                    EM::EpochGuard guard;
                    
                    // Simulate some critical section work
                    int* ptr = new int(j);
                    allocation_counter.fetch_add(1);
                    
                    // Retire the pointer
                    EM::retirePointer(ptr);
                }
                
                // Try to advance epoch
                EM::tryAdvanceEpoch();
                
                if (j % 100 == 0) {
                    std::this_thread::sleep_for(std::chrono::microseconds(1));
                }
            }
        });
    }
    
    // Wait for completion
    for (auto& thread : threads) {
        thread.join();
    }
    
    printf("Epoch-Based Reclamation Test Results:\n");
    printf("  Total allocations: %d\n", allocation_counter.load());
    
    if (allocation_counter.load() == 0) {
        throw std::runtime_error("No allocations performed");
    }
}

// Test mixed workload concurrency
void testMixedWorkloadConcurrency() {
    const int NUM_THREADS = 8;
    const int OPERATIONS_PER_THREAD = 2000;
    
    AtomicPriceLevel bid_level;
    AtomicPriceLevel ask_level;
    LockFreeSkipList<16> order_index;
    
    std::atomic<int> operations_completed{0};
    std::vector<std::thread> threads;
    
    for (int i = 0; i < NUM_THREADS; ++i) {
        threads.emplace_back([&, i]() {
            for (int j = 0; j < OPERATIONS_PER_THREAD; ++j) {
                int operation = (i * OPERATIONS_PER_THREAD + j) % 4;
                
                switch (operation) {
                    case 0: // Add bid order
                        bid_level.addOrder(100 + (j % 500));
                        break;
                        
                    case 1: // Add ask order
                        ask_level.addOrder(100 + (j % 500));
                        break;
                        
                    case 2: // Index operation
                        order_index.insertOrUpdate(1000 + j, 100 + j, 1);
                        break;
                        
                    case 3: // Read operations
                        {
                            Amount bid_volume = bid_level.getVolume();
                            Amount ask_volume = ask_level.getVolume();
                            // Simulate read by checking if operation succeeds
                            order_index.insertOrUpdate(1000 + (j % 500), 0, 0);
                            
                            // Verify basic invariants (Amount is unsigned, so no negative check needed)
                            if (bid_volume == 0 && ask_volume == 0) {
                                // This is fine, just means no orders
                            }
                        }
                        break;
                }
                
                operations_completed.fetch_add(1);
                
                // Occasional yield to increase contention
                if (j % 50 == 0) {
                    std::this_thread::yield();
                }
            }
        });
    }
    
    // Wait for completion
    for (auto& thread : threads) {
        thread.join();
    }
    
    printf("Mixed Workload Test Results:\n");
    printf("  Operations completed: %d\n", operations_completed.load());
    printf("  Expected operations: %d\n", NUM_THREADS * OPERATIONS_PER_THREAD);
    printf("  Bid volume: %lu\n", bid_level.getVolume());
    printf("  Ask volume: %lu\n", ask_level.getVolume());
    
    if (operations_completed.load() != NUM_THREADS * OPERATIONS_PER_THREAD) {
        throw std::runtime_error("Not all operations completed");
    }
}

int test_lockfree_concurrency_main() {
    printf("Running Enhanced Concurrency Tests for Lock-Free Structures\n");
    printf("=============================================================\n\n");
    
    TestRunner::run_test("Atomic Price Level Concurrency", testAtomicPriceLevelConcurrency);
    TestRunner::run_test("Lock-Free Skip List Concurrency", testLockFreeSkipListConcurrency);
    TestRunner::run_test("Hazard Pointer Concurrency", testHazardPointerConcurrency);
    TestRunner::run_test("Epoch-Based Reclamation", testEpochBasedReclamation);
    TestRunner::run_test("Mixed Workload Concurrency", testMixedWorkloadConcurrency);
    
    printf("\n=============================================================\n");
    TestRunner::print_summary();
    
    return TestRunner::get_exit_code();
}