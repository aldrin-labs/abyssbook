#pragma once

#include "common.hpp"
#include <memory>
#include <vector>
#include <atomic>
#include <mutex>

#ifdef __linux__
#include <unistd.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <cstdio>

// NUMA policy constants
#ifndef MPOL_BIND
#define MPOL_BIND 2
#endif

#ifndef SYS_mbind
#define SYS_mbind 237
#endif
#endif

namespace abyssbook {

// NUMA-aware memory allocation helpers
namespace numa {
#ifdef __linux__
    // Check if NUMA is available
    inline bool isNumaAvailable() {
        return access("/sys/devices/system/node", F_OK) == 0;
    }
    
    // Get number of NUMA nodes
    inline int getNumaNodeCount() {
        if (!isNumaAvailable()) return 1;
        
        int max_node = 0;
        FILE* fp = fopen("/sys/devices/system/node/online", "r");
        if (fp) {
            fscanf(fp, "%*d-%d", &max_node);
            fclose(fp);
        }
        return max_node + 1;
    }
    
    // Allocate memory on specific NUMA node
    void* allocateOnNode(std::size_t size, int node) {
        if (!isNumaAvailable()) {
            return std::aligned_alloc(CACHE_LINE_SIZE, size);
        }
        
        void* ptr = std::aligned_alloc(CACHE_LINE_SIZE, size);
        if (ptr) {
            // Move pages to specific NUMA node (Linux specific)
            long pages = (size + 4095) / 4096;
            unsigned long nodemask = 1UL << node;
            syscall(SYS_mbind, ptr, size, MPOL_BIND, &nodemask, sizeof(nodemask) * 8, 0);
        }
        return ptr;
    }
#else
    inline bool isNumaAvailable() { return false; }
    inline int getNumaNodeCount() { return 1; }
    inline void* allocateOnNode(std::size_t size, int) {
        return std::aligned_alloc(CACHE_LINE_SIZE, size);
    }
#endif
} // namespace numa

// Huge pages support
namespace hugepages {
#ifdef __linux__
    // Check if huge pages are available
    inline bool areHugePagesAvailable() {
        return access("/proc/sys/vm/nr_hugepages", F_OK) == 0;
    }
    
    // Allocate memory using huge pages
    void* allocateHugePages(std::size_t size) {
        if (!areHugePagesAvailable()) {
            return std::aligned_alloc(CACHE_LINE_SIZE, size);
        }
        
        // Round up to huge page boundary (2MB typically)
        constexpr std::size_t HUGE_PAGE_SIZE = 2 * 1024 * 1024;
        std::size_t aligned_size = ((size + HUGE_PAGE_SIZE - 1) / HUGE_PAGE_SIZE) * HUGE_PAGE_SIZE;
        
        void* ptr = mmap(nullptr, aligned_size, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
        
        if (ptr == MAP_FAILED) {
            // Fall back to regular allocation
            return std::aligned_alloc(CACHE_LINE_SIZE, size);
        }
        
        return ptr;
    }
    
    void deallocateHugePages(void* ptr, std::size_t size) {
        constexpr std::size_t HUGE_PAGE_SIZE = 2 * 1024 * 1024;
        std::size_t aligned_size = ((size + HUGE_PAGE_SIZE - 1) / HUGE_PAGE_SIZE) * HUGE_PAGE_SIZE;
        munmap(ptr, aligned_size);
    }
#else
    inline bool areHugePagesAvailable() { return false; }
    inline void* allocateHugePages(std::size_t size) {
        return std::aligned_alloc(CACHE_LINE_SIZE, size);
    }
    inline void deallocateHugePages(void* ptr, std::size_t) {
        std::free(ptr);
    }
#endif
} // namespace hugepages

// High-performance memory pool for order allocation
// Reduces allocation overhead and improves cache locality
class MemoryPool {
public:
    explicit MemoryPool(std::size_t block_size, std::size_t initial_blocks = 1024);
    ~MemoryPool();
    
    // Non-copyable but movable
    MemoryPool(const MemoryPool&) = delete;
    MemoryPool& operator=(const MemoryPool&) = delete;
    MemoryPool(MemoryPool&&) noexcept;
    MemoryPool& operator=(MemoryPool&&) noexcept;
    
    // Allocate a block of memory
    void* allocate() noexcept;
    
    // Deallocate a block of memory
    void deallocate(void* ptr) noexcept;
    
    // Get statistics about memory usage
    struct Stats {
        std::size_t total_blocks;
        std::size_t free_blocks;
        std::size_t allocated_blocks;
        std::size_t peak_allocated;
        std::size_t block_size;
        
        double utilization() const {
            return total_blocks > 0 ? 
                static_cast<double>(allocated_blocks) / total_blocks : 0.0;
        }
    };
    
    Stats getStats() const;
    
    // Reset the pool (deallocate all blocks)
    void reset();
    
    // Preallocate additional blocks
    void reserve(std::size_t additional_blocks);

private:
    struct Block {
        Block* next;
        CACHE_ALIGNED char data[];
    };
    
    struct Chunk {
        std::unique_ptr<char[]> memory;
        std::size_t size;
        std::size_t block_count;
    };
    
    void allocateNewChunk();
    void linkBlocks(char* chunk_start, std::size_t block_count);
    
    const std::size_t block_size_;
    const std::size_t aligned_block_size_;
    const std::size_t blocks_per_chunk_;
    
