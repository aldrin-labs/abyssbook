#pragma once

#include "common.hpp"
#include <atomic>
#include <array>
#include <memory>
#include <vector>
#include <thread>
#include <algorithm>
#include <cassert>

namespace abyssbook {
namespace memory {

//=============================================================================
// Hazard Pointer Implementation for Lock-Free Memory Reclamation
//=============================================================================

template<typename T>
class HazardPointers {
private:
    static constexpr int MAX_THREADS = 64;
    static constexpr int HAZARD_PTRS_PER_THREAD = 4;
    static constexpr int RETIRED_LIST_MAX_SIZE = 64;
    
    struct HazardRecord {
        std::array<std::atomic<T*>, HAZARD_PTRS_PER_THREAD> hazard_ptrs;
        std::atomic<bool> active{false};
        
        HazardRecord() {
            for (auto& ptr : hazard_ptrs) {
                ptr.store(nullptr, std::memory_order_relaxed);
            }
        }
    };
    
    struct RetiredNode {
        T* ptr;
        std::function<void(T*)> deleter;
        
        RetiredNode(T* p, std::function<void(T*)> del) : ptr(p), deleter(std::move(del)) {}
    };
    
    static std::array<HazardRecord, MAX_THREADS> hazard_records_;
    static thread_local int thread_id_;
    static thread_local std::vector<RetiredNode> retired_list_;
    static thread_local bool initialized_;
    static std::atomic<int> next_thread_id_;
    
    static void ensureInitialized() {
        if (!initialized_) {
            thread_id_ = next_thread_id_.fetch_add(1, std::memory_order_relaxed);
            if (thread_id_ >= MAX_THREADS) {
                // Handle thread ID overflow (reuse)
                thread_id_ = thread_id_ % MAX_THREADS;
            }
            hazard_records_[thread_id_].active.store(true, std::memory_order_relaxed);
            initialized_ = true;
        }
    }
    
    static bool isHazardous(T* ptr) {
        for (int i = 0; i < MAX_THREADS; ++i) {
            if (!hazard_records_[i].active.load(std::memory_order_relaxed)) {
                continue;
            }
            
            for (int j = 0; j < HAZARD_PTRS_PER_THREAD; ++j) {
                if (hazard_records_[i].hazard_ptrs[j].load(std::memory_order_acquire) == ptr) {
                    return true;
                }
            }
        }
        return false;
    }
    
    static void scan() {
        // Move non-hazardous retired nodes to a separate list for deletion
        std::vector<RetiredNode> to_delete;
        std::vector<RetiredNode> still_retired;
        
        for (auto& retired : retired_list_) {
            if (!isHazardous(retired.ptr)) {
                to_delete.push_back(std::move(retired));
            } else {
                still_retired.push_back(std::move(retired));
            }
        }
        
        retired_list_ = std::move(still_retired);
        
        // Delete non-hazardous nodes
        for (auto& node : to_delete) {
            node.deleter(node.ptr);
        }
    }
    
public:
    class HazardPointer {
    private:
        int slot_;
        
    public:
        explicit HazardPointer(int slot = 0) : slot_(slot) {
            ensureInitialized();
            assert(slot < HAZARD_PTRS_PER_THREAD);
        }
        
        ~HazardPointer() {
            reset();
        }
        
        // Non-copyable but movable
        HazardPointer(const HazardPointer&) = delete;
        HazardPointer& operator=(const HazardPointer&) = delete;
        
        HazardPointer(HazardPointer&& other) noexcept : slot_(other.slot_) {
            other.slot_ = -1;
        }
        
        HazardPointer& operator=(HazardPointer&& other) noexcept {
            if (this != &other) {
                reset();
                slot_ = other.slot_;
                other.slot_ = -1;
            }
            return *this;
        }
        
        void protect(T* ptr) {
            if (slot_ >= 0) {
                hazard_records_[thread_id_].hazard_ptrs[slot_].store(ptr, std::memory_order_release);
            }
        }
        
        void reset() {
            if (slot_ >= 0) {
                hazard_records_[thread_id_].hazard_ptrs[slot_].store(nullptr, std::memory_order_release);
            }
        }
        
        T* get() const {
            if (slot_ >= 0) {
                return hazard_records_[thread_id_].hazard_ptrs[slot_].load(std::memory_order_acquire);
            }
            return nullptr;
        }
    };
    
    // Protect a pointer during traversal
    template<typename AtomicPtr>
    static T* protectPointer(AtomicPtr& atomic_ptr, HazardPointer& hp) {
        T* ptr;
        do {
            ptr = atomic_ptr.load(std::memory_order_acquire);
            hp.protect(ptr);
            // Check if pointer changed while we were protecting it
        } while (ptr != atomic_ptr.load(std::memory_order_acquire));
        
        return ptr;
    }
    
    // Retire a pointer for later deletion
    static void retirePointer(T* ptr, std::function<void(T*)> deleter = [](T* p) { delete p; }) {
        ensureInitialized();
        
        retired_list_.emplace_back(ptr, std::move(deleter));
        
        // Trigger scan if retired list is getting large
        if (retired_list_.size() >= RETIRED_LIST_MAX_SIZE) {
            scan();
        }
    }
    
    // Force scan of retired list
    static void forceScan() {
        ensureInitialized();
        scan();
    }
    
    // Clean up when thread exits
    static void threadCleanup() {
        if (initialized_) {
            // Scan one final time
            scan();
            
            // Clear all hazard pointers
            for (auto& ptr : hazard_records_[thread_id_].hazard_ptrs) {
                ptr.store(nullptr, std::memory_order_relaxed);
            }
            
            hazard_records_[thread_id_].active.store(false, std::memory_order_relaxed);
            initialized_ = false;
        }
    }
};

// Static member definitions
template<typename T>
std::array<typename HazardPointers<T>::HazardRecord, HazardPointers<T>::MAX_THREADS> 
    HazardPointers<T>::hazard_records_;

template<typename T>
thread_local int HazardPointers<T>::thread_id_ = -1;

template<typename T>
thread_local std::vector<typename HazardPointers<T>::RetiredNode> HazardPointers<T>::retired_list_;

template<typename T>
thread_local bool HazardPointers<T>::initialized_ = false;

template<typename T>
std::atomic<int> HazardPointers<T>::next_thread_id_{0};

//=============================================================================
// Epoch-Based Memory Reclamation (Alternative to Hazard Pointers)
//=============================================================================

template<typename T>
class EpochManager {
private:
    static constexpr int MAX_THREADS = 64;
    static constexpr int EPOCHS_TO_WAIT = 3;
    
    struct ThreadData {
        std::atomic<uint64_t> local_epoch{0};
        std::atomic<bool> active{false};
        std::array<std::vector<T*>, EPOCHS_TO_WAIT> retired_lists;
        uint64_t current_list_index{0};
    };
    
    static std::atomic<uint64_t> global_epoch_;
    static std::array<ThreadData, MAX_THREADS> thread_data_;
    static thread_local int thread_id_;
    static thread_local bool initialized_;
    static std::atomic<int> next_thread_id_;
    
    static void ensureInitialized() {
        if (!initialized_) {
            thread_id_ = next_thread_id_.fetch_add(1, std::memory_order_relaxed);
            if (thread_id_ >= MAX_THREADS) {
                thread_id_ = thread_id_ % MAX_THREADS;
            }
            thread_data_[thread_id_].active.store(true, std::memory_order_relaxed);
            initialized_ = true;
        }
    }
    
public:
    class EpochGuard {
    private:
        uint64_t epoch_;
        
    public:
        EpochGuard() {
            ensureInitialized();
            epoch_ = global_epoch_.load(std::memory_order_acquire);
            thread_data_[thread_id_].local_epoch.store(epoch_, std::memory_order_release);
        }
        
        ~EpochGuard() {
            thread_data_[thread_id_].local_epoch.store(0, std::memory_order_release);
        }
        
        // Non-copyable, non-movable
        EpochGuard(const EpochGuard&) = delete;
        EpochGuard& operator=(const EpochGuard&) = delete;
        EpochGuard(EpochGuard&&) = delete;
        EpochGuard& operator=(EpochGuard&&) = delete;
    };
    
    static void retirePointer(T* ptr) {
        ensureInitialized();
        
        auto& data = thread_data_[thread_id_];
        uint64_t list_index = data.current_list_index % EPOCHS_TO_WAIT;
        data.retired_lists[list_index].push_back(ptr);
        
        // Try to advance epoch and clean up old objects
        tryAdvanceEpoch();
    }
    
    static void tryAdvanceEpoch() {
        uint64_t current_global = global_epoch_.load(std::memory_order_acquire);
        
        // Check if all threads have caught up
        uint64_t min_epoch = current_global;
        for (int i = 0; i < MAX_THREADS; ++i) {
            if (thread_data_[i].active.load(std::memory_order_relaxed)) {
                uint64_t local_epoch = thread_data_[i].local_epoch.load(std::memory_order_acquire);
                if (local_epoch > 0) { // 0 means not in critical section
                    min_epoch = std::min(min_epoch, local_epoch);
                }
            }
        }
        
        // If all active threads are at current epoch, try to advance
        if (min_epoch == current_global) {
            uint64_t new_epoch = current_global + 1;
            if (global_epoch_.compare_exchange_weak(current_global, new_epoch, std::memory_order_acq_rel)) {
                cleanupOldObjects(new_epoch);
            }
        }
    }
    
private:
    static void cleanupOldObjects(uint64_t current_epoch) {
        ensureInitialized();
        
        auto& data = thread_data_[thread_id_];
        uint64_t cleanup_index = (current_epoch - EPOCHS_TO_WAIT) % EPOCHS_TO_WAIT;
        
        // Delete objects from old epoch
        for (T* ptr : data.retired_lists[cleanup_index]) {
            delete ptr;
        }
        data.retired_lists[cleanup_index].clear();
        
        data.current_list_index = current_epoch % EPOCHS_TO_WAIT;
    }
    
public:
    static void threadCleanup() {
        if (initialized_) {
            thread_data_[thread_id_].active.store(false, std::memory_order_relaxed);
            
            // Clean up all remaining objects
            auto& data = thread_data_[thread_id_];
            for (auto& list : data.retired_lists) {
                for (T* ptr : list) {
                    delete ptr;
                }
                list.clear();
            }
            
            initialized_ = false;
        }
    }
};

// Static member definitions
template<typename T>
std::atomic<uint64_t> EpochManager<T>::global_epoch_{1};

template<typename T>
std::array<typename EpochManager<T>::ThreadData, EpochManager<T>::MAX_THREADS> 
    EpochManager<T>::thread_data_;

template<typename T>
thread_local int EpochManager<T>::thread_id_ = -1;

template<typename T>
thread_local bool EpochManager<T>::initialized_ = false;

template<typename T>
std::atomic<int> EpochManager<T>::next_thread_id_{0};

} // namespace memory
} // namespace abyssbook