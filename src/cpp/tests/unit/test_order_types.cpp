#include "abyssbook/order_types.hpp"
#include "../test_framework.hpp"
#include <iostream>
#include <cassert>
#include <chrono>

// Test basic order creation and properties
void test_basic_order_creation() {
    using namespace abyssbook;
    
    auto order = OrderFactory::createLimit(1000, 100, 1, OrderSide::Buy);
    
    assert(order.price == 1000);
    assert(order.amount == 100);
    assert(order.id == 1);
    assert(order.side == OrderSide::Buy);
    assert(order.order_type == OrderType::Limit);
    assert(order.validate() == OrderError::Success);
}

void test_advanced_order_types() {
    using namespace abyssbook;
    
    // Test TWAP order
    auto twap = OrderFactory::createTWAP(1000, 500, 2, OrderSide::Buy, 5, 60);
    assert(twap.flags.is_twap);
    assert(twap.twap_params != nullptr);
    assert(twap.twap_params->num_intervals == 5);
    assert(twap.twap_params->interval_seconds == 60);
    assert(twap.twap_params->amount_per_interval == 100); // 500/5
    
    // Test Iceberg order
    auto iceberg = OrderFactory::createIceberg(1000, 500, 50, 3, OrderSide::Sell);
    assert(iceberg.flags.is_iceberg);
    assert(iceberg.display_amount == 50);
    assert(iceberg.getDisplayAmount() == 50);
    
    // Test Stop order
    auto stop = OrderFactory::createStop(1000, 100, 4, OrderSide::Sell, 950);
    assert(stop.flags.is_stop);
    assert(stop.stop_price == 950);
    assert(!stop.shouldTrigger(960)); // Market price above stop
    assert(stop.shouldTrigger(940));  // Market price below stop
}

void test_order_validation() {
    using namespace abyssbook;
    
    // Valid order
    auto valid_order = OrderFactory::createLimit(1000, 100, 1, OrderSide::Buy);
    assert(valid_order.validate() == OrderError::Success);
    
    // Invalid price (zero for limit order)
    CacheAlignedOrder invalid_price(0, 100, 2, OrderSide::Buy, OrderType::Limit);
    assert(invalid_price.validate() == OrderError::InvalidPrice);
    
    // Invalid amount (zero)
    CacheAlignedOrder invalid_amount(1000, 0, 3, OrderSide::Buy, OrderType::Limit);
    assert(invalid_amount.validate() == OrderError::InvalidAmount);
}

void test_order_flags() {
    using namespace abyssbook;
    
    // Test IOC order flags
    auto ioc = OrderFactory::createIOC(1000, 100, 1, OrderSide::Buy);
    assert(ioc.flags.is_ioc);
    assert(!ioc.flags.is_fok);
    assert(!ioc.flags.is_stop);
    
    // Test FOK order flags
    auto fok = OrderFactory::createFOK(1000, 100, 2, OrderSide::Buy);
    assert(fok.flags.is_fok);
    assert(!fok.flags.is_ioc);
    
    // Test Post-only order flags
    auto post_only = OrderFactory::createPostOnly(1000, 100, 3, OrderSide::Buy);
    assert(post_only.flags.is_post_only);
}

void test_order_copy_semantics() {
    using namespace abyssbook;
    
    auto original = OrderFactory::createTWAP(1000, 500, 1, OrderSide::Buy, 5, 60);
    
    // Test copy constructor
    CacheAlignedOrder copied(original);
    assert(copied.id == original.id);
    assert(copied.price == original.price);
    assert(copied.amount == original.amount);
    assert(copied.twap_params != nullptr);
    assert(copied.twap_params.get() != original.twap_params.get()); // Different pointer
    assert(copied.twap_params->num_intervals == original.twap_params->num_intervals);
    
    // Test move constructor
    CacheAlignedOrder moved(std::move(original));
    assert(moved.id == 1);
    assert(moved.twap_params != nullptr);
    assert(original.twap_params == nullptr); // Moved from
}

void test_performance_basic() {
    using namespace abyssbook;
    
    const int num_orders = 100000;
    auto start = std::chrono::high_resolution_clock::now();
    
    for (int i = 0; i < num_orders; ++i) {
        auto order = OrderFactory::createLimit(1000 + (i % 100), 100, i, 
                                              (i % 2) ? OrderSide::Buy : OrderSide::Sell);
        // Simulate some work
        volatile auto price = order.price;
        (void)price;
    }
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
    
    double orders_per_second = (num_orders * 1000000.0) / duration.count();
    std::cout << "Created " << num_orders << " orders in " << duration.count() 
              << " microseconds (" << orders_per_second << " orders/sec)" << std::endl;
    
    // Should be able to create at least 1M orders per second
    assert(orders_per_second > 1000000);
}

int test_order_types_main() {
    std::cout << "Running C++ AbyssBook Order Types Tests\n" << std::endl;
    
    TestRunner::run_test("Basic Order Creation", test_basic_order_creation);
    TestRunner::run_test("Advanced Order Types", test_advanced_order_types);
    TestRunner::run_test("Order Validation", test_order_validation);
    TestRunner::run_test("Order Flags", test_order_flags);
    TestRunner::run_test("Order Copy Semantics", test_order_copy_semantics);
    TestRunner::run_test("Performance Basic", test_performance_basic);
    
    TestRunner::print_summary();
    return TestRunner::get_exit_code();
}