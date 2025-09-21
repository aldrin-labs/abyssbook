#!/bin/bash

# Abyssbook Performance Testing Script
# This script provides easy access to all performance testing tools

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}    Abyssbook Performance Testing Suite    ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo
}

print_usage() {
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  bench         Run benchmark suite"
    echo "  profile       Run performance profiler"
    echo "  load-test     Run load testing"
    echo "  regression    Run regression tests"
    echo "  all           Run all performance tests"
    echo "  build         Build all performance tools"
    echo "  clean         Clean build artifacts"
    echo "  help          Show this help message"
    echo
    echo "Examples:"
    echo "  $0 bench          # Run benchmarks"
    echo "  $0 all            # Run all performance tests"
    echo "  $0 build          # Build performance tools"
    echo
}

check_zig() {
    if ! command -v zig &> /dev/null; then
        echo -e "${RED}Error: Zig compiler not found${NC}"
        echo "Please install Zig from https://ziglang.org/"
        exit 1
    fi
}

run_benchmark() {
    echo -e "${GREEN}Running benchmark suite...${NC}"
    echo "This may take a few minutes depending on your system."
    echo
    zig build bench
}

run_profiler() {
    echo -e "${GREEN}Running performance profiler...${NC}"
    echo "Analyzing hotspots and performance bottlenecks..."
    echo
    zig build profile
}

run_load_test() {
    echo -e "${GREEN}Running load test...${NC}"
    echo "Testing sustained performance under load..."
    echo
    zig build load-test
}

run_regression_test() {
    echo -e "${GREEN}Running regression tests...${NC}"
    echo "Checking for performance regressions..."
    echo
    zig build regression-test
}

run_all_tests() {
    echo -e "${GREEN}Running all performance tests...${NC}"
    echo "This will take several minutes to complete."
    echo
    
    echo -e "${YELLOW}1/4: Running benchmarks...${NC}"
    run_benchmark
    echo
    
    echo -e "${YELLOW}2/4: Running profiler...${NC}"
    run_profiler
    echo
    
    echo -e "${YELLOW}3/4: Running load test...${NC}"
    run_load_test
    echo
    
    echo -e "${YELLOW}4/4: Running regression tests...${NC}"
    run_regression_test
    echo
    
    echo -e "${GREEN}All performance tests completed!${NC}"
}

build_tools() {
    echo -e "${GREEN}Building performance tools...${NC}"
    zig build bench
    zig build profile  
    zig build load-test
    zig build regression-test
    echo -e "${GREEN}All tools built successfully!${NC}"
}

clean_artifacts() {
    echo -e "${YELLOW}Cleaning build artifacts...${NC}"
    rm -rf zig-cache zig-out benchmark_results
    echo -e "${GREEN}Clean completed!${NC}"
}

# Main script logic
case "${1:-help}" in
    "bench")
        print_header
        check_zig
        run_benchmark
        ;;
    "profile")
        print_header
        check_zig
        run_profiler
        ;;
    "load-test")
        print_header
        check_zig
        run_load_test
        ;;
    "regression")
        print_header
        check_zig
        run_regression_test
        ;;
    "all")
        print_header
        check_zig
        run_all_tests
        ;;
    "build")
        print_header
        check_zig
        build_tools
        ;;
    "clean")
        print_header
        clean_artifacts
        ;;
    "help"|"-h"|"--help")
        print_header
        print_usage
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$1'${NC}"
        echo
        print_usage
        exit 1
        ;;
esac