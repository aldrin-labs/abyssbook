#pragma once

#include "common.hpp"
#include <random>
#include <memory>
#include <thread>
#include <chrono>

namespace abyssbook {
namespace random {

//=============================================================================
// Thread-Safe Random Number Generation
//=============================================================================

class ThreadSafePRNG {
private:
    // Thread-local storage for per-thread generators
    static thread_local std::unique_ptr<std::mt19937_64> generator_;
    static thread_local std::uniform_real_distribution<float> float_dist_;
    static thread_local std::uniform_int_distribution<int> int_dist_;
    
    // Initialize thread-local generator if needed
    static void ensureInitialized() {
        if (!generator_) {
            // Use a combination of thread ID and high-resolution time for seeding
            auto now = std::chrono::high_resolution_clock::now();
            auto thread_id = std::hash<std::thread::id>{}(std::this_thread::get_id());
            auto seed = static_cast<uint64_t>(now.time_since_epoch().count()) ^ thread_id;
            
            generator_ = std::make_unique<std::mt19937_64>(seed);
            float_dist_ = std::uniform_real_distribution<float>(0.0f, 1.0f);
            int_dist_ = std::uniform_int_distribution<int>(0, 1);
        }
    }
    
public:
    // Generate random float in [0.0, 1.0)
    HOT FORCE_INLINE static float randomFloat() {
        ensureInitialized();
        return float_dist_(*generator_);
    }
    
    // Generate random integer in [0, max)
    HOT FORCE_INLINE static int randomInt(int max) {
        ensureInitialized();
        std::uniform_int_distribution<int> dist(0, max - 1);
        return dist(*generator_);
    }
    
    // Generate random bit (0 or 1)
    HOT FORCE_INLINE static int randomBit() {
        ensureInitialized();
        return int_dist_(*generator_);
    }
    
    // Generate random boolean
    HOT FORCE_INLINE static bool randomBool() {
        return randomBit() == 1;
    }
    
    // Generate random float in specific range
    HOT FORCE_INLINE static float randomFloat(float min, float max) {
        ensureInitialized();
        std::uniform_real_distribution<float> dist(min, max);
        return dist(*generator_);
    }
    
    // Reseed the thread-local generator
    static void reseed(uint64_t seed = 0) {
        if (seed == 0) {
            auto now = std::chrono::high_resolution_clock::now();
            auto thread_id = std::hash<std::thread::id>{}(std::this_thread::get_id());
            seed = static_cast<uint64_t>(now.time_since_epoch().count()) ^ thread_id;
        }
        
        ensureInitialized();
        generator_->seed(seed);
    }
};

// Static member definitions
thread_local std::unique_ptr<std::mt19937_64> ThreadSafePRNG::generator_;
thread_local std::uniform_real_distribution<float> ThreadSafePRNG::float_dist_;
thread_local std::uniform_int_distribution<int> ThreadSafePRNG::int_dist_;

//=============================================================================
// Fast Lock-Free Random Number Generation for Performance-Critical Paths
//=============================================================================

class FastThreadLocalRNG {
private:
    // Simple Linear Congruential Generator for very fast generation
    static thread_local uint64_t state_;
    
    static void ensureInitialized() {
        if (state_ == 0) {
            auto now = std::chrono::high_resolution_clock::now();
            auto thread_id = std::hash<std::thread::id>{}(std::this_thread::get_id());
            state_ = static_cast<uint64_t>(now.time_since_epoch().count()) ^ thread_id;
            if (state_ == 0) state_ = 1; // Ensure non-zero state
        }
    }
    
public:
    // Very fast random number generation using LCG
    HOT FORCE_INLINE static uint32_t fastRandom() {
        ensureInitialized();
        state_ = state_ * 1103515245ULL + 12345ULL;
        return static_cast<uint32_t>(state_ >> 32);
    }
    
    // Fast random float in [0.0, 1.0)
    HOT FORCE_INLINE static float fastRandomFloat() {
        return static_cast<float>(fastRandom()) / static_cast<float>(UINT32_MAX);
    }
    
    // Fast random bit
    HOT FORCE_INLINE static int fastRandomBit() {
        return fastRandom() & 1;
    }
    
    // Fast random boolean
    HOT FORCE_INLINE static bool fastRandomBool() {
        return fastRandomBit() == 1;
    }
};

// Static member definition
thread_local uint64_t FastThreadLocalRNG::state_ = 0;

// Convenience aliases
using TSPRNG = ThreadSafePRNG;
using FastRNG = FastThreadLocalRNG;

} // namespace random
} // namespace abyssbook