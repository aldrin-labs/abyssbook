cmake_minimum_required(VERSION 3.16)
project(abyssbook VERSION 1.0.0 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Compiler-specific options
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Wpedantic")
    set(CMAKE_CXX_FLAGS_DEBUG "-g -O0 -DDEBUG")
    
    # Aggressive optimization for release builds
    set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -march=native -mtune=native")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -funroll-loops")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -fomit-frame-pointer -finline-functions")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -ffast-math")
    
    # Link-time optimization (commented for compatibility)
    # set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -flto -fuse-linker-plugin")
    # set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} -flto")
    # set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} -flto")
    
    set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-O2 -g -DNDEBUG")
    
    # Enhanced SIMD optimizations - detect what's available (conservative)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -msse4.2 -mavx -mavx2")
    
    # Try to enable AVX-512 if available (disabled for compatibility)
    # include(CheckCXXCompilerFlag)
    # check_cxx_compiler_flag("-mavx512f" COMPILER_SUPPORTS_AVX512F)
    # if(COMPILER_SUPPORTS_AVX512F)
    #     set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -mavx512f -mavx512dq -mavx512bw")
    #     message(STATUS "AVX-512 support enabled")
    # endif()
    
    # Enable additional instruction sets if available
    # include(CheckCXXCompilerFlag)
    # check_cxx_compiler_flag("-mbmi" COMPILER_SUPPORTS_BMI)
    # if(COMPILER_SUPPORTS_BMI)
    #     set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mbmi -mbmi2")
    # endif()
    
    # check_cxx_compiler_flag("-mlzcnt" COMPILER_SUPPORTS_LZCNT)
    # if(COMPILER_SUPPORTS_LZCNT)
    #     set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mlzcnt")
    # endif()
    
    # Profile-guided optimization setup (commented out by default)
    # set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -fprofile-generate")
    # set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} -fprofile-generate")
    
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /W4")
    set(CMAKE_CXX_FLAGS_RELEASE "/O2 /DNDEBUG /arch:AVX2")
endif()

# Find required packages
find_package(Threads REQUIRED)

# Include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src)

# Source files
set(ABYSSBOOK_SOURCES
    src/cpp/orderbook.cpp
    src/cpp/order_types.cpp
    src/cpp/price_level.cpp
    src/cpp/order_matching.cpp
    src/cpp/advanced_orders.cpp
    src/cpp/market_data.cpp
    src/cpp/memory_pool.cpp
)

# Header files
set(ABYSSBOOK_HEADERS
    include/abyssbook/orderbook.hpp
    include/abyssbook/order_types.hpp
    include/abyssbook/price_level.hpp
    include/abyssbook/order_matching.hpp
    include/abyssbook/advanced_orders.hpp
    include/abyssbook/market_data.hpp
    include/abyssbook/memory_pool.hpp
    include/abyssbook/simd_helpers.hpp
    include/abyssbook/common.hpp
    include/abyssbook/lockfree_structures.hpp
    include/abyssbook/template_optimizations.hpp
    include/abyssbook/optimized_matching.hpp
    include/abyssbook/novel_structures.hpp
    include/abyssbook/fusion_structures.hpp
)

# Create static library
add_library(abyssbook_static STATIC ${ABYSSBOOK_SOURCES} ${ABYSSBOOK_HEADERS})
target_link_libraries(abyssbook_static Threads::Threads)

# Create shared library
add_library(abyssbook_shared SHARED ${ABYSSBOOK_SOURCES} ${ABYSSBOOK_HEADERS})
target_link_libraries(abyssbook_shared Threads::Threads)

# Main executable
add_executable(abyssbook src/cpp/main.cpp)
target_link_libraries(abyssbook abyssbook_static)

# Benchmark executable
add_executable(abyssbook_bench 
    src/cpp/benchmark/benchmark_main.cpp 
    src/cpp/benchmark/order_bench.cpp 
    src/cpp/benchmark/matching_bench.cpp 
    src/cpp/benchmark/advanced_order_bench.cpp
)
target_link_libraries(abyssbook_bench abyssbook_static)

