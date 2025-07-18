#include <iostream>

// Test runner entry point for unit tests
int main() {
    extern int test_order_types_main();
    extern int test_price_level_main();
    
    std::cout << "=== Running Unit Tests ===" << std::endl;
    
    int result = 0;
    result |= test_order_types_main();
    result |= test_price_level_main();
    
    return result;
}