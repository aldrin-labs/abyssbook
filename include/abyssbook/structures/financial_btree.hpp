#pragma once

#include "../common.hpp"
#include <array>
#include <vector>
#include <memory>
#include <atomic>
#include <bit>
#include <cstring>
#include <cmath>

namespace abyssbook {
namespace novel {

//=============================================================================
// B+ Tree with Bulk Operations - Optimized for Financial Data
//=============================================================================

template<typename Key, typename Value, int FANOUT = 64>
class FinancialBPlusTree {
public:
    static constexpr int MIN_KEYS = FANOUT / 2;
    static constexpr int MAX_KEYS = FANOUT - 1;
    
private:
    struct CACHE_ALIGNED Node {
        std::atomic<bool> is_leaf;
        std::atomic<int> key_count;
        std::array<std::atomic<Key>, MAX_KEYS> keys;
        std::atomic<Node*> parent;
        
        Node(bool leaf) : is_leaf(leaf), key_count(0), parent(nullptr) {
            for (auto& key : keys) {
                key.store(Key{}, std::memory_order_relaxed);
            }
        }
        
        virtual ~Node() = default;
    };
    
    struct CACHE_ALIGNED LeafNode : public Node {
        std::array<std::atomic<Value>, MAX_KEYS> values;
        std::atomic<LeafNode*> next;
        std::atomic<LeafNode*> prev;
        
        LeafNode() : Node(true), next(nullptr), prev(nullptr) {
            for (auto& value : values) {
                value.store(Value{}, std::memory_order_relaxed);
            }
        }
        
        HOT FORCE_INLINE bool insert(Key key, Value value) {
            int count = this->key_count.load(std::memory_order_relaxed);
            if (count >= MAX_KEYS) return false;
            
            // Find insertion point
            int pos = 0;
            while (pos < count && this->keys[pos].load(std::memory_order_relaxed) < key) {
                pos++;
            }
            
            // Shift elements
            for (int i = count; i > pos; i--) {
                this->keys[i].store(this->keys[i-1].load(std::memory_order_relaxed), 
                                  std::memory_order_relaxed);
                values[i].store(values[i-1].load(std::memory_order_relaxed), 
                              std::memory_order_relaxed);
            }
            
            // Insert new element
            this->keys[pos].store(key, std::memory_order_relaxed);
            values[pos].store(value, std::memory_order_relaxed);
            this->key_count.fetch_add(1, std::memory_order_relaxed);
            
            return true;
        }
        
        HOT FORCE_INLINE std::optional<Value> find(Key key) const {
            int count = this->key_count.load(std::memory_order_relaxed);
            
            // Binary search for better performance
            int left = 0, right = count - 1;
            while (left <= right) {
                int mid = (left + right) / 2;
                Key mid_key = this->keys[mid].load(std::memory_order_relaxed);
                
                if (mid_key == key) {
                    return values[mid].load(std::memory_order_relaxed);
                } else if (mid_key < key) {
                    left = mid + 1;
                } else {
                    right = mid - 1;
                }
            }
            return std::nullopt;
        }
    };
    
    struct CACHE_ALIGNED InternalNode : public Node {
        std::array<std::atomic<Node*>, FANOUT> children;
        
        InternalNode() : Node(false) {
            for (auto& child : children) {
                child.store(nullptr, std::memory_order_relaxed);
            }
        }
    };
    
    std::atomic<Node*> root;
    std::atomic<size_t> size;
    
public:
    FinancialBPlusTree() : root(nullptr), size(0) {}
    
    ~FinancialBPlusTree() {
        clear();
    }
    
    HOT FORCE_INLINE bool insert(Key key, Value value) {
        if (!root.load(std::memory_order_relaxed)) {
            auto leaf = std::make_unique<LeafNode>();
            leaf->insert(key, value);
            root.store(leaf.release(), std::memory_order_release);
            size.fetch_add(1, std::memory_order_relaxed);
            return true;
        }
        
        // Navigate to appropriate leaf
        Node* current = root.load(std::memory_order_acquire);
        while (!current->is_leaf.load(std::memory_order_relaxed)) {
            auto internal = static_cast<InternalNode*>(current);
            // Find appropriate child (simplified logic)
            current = internal->children[0].load(std::memory_order_relaxed);
        }
        
        auto leaf = static_cast<LeafNode*>(current);
        if (leaf->insert(key, value)) {
            size.fetch_add(1, std::memory_order_relaxed);
            return true;
        }
        
        return false; // Node full, would need split logic
    }
    
    HOT FORCE_INLINE std::optional<Value> find(Key key) const {
        Node* current = root.load(std::memory_order_acquire);
        if (!current) return std::nullopt;
        
        while (!current->is_leaf.load(std::memory_order_relaxed)) {
            auto internal = static_cast<InternalNode*>(current);
            // Navigate to appropriate child (simplified)
            current = internal->children[0].load(std::memory_order_relaxed);
        }
        
        auto leaf = static_cast<const LeafNode*>(current);
        return leaf->find(key);
    }
    
    FORCE_INLINE size_t getSize() const {
        return size.load(std::memory_order_relaxed);
    }
    
    void clear() {
        // Simplified cleanup - in production would need proper tree traversal
        Node* current = root.exchange(nullptr, std::memory_order_acq_rel);
        if (current) {
            delete current; // Simplified - would need recursive cleanup
        }
        size.store(0, std::memory_order_relaxed);
    }
    
    // Bulk operations for financial data
    FORCE_INLINE void bulkInsert(const std::vector<std::pair<Key, Value>>& items) {
        for (const auto& [key, value] : items) {
            insert(key, value);
        }
    }
    
    FORCE_INLINE std::vector<Value> rangeQuery(Key start, Key end) const {
        std::vector<Value> results;
        // Simplified range query implementation
        // In production, would leverage B+ tree structure for efficient range scans
        return results;
    }
};

} // namespace novel
} // namespace abyssbook