# Novel structures benchmark executable
add_executable(novel_structures_bench 
    src/cpp/benchmark/novel_structures_bench.cpp
)
target_link_libraries(novel_structures_bench abyssbook_static)

# Working novel benchmark executable  
add_executable(working_novel_bench
    src/cpp/benchmark/working_novel_bench.cpp
)
target_link_libraries(working_novel_bench abyssbook_static)

# Testing
enable_testing()

# Unit tests executable
add_executable(unit_tests 
    src/cpp/tests/test_framework.cpp
    src/cpp/tests/unit/test_orderbook.cpp
    src/cpp/tests/unit/test_order_types.cpp
    src/cpp/tests/unit/test_price_level.cpp
    src/cpp/tests/unit/test_order_matching.cpp
    src/cpp/tests/unit/test_advanced_orders.cpp
    src/cpp/tests/unit/test_memory_pool.cpp
    src/cpp/tests/unit/test_main.cpp
)
target_link_libraries(unit_tests abyssbook_static)
add_test(NAME UnitTests COMMAND unit_tests)

# Integration tests executable
add_executable(integration_tests
    src/cpp/tests/integration/test_full_trading_scenario.cpp
    src/cpp/tests/integration/test_multi_threaded_access.cpp
    src/cpp/tests/integration/test_stress_scenarios.cpp
    src/cpp/tests/integration/integration_test_main.cpp
)
target_link_libraries(integration_tests abyssbook_static)
add_test(NAME IntegrationTests COMMAND integration_tests)

# End-to-end tests executable
add_executable(e2e_tests
    src/cpp/tests/e2e/test_complete_trading_workflow.cpp
    src/cpp/tests/e2e/test_market_making_scenario.cpp
    src/cpp/tests/e2e/test_high_frequency_trading.cpp
    src/cpp/tests/e2e/e2e_test_main.cpp
)
target_link_libraries(e2e_tests abyssbook_static)
add_test(NAME E2ETests COMMAND e2e_tests)

# Security tests executable
add_executable(security_tests
    src/cpp/tests/security/test_input_validation.cpp
    src/cpp/tests/security/test_memory_safety.cpp
    src/cpp/tests/security/test_thread_safety.cpp
    src/cpp/tests/security/security_test_main.cpp
)
target_link_libraries(security_tests abyssbook_static)
add_test(NAME SecurityTests COMMAND security_tests)

# Custom targets for different test types
add_custom_target(test-unit
    COMMAND unit_tests
    DEPENDS unit_tests
    COMMENT "Running unit tests"
)

add_custom_target(test-integration
    COMMAND integration_tests
    DEPENDS integration_tests
    COMMENT "Running integration tests"
)

add_custom_target(test-e2e
    COMMAND e2e_tests
    DEPENDS e2e_tests
    COMMENT "Running end-to-end tests"
)

add_custom_target(test-security
    COMMAND security_tests
    DEPENDS security_tests
    COMMENT "Running security tests"
)

add_custom_target(test-all
    COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure
    DEPENDS unit_tests integration_tests e2e_tests security_tests
    COMMENT "Running all tests"
)

add_custom_target(bench
    COMMAND abyssbook_bench
    DEPENDS abyssbook_bench
    COMMENT "Running benchmarks"
)

add_custom_target(bench-novel
    COMMAND novel_structures_bench
    DEPENDS novel_structures_bench
    COMMENT "Running novel data structures benchmarks"
)

add_custom_target(bench-working
    COMMAND working_novel_bench  
    DEPENDS working_novel_bench
    COMMENT "Running working novel optimizations benchmark"
)

# Installation
install(TARGETS abyssbook abyssbook_static abyssbook_shared
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)

# CPack configuration for packaging
set(CPACK_PACKAGE_NAME "abyssbook")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "High-performance DEX orderbook implementation")
set(CPACK_PACKAGE_CONTACT "aldrin-labs")
include(CPack)