#pragma once

#include <iostream>
#include <functional>
#include <string>

// Simple test framework for unit tests
class TestRunner {
public:
    static void run_test(const std::string& test_name, std::function<void()> test_func);
    static void print_summary();
    static int get_exit_code();

private:
    static int passed_;
    static int failed_;
};