    mutable std::mutex mutex_;
    std::vector<Chunk> chunks_;
    std::atomic<Block*> free_list_;
    
    // Statistics (atomic for thread safety)
    mutable std::atomic<std::size_t> total_blocks_;
    mutable std::atomic<std::size_t> allocated_blocks_;
    mutable std::atomic<std::size_t> peak_allocated_;
};

// RAII wrapper for memory pool allocation
template<typename T>
class PoolAllocated {
public:
    explicit PoolAllocated(MemoryPool& pool) : pool_(pool), ptr_(nullptr) {
        static_assert(sizeof(T) <= pool.getStats().block_size, 
                     "Object too large for memory pool");
        ptr_ = static_cast<T*>(pool_.allocate());
        if (ptr_) {
            new(ptr_) T();
        }
    }
    
    template<typename... Args>
    PoolAllocated(MemoryPool& pool, Args&&... args) : pool_(pool), ptr_(nullptr) {
        static_assert(sizeof(T) <= pool.getStats().block_size, 
                     "Object too large for memory pool");
        ptr_ = static_cast<T*>(pool_.allocate());
        if (ptr_) {
            new(ptr_) T(std::forward<Args>(args)...);
        }
    }
    
    ~PoolAllocated() {
        if (ptr_) {
            ptr_->~T();
            pool_.deallocate(ptr_);
        }
    }
    
    // Non-copyable but movable
    PoolAllocated(const PoolAllocated&) = delete;
    PoolAllocated& operator=(const PoolAllocated&) = delete;
    
    PoolAllocated(PoolAllocated&& other) noexcept 
        : pool_(other.pool_), ptr_(other.ptr_) {
        other.ptr_ = nullptr;
    }
    
    PoolAllocated& operator=(PoolAllocated&& other) noexcept {
        if (this != &other) {
            if (ptr_) {
                ptr_->~T();
                pool_.deallocate(ptr_);
            }
            ptr_ = other.ptr_;
            other.ptr_ = nullptr;
        }
        return *this;
    }
    
    T* get() const noexcept { return ptr_; }
    T& operator*() const { return *ptr_; }
    T* operator->() const { return ptr_; }
    
    explicit operator bool() const noexcept { return ptr_ != nullptr; }
    
    T* release() noexcept {
        T* temp = ptr_;
        ptr_ = nullptr;
        return temp;
    }

private:
    MemoryPool& pool_;
    T* ptr_;
};

// Custom allocator for STL containers
template<typename T>
class PoolAllocator {
public:
    using value_type = T;
    using pointer = T*;
    using const_pointer = const T*;
    using reference = T&;
    using const_reference = const T&;
    using size_type = std::size_t;
    using difference_type = std::ptrdiff_t;
    
    template<typename U>
    struct rebind {
        using other = PoolAllocator<U>;
    };
    
    explicit PoolAllocator(MemoryPool& pool) : pool_(&pool) {}
    
    template<typename U>
    PoolAllocator(const PoolAllocator<U>& other) : pool_(other.pool_) {}
    
    pointer allocate(size_type n) {
        if (n == 1 && sizeof(T) <= pool_->getStats().block_size) {
            return static_cast<pointer>(pool_->allocate());
        }
        // Fall back to standard allocation for larger requests
        return static_cast<pointer>(std::aligned_alloc(alignof(T), n * sizeof(T)));
    }
    
    void deallocate(pointer p, size_type n) {
        if (n == 1 && sizeof(T) <= pool_->getStats().block_size) {
            pool_->deallocate(p);
        } else {
            std::free(p);
        }
    }
    
    template<typename U, typename... Args>
    void construct(U* p, Args&&... args) {
        new(p) U(std::forward<Args>(args)...);
    }
    
    template<typename U>
    void destroy(U* p) {
        p->~U();
    }
    
    bool operator==(const PoolAllocator& other) const {
        return pool_ == other.pool_;
    }
    
    bool operator!=(const PoolAllocator& other) const {
        return !(*this == other);
    }
    
    MemoryPool* pool_;
};

// Lock-free memory pool for high-frequency allocations
class LockFreeMemoryPool {
public:
    explicit LockFreeMemoryPool(std::size_t block_size, std::size_t initial_blocks = 1024);
    ~LockFreeMemoryPool();
    
    // Non-copyable and non-movable (due to atomic pointers)
    LockFreeMemoryPool(const LockFreeMemoryPool&) = delete;
    LockFreeMemoryPool& operator=(const LockFreeMemoryPool&) = delete;
    LockFreeMemoryPool(LockFreeMemoryPool&&) = delete;
    LockFreeMemoryPool& operator=(LockFreeMemoryPool&&) = delete;
    
    void* allocate() noexcept;
    void deallocate(void* ptr) noexcept;
    
    MemoryPool::Stats getStats() const;

private:
    struct alignas(CACHE_LINE_SIZE) Block {
        std::atomic<Block*> next;
        char data[];
    };
    
    void allocateNewChunk();
    
    const std::size_t block_size_;
    const std::size_t aligned_block_size_;
    
    std::atomic<Block*> free_list_;
    std::vector<std::unique_ptr<char[]>> chunks_;
    mutable std::mutex chunk_mutex_;  // Only for chunk allocation
    
    std::atomic<std::size_t> total_blocks_;
    std::atomic<std::size_t> allocated_blocks_;
};

} // namespace abyssbook