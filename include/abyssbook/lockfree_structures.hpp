#pragma once

#include "common.hpp"
#include "thread_safe_random.hpp"
#include "memory_reclamation.hpp"
#include <atomic>
#include <memory>
#include <array>

namespace abyssbook {
namespace lockfree {

// Atomic price level for lock-free operations
struct AtomicPriceLevel {
    std::atomic<Amount> total_volume;
    std::atomic<std::size_t> order_count;
    
    AtomicPriceLevel() : total_volume(0), order_count(0) {}
    
    AtomicPriceLevel(Amount volume, std::size_t count) 
        : total_volume(volume), order_count(count) {}
    
    // Atomic operations
    HOT FORCE_INLINE void addOrder(Amount amount) noexcept {
        total_volume.fetch_add(amount, std::memory_order_relaxed);
        order_count.fetch_add(1, std::memory_order_relaxed);
    }
    
    HOT FORCE_INLINE void removeOrder(Amount amount) noexcept {
        // Use compare-and-swap for safe subtraction
        Amount current = total_volume.load(std::memory_order_relaxed);
        Amount new_volume;
        do {
            new_volume = (amount >= current) ? 0 : current - amount;
        } while (!total_volume.compare_exchange_weak(current, new_volume, 
                                                   std::memory_order_relaxed));
        
        // Decrement order count safely
        std::size_t current_count = order_count.load(std::memory_order_relaxed);
        std::size_t new_count;
        do {
            new_count = (current_count > 0) ? current_count - 1 : 0;
        } while (!order_count.compare_exchange_weak(current_count, new_count,
                                                  std::memory_order_relaxed));
    }
    
    HOT FORCE_INLINE bool isEmpty() const noexcept {
        return order_count.load(std::memory_order_relaxed) == 0 || 
               total_volume.load(std::memory_order_relaxed) == 0;
    }
    
    HOT FORCE_INLINE Amount getVolume() const noexcept {
        return total_volume.load(std::memory_order_relaxed);
    }
    
    HOT FORCE_INLINE std::size_t getOrderCount() const noexcept {
        return order_count.load(std::memory_order_relaxed);
    }
};

// Lock-free skip list node for price levels
template<int MAX_LEVEL = 16>
struct CACHE_ALIGNED SkipListNode {
    std::atomic<Price> price;
    AtomicPriceLevel level;
    std::atomic<bool> marked_for_deletion;
    
    // Array of atomic pointers to next nodes at each level
    std::array<std::atomic<SkipListNode*>, MAX_LEVEL> forward;
    const int node_level;
    
    SkipListNode(Price p, Amount volume, std::size_t count, int level) 
        : price(p), level(volume, count), marked_for_deletion(false), node_level(level) {
        for (auto& ptr : forward) {
            ptr.store(nullptr, std::memory_order_relaxed);
        }
    }
    
    HOT FORCE_INLINE bool isMarkedForDeletion() const noexcept {
        return marked_for_deletion.load(std::memory_order_acquire);
    }
    
    HOT FORCE_INLINE void markForDeletion() noexcept {
        marked_for_deletion.store(true, std::memory_order_release);
    }
};

// Lock-free skip list for price levels with cached best prices
template<int MAX_LEVEL = 16>
class LockFreeSkipList {
private:
    using Node = SkipListNode<MAX_LEVEL>;
    
    Node* head_;
    Node* tail_;
    std::atomic<int> current_level_;
    std::atomic<std::size_t> size_;
    
    // Cached best prices for O(1) retrieval
    mutable std::atomic<Price> cached_best_bid_{0};
    mutable std::atomic<Price> cached_best_ask_{UINT64_MAX};
    mutable std::atomic<bool> cache_valid_{false};
    
    // Random level generation for skip list
    HOT int randomLevel() const noexcept {
        int level = 1;
        while (random::FastRNG::fastRandomBit() && level < MAX_LEVEL) {
            level++;
        }
        return level;
    }
    
    // Find node with given price and return predecessors and successors
    bool find(Price price, Node** predecessors, Node** successors) const {
        Node* current = head_;
        
        for (int level = current_level_.load(std::memory_order_relaxed) - 1; level >= 0; level--) {
            Node* next = current->forward[level].load(std::memory_order_acquire);
            
            while (next != tail_ && next->price.load(std::memory_order_relaxed) < price) {
                current = next;
                next = current->forward[level].load(std::memory_order_acquire);
            }
            
            if (predecessors) predecessors[level] = current;
            if (successors) successors[level] = next;
        }
        
        return (successors && successors[0] != tail_ && 
                successors[0]->price.load(std::memory_order_relaxed) == price);
    }
    
public:
    LockFreeSkipList() : current_level_(1), size_(0), 
                        cached_best_bid_(0), cached_best_ask_(UINT64_MAX), cache_valid_(false) {
        // Create sentinel nodes
        head_ = new Node(0, 0, 0, MAX_LEVEL);
        tail_ = new Node(UINT64_MAX, 0, 0, MAX_LEVEL);
        
        for (int i = 0; i < MAX_LEVEL; i++) {
            head_->forward[i].store(tail_, std::memory_order_relaxed);
        }
    }
    
    ~LockFreeSkipList() {
        // Clean up all nodes
        Node* current = head_;
        while (current != nullptr) {
            Node* next = current->forward[0].load(std::memory_order_relaxed);
            delete current;
            current = next;
        }
    }
    
    // Insert or update price level
    HOT bool insertOrUpdate(Price price, std::int64_t volume_delta, std::int64_t count_delta) {
        Node* predecessors[MAX_LEVEL];
        Node* successors[MAX_LEVEL];
        
        while (true) {
            bool found = find(price, predecessors, successors);
            
            if (found && !successors[0]->isMarkedForDeletion()) {
                // Update existing node
                if (volume_delta > 0) {
                    successors[0]->level.addOrder(static_cast<Amount>(volume_delta));
                } else if (volume_delta < 0) {
                    successors[0]->level.removeOrder(static_cast<Amount>(-volume_delta));
                }
                // Invalidate cache on any update
                cache_valid_.store(false, std::memory_order_relaxed);
                return true;
            }
            
            if (!found) {
                // Create new node
                int new_level = randomLevel();
                Node* new_node = new Node(price, 
                                        volume_delta > 0 ? static_cast<Amount>(volume_delta) : 0,
                                        count_delta > 0 ? static_cast<std::size_t>(count_delta) : 0,
                                        new_level);
                
                // Update current level if needed
                int current_max_level = current_level_.load(std::memory_order_relaxed);
                if (new_level > current_max_level) {
                    for (int i = current_max_level; i < new_level; i++) {
                        predecessors[i] = head_;
                        successors[i] = tail_;
                    }
                    current_level_.store(new_level, std::memory_order_relaxed);
                }
                
                // Set up forward pointers
                for (int i = 0; i < new_level; i++) {
                    new_node->forward[i].store(successors[i], std::memory_order_relaxed);
                }
                
                // Link new node atomically
                bool success = true;
                for (int i = 0; i < new_level; i++) {
                    if (!predecessors[i]->forward[i].compare_exchange_weak(
                            successors[i], new_node, std::memory_order_release)) {
                        success = false;
                        break;
                    }
                }
                
                if (success) {
                    size_.fetch_add(1, std::memory_order_relaxed);
                    // Invalidate cache on successful insert
                    cache_valid_.store(false, std::memory_order_relaxed);
                    return true;
                } else {
                    delete new_node;
                    continue; // Retry
                }
            }
        }
        return false;
    }
    
    // Find price level
    HOT std::optional<std::pair<Amount, std::size_t>> find(Price price) const {
        Node* predecessors[MAX_LEVEL];
        Node* successors[MAX_LEVEL];
        
        if (find(price, predecessors, successors) && !successors[0]->isMarkedForDeletion()) {
            return std::make_pair(successors[0]->level.getVolume(),
                                successors[0]->level.getOrderCount());
        }
        return std::nullopt;
    }
    
    // Update best price cache - called after insert/remove operations
    HOT FORCE_INLINE void updateBestPriceCache() const noexcept {
        cache_valid_.store(false, std::memory_order_release);
        
        Price best_bid = 0;
        Price best_ask = UINT64_MAX;
        
        // Single traversal to find both best bid and ask
        Node* current = head_->forward[0].load(std::memory_order_acquire);
        while (current != tail_) {
            if (!current->isMarkedForDeletion() && !current->level.isEmpty()) {
                Price price = current->price.load(std::memory_order_relaxed);
                if (price > best_bid) best_bid = price;  // Higher price for bid
                if (price < best_ask) best_ask = price;  // Lower price for ask
            }
            current = current->forward[0].load(std::memory_order_acquire);
        }
        
        cached_best_bid_.store(best_bid, std::memory_order_relaxed);
        cached_best_ask_.store(best_ask == UINT64_MAX ? 0 : best_ask, std::memory_order_relaxed);
        cache_valid_.store(true, std::memory_order_release);
    }
    
    // Get best price (for bid or ask side) - O(1) with cache
    HOT std::optional<Price> getBestPrice(bool is_bid) const {
        // Fast path: use cache if valid
        if (cache_valid_.load(std::memory_order_acquire)) {
            Price cached_price = is_bid ? 
                cached_best_bid_.load(std::memory_order_relaxed) :
                cached_best_ask_.load(std::memory_order_relaxed);
            return cached_price > 0 ? std::optional<Price>(cached_price) : std::nullopt;
        }
        
        // Slow path: refresh cache and retry
        updateBestPriceCache();
        Price cached_price = is_bid ? 
            cached_best_bid_.load(std::memory_order_relaxed) :
            cached_best_ask_.load(std::memory_order_relaxed);
        return cached_price > 0 ? std::optional<Price>(cached_price) : std::nullopt;
    }
    
    // Get size
    HOT std::size_t size() const noexcept {
        return size_.load(std::memory_order_relaxed);
    }
    
    // Check if empty
    HOT bool empty() const noexcept {
        return size() == 0;
    }
};

// Lock-free hash map for fast price level lookup
template<std::size_t BUCKET_COUNT = 1024>
class LockFreeHashMap {
private:
    struct CACHE_ALIGNED HashNode {
        std::atomic<Price> price;
        AtomicPriceLevel level;
        std::atomic<HashNode*> next;
        std::atomic<bool> marked_for_deletion;
        
        HashNode(Price p, Amount volume, std::size_t count) 
            : price(p), level(volume, count), next(nullptr), marked_for_deletion(false) {}
    };
    
    std::array<std::atomic<HashNode*>, BUCKET_COUNT> buckets_;
    
    HOT std::size_t hash(Price price) const noexcept {
        // Use Fibonacci hashing for better distribution
        constexpr std::uint64_t golden_ratio = 11400714819323198485ULL;
        return (price * golden_ratio) >> (64 - __builtin_ctzll(BUCKET_COUNT));
    }
    
public:
    LockFreeHashMap() {
        for (auto& bucket : buckets_) {
            bucket.store(nullptr, std::memory_order_relaxed);
        }
    }
    
    ~LockFreeHashMap() {
        for (auto& bucket : buckets_) {
            HashNode* current = bucket.load(std::memory_order_relaxed);
            while (current) {
                HashNode* next = current->next.load(std::memory_order_relaxed);
                delete current;
                current = next;
            }
        }
    }
    
    // Insert or update
    HOT bool insertOrUpdate(Price price, std::int64_t volume_delta, std::int64_t count_delta) {
        std::size_t bucket_idx = hash(price);
        HashNode* head = buckets_[bucket_idx].load(std::memory_order_acquire);
        
        // Try to find existing node
        HashNode* current = head;
        while (current) {
            if (current->price.load(std::memory_order_relaxed) == price && 
                !current->marked_for_deletion.load(std::memory_order_relaxed)) {
                // Update existing
                if (volume_delta > 0) {
                    current->level.addOrder(static_cast<Amount>(volume_delta));
                } else if (volume_delta < 0) {
                    current->level.removeOrder(static_cast<Amount>(-volume_delta));
                }
                return true;
            }
            current = current->next.load(std::memory_order_acquire);
        }
        
        // Create new node
        HashNode* new_node = new HashNode(price, 
                                        volume_delta > 0 ? static_cast<Amount>(volume_delta) : 0,
                                        count_delta > 0 ? static_cast<std::size_t>(count_delta) : 0);
        
        // Insert at head of bucket
        do {
            head = buckets_[bucket_idx].load(std::memory_order_acquire);
            new_node->next.store(head, std::memory_order_relaxed);
        } while (!buckets_[bucket_idx].compare_exchange_weak(head, new_node, 
                                                           std::memory_order_release));
        
        return true;
    }
    
    // Find price level
    HOT std::optional<std::pair<Amount, std::size_t>> find(Price price) const {
        std::size_t bucket_idx = hash(price);
        HashNode* current = buckets_[bucket_idx].load(std::memory_order_acquire);
        
        while (current) {
            if (current->price.load(std::memory_order_relaxed) == price &&
                !current->marked_for_deletion.load(std::memory_order_relaxed)) {
                return std::make_pair(current->level.getVolume(),
                                    current->level.getOrderCount());
            }
            current = current->next.load(std::memory_order_acquire);
        }
        return std::nullopt;
    }
};

} // namespace lockfree
} // namespace abyssbook