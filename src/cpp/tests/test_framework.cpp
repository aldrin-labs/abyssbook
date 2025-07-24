#include "test_framework.hpp"

// Define the static members
int TestRunner::passed_ = 0;
int TestRunner::failed_ = 0;

void TestRunner::run_test(const std::string& test_name, std::function<void()> test_func) {
    try {
        std::cout << "Running " << test_name << "... ";
        test_func();
        std::cout << "PASSED" << std::endl;
        passed_++;
    } catch (const std::exception& e) {
        std::cout << "FAILED: " << e.what() << std::endl;
        failed_++;
    } catch (...) {
        std::cout << "FAILED: Unknown exception" << std::endl;
        failed_++;
    }
}

void TestRunner::print_summary() {
    std::cout << "\nTest Summary: " << passed_ << " passed, " << failed_ << " failed" << std::endl;
}

int TestRunner::get_exit_code() {
    return failed_ > 0 ? 1 : 0;
}