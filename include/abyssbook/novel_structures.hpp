#pragma once

#include "common.hpp"
#include <array>
#include <vector>
#include <memory>
#include <atomic>
#include <bit>
#include <cstring>

namespace abyssbook {
namespace novel {

//=============================================================================
// 1. B+ Tree with Bulk Operations - Optimized for Financial Data
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
    
    std::atomic<Node*> root_;
    std::atomic<LeafNode*> first_leaf_;
    std::atomic<std::size_t> size_;
    
public:
    FinancialBPlusTree() : root_(new LeafNode()), first_leaf_(static_cast<LeafNode*>(root_.load())), size_(0) {}
    
    ~FinancialBPlusTree() {
        // Cleanup implementation
    }
    
    HOT bool insert(Key key, Value value) {
        Node* root = root_.load(std::memory_order_acquire);
        if (root->is_leaf.load(std::memory_order_relaxed)) {
            LeafNode* leaf = static_cast<LeafNode*>(root);
            if (leaf->insert(key, value)) {
                size_.fetch_add(1, std::memory_order_relaxed);
                return true;
            }
        }
        return false; // Simplified for now
    }
    
    HOT std::optional<Value> find(Key key) const {
        Node* current = root_.load(std::memory_order_acquire);
        
        while (!current->is_leaf.load(std::memory_order_relaxed)) {
            // Traverse internal nodes
            InternalNode* internal = static_cast<InternalNode*>(current);
            int key_count = internal->key_count.load(std::memory_order_relaxed);
            
            int pos = 0;
            while (pos < key_count && internal->keys[pos].load(std::memory_order_relaxed) <= key) {
                pos++;
            }
            
            current = internal->children[pos].load(std::memory_order_acquire);
        }
        
        // Search in leaf
        LeafNode* leaf = static_cast<LeafNode*>(current);
        return leaf->find(key);
    }
    
    // Bulk insert for better performance
    HOT void bulkInsert(const std::vector<std::pair<Key, Value>>& data) {
        // Sort data first for optimal insertion
        auto sorted_data = data;
        std::sort(sorted_data.begin(), sorted_data.end());
        
        for (const auto& [key, value] : sorted_data) {
            insert(key, value);
        }
    }
    
    std::size_t size() const { return size_.load(std::memory_order_relaxed); }
};

//=============================================================================
// 2. Van Emde Boas Tree for Ultra-Fast Integer Operations
//=============================================================================

template<int UNIVERSE_BITS = 16>
class VanEmdeBoas {
private:
    static constexpr std::size_t UNIVERSE_SIZE = 1ULL << UNIVERSE_BITS;
    static constexpr std::size_t CLUSTER_SIZE = 1ULL << (UNIVERSE_BITS / 2);
    static constexpr std::size_t CLUSTER_COUNT = CLUSTER_SIZE;
    
    struct VEBNode {
        std::atomic<bool> has_min;
        std::atomic<bool> has_max;
        std::atomic<std::uint32_t> min_val;
        std::atomic<std::uint32_t> max_val;
        
        std::unique_ptr<VEBNode> summary;
        std::vector<std::unique_ptr<VEBNode>> clusters;
        
        VEBNode() : has_min(false), has_max(false), min_val(0), max_val(0) {
            if (UNIVERSE_BITS > 1) {
                summary = std::make_unique<VEBNode>();
                clusters.resize(CLUSTER_COUNT);
                for (auto& cluster : clusters) {
                    cluster = std::make_unique<VEBNode>();
                }
            }
        }
    };
    
    std::unique_ptr<VEBNode> root_;
    
    HOT std::uint32_t high(std::uint32_t x) const {
        return x >> (UNIVERSE_BITS / 2);
    }
    
    HOT std::uint32_t low(std::uint32_t x) const {
        return x & ((1ULL << (UNIVERSE_BITS / 2)) - 1);
    }
    
    HOT std::uint32_t index(std::uint32_t high, std::uint32_t low) const {
        return (high << (UNIVERSE_BITS / 2)) | low;
    }
    
public:
    VanEmdeBoas() : root_(std::make_unique<VEBNode>()) {}
    
    HOT void insert(std::uint32_t x) {
        if (!root_->has_min.load(std::memory_order_relaxed)) {
            root_->min_val.store(x, std::memory_order_relaxed);
            root_->max_val.store(x, std::memory_order_relaxed);
            root_->has_min.store(true, std::memory_order_release);
            root_->has_max.store(true, std::memory_order_release);
            return;
        }
        
        std::uint32_t min_val = root_->min_val.load(std::memory_order_relaxed);
        std::uint32_t max_val = root_->max_val.load(std::memory_order_relaxed);
        
        if (x < min_val) {
            std::swap(x, min_val);
            root_->min_val.store(min_val, std::memory_order_relaxed);
        }
        
        if (x > max_val) {
            root_->max_val.store(x, std::memory_order_relaxed);
        }
        
        if (UNIVERSE_BITS > 1 && x != min_val) {
            std::uint32_t h = high(x);
            std::uint32_t l = low(x);
            
            if (!root_->clusters[h] || !root_->clusters[h]->has_min.load(std::memory_order_relaxed)) {
                // Insert into summary
                insertRecursive(root_->summary.get(), h);
            }
            
            insertRecursive(root_->clusters[h].get(), l);
        }
    }
    
    HOT bool member(std::uint32_t x) const {
        if (!root_->has_min.load(std::memory_order_relaxed)) {
            return false;
        }
        
        std::uint32_t min_val = root_->min_val.load(std::memory_order_relaxed);
        std::uint32_t max_val = root_->max_val.load(std::memory_order_relaxed);
        
        if (x == min_val || x == max_val) {
            return true;
        }
        
        if (UNIVERSE_BITS == 1) {
            return false;
        }
        
        std::uint32_t h = high(x);
        std::uint32_t l = low(x);
        
        return root_->clusters[h] && memberRecursive(root_->clusters[h].get(), l);
    }
    
    HOT std::optional<std::uint32_t> successor(std::uint32_t x) const {
        if (!root_->has_min.load(std::memory_order_relaxed)) {
            return std::nullopt;
        }
        
        std::uint32_t min_val = root_->min_val.load(std::memory_order_relaxed);
        std::uint32_t max_val = root_->max_val.load(std::memory_order_relaxed);
        
        if (x < min_val) {
            return min_val;
        }
        
        if (x >= max_val) {
            return std::nullopt;
        }
        
        if (UNIVERSE_BITS == 1) {
            return max_val;
        }
        
        std::uint32_t h = high(x);
        std::uint32_t l = low(x);
        
        if (root_->clusters[h] && root_->clusters[h]->has_max.load(std::memory_order_relaxed) &&
            l < root_->clusters[h]->max_val.load(std::memory_order_relaxed)) {
            
            auto succ_low = successorRecursive(root_->clusters[h].get(), l);
            if (succ_low) {
                return index(h, *succ_low);
            }
        }
        
        auto succ_cluster = successorRecursive(root_->summary.get(), h);
        if (succ_cluster && root_->clusters[*succ_cluster]) {
            std::uint32_t succ_low = root_->clusters[*succ_cluster]->min_val.load(std::memory_order_relaxed);
            return index(*succ_cluster, succ_low);
        }
        
        return std::nullopt;
    }
    
private:
    void insertRecursive(VEBNode* node, std::uint32_t x) {
        // Recursive implementation
        if (!node->has_min.load(std::memory_order_relaxed)) {
            node->min_val.store(x, std::memory_order_relaxed);
            node->max_val.store(x, std::memory_order_relaxed);
            node->has_min.store(true, std::memory_order_release);
            node->has_max.store(true, std::memory_order_release);
        }
        // Additional logic for recursive insertion
    }
    
    bool memberRecursive(VEBNode* node, std::uint32_t x) const {
        if (!node || !node->has_min.load(std::memory_order_relaxed)) {
            return false;
        }
        
        return x == node->min_val.load(std::memory_order_relaxed) || 
               x == node->max_val.load(std::memory_order_relaxed);
        // Additional logic for recursive search
    }
    
    std::optional<std::uint32_t> successorRecursive(VEBNode* node, std::uint32_t x) const {
        // Recursive successor implementation
        if (!node || !node->has_min.load(std::memory_order_relaxed)) {
            return std::nullopt;
        }
        
        std::uint32_t min_val = node->min_val.load(std::memory_order_relaxed);
        std::uint32_t max_val = node->max_val.load(std::memory_order_relaxed);
        
        if (x < min_val) return min_val;
        if (x >= max_val) return std::nullopt;
        
        return max_val;
    }
};

//=============================================================================
// 3. Adaptive Splay Tree for Hot Data
//=============================================================================

template<typename Key, typename Value>
class AdaptiveSplayTree {
private:
    struct CACHE_ALIGNED Node {
        Key key;
        Value value;
        std::atomic<Node*> left;
        std::atomic<Node*> right;
        std::atomic<Node*> parent;
        std::atomic<std::uint64_t> access_count;
        
        Node(Key k, Value v) : key(k), value(v), left(nullptr), right(nullptr), 
                              parent(nullptr), access_count(1) {}
    };
    
    std::atomic<Node*> root_;
    std::atomic<std::size_t> size_;
    
    HOT void splay(Node* x) {
        while (x && x->parent.load(std::memory_order_relaxed)) {
            Node* p = x->parent.load(std::memory_order_relaxed);
            Node* g = p ? p->parent.load(std::memory_order_relaxed) : nullptr;
            
            if (!g) {
                // Zig step
                if (p->left.load(std::memory_order_relaxed) == x) {
                    rotateRight(p);
                } else {
                    rotateLeft(p);
                }
            } else if ((g->left.load(std::memory_order_relaxed) == p) == 
                      (p->left.load(std::memory_order_relaxed) == x)) {
                // Zig-zig step
                if (p->left.load(std::memory_order_relaxed) == x) {
                    rotateRight(g);
                    rotateRight(p);
                } else {
                    rotateLeft(g);
                    rotateLeft(p);
                }
            } else {
                // Zig-zag step
                if (p->left.load(std::memory_order_relaxed) == x) {
                    rotateRight(p);
                    rotateLeft(g);
                } else {
                    rotateLeft(p);
                    rotateRight(g);
                }
            }
        }
        
        root_.store(x, std::memory_order_release);
    }
    
    HOT void rotateLeft(Node* x) {
        Node* y = x->right.load(std::memory_order_relaxed);
        if (!y) return;
        
        x->right.store(y->left.load(std::memory_order_relaxed), std::memory_order_relaxed);
        if (y->left.load(std::memory_order_relaxed)) {
            y->left.load(std::memory_order_relaxed)->parent.store(x, std::memory_order_relaxed);
        }
        
        y->parent.store(x->parent.load(std::memory_order_relaxed), std::memory_order_relaxed);
        if (!x->parent.load(std::memory_order_relaxed)) {
            root_.store(y, std::memory_order_relaxed);
        } else if (x == x->parent.load(std::memory_order_relaxed)->left.load(std::memory_order_relaxed)) {
            x->parent.load(std::memory_order_relaxed)->left.store(y, std::memory_order_relaxed);
        } else {
            x->parent.load(std::memory_order_relaxed)->right.store(y, std::memory_order_relaxed);
        }
        
        y->left.store(x, std::memory_order_relaxed);
        x->parent.store(y, std::memory_order_relaxed);
    }
    
    HOT void rotateRight(Node* x) {
        Node* y = x->left.load(std::memory_order_relaxed);
        if (!y) return;
        
        x->left.store(y->right.load(std::memory_order_relaxed), std::memory_order_relaxed);
        if (y->right.load(std::memory_order_relaxed)) {
            y->right.load(std::memory_order_relaxed)->parent.store(x, std::memory_order_relaxed);
        }
        
        y->parent.store(x->parent.load(std::memory_order_relaxed), std::memory_order_relaxed);
        if (!x->parent.load(std::memory_order_relaxed)) {
            root_.store(y, std::memory_order_relaxed);
        } else if (x == x->parent.load(std::memory_order_relaxed)->right.load(std::memory_order_relaxed)) {
            x->parent.load(std::memory_order_relaxed)->right.store(y, std::memory_order_relaxed);
        } else {
            x->parent.load(std::memory_order_relaxed)->left.store(y, std::memory_order_relaxed);
        }
        
        y->right.store(x, std::memory_order_relaxed);
        x->parent.store(y, std::memory_order_relaxed);
    }
    
public:
    AdaptiveSplayTree() : root_(nullptr), size_(0) {}
    
    HOT bool insert(Key key, Value value) {
        if (!root_.load(std::memory_order_relaxed)) {
            root_.store(new Node(key, value), std::memory_order_release);
            size_.fetch_add(1, std::memory_order_relaxed);
            return true;
        }
        
        Node* current = root_.load(std::memory_order_acquire);
        Node* parent = nullptr;
        
        while (current) {
            parent = current;
            if (key < current->key) {
                current = current->left.load(std::memory_order_relaxed);
            } else if (key > current->key) {
                current = current->right.load(std::memory_order_relaxed);
            } else {
                // Update existing
                current->value = value;
                current->access_count.fetch_add(1, std::memory_order_relaxed);
                splay(current);
                return true;
            }
        }
        
        Node* new_node = new Node(key, value);
        new_node->parent.store(parent, std::memory_order_relaxed);
        
        if (key < parent->key) {
            parent->left.store(new_node, std::memory_order_relaxed);
        } else {
            parent->right.store(new_node, std::memory_order_relaxed);
        }
        
        splay(new_node);
        size_.fetch_add(1, std::memory_order_relaxed);
        return true;
    }
    
    HOT std::optional<Value> find(Key key) {
        Node* current = root_.load(std::memory_order_acquire);
        
        while (current) {
            if (key == current->key) {
                current->access_count.fetch_add(1, std::memory_order_relaxed);
                splay(current);
                return current->value;
            } else if (key < current->key) {
                current = current->left.load(std::memory_order_relaxed);
            } else {
                current = current->right.load(std::memory_order_relaxed);
            }
        }
        
        return std::nullopt;
    }
    
    std::size_t size() const { return size_.load(std::memory_order_relaxed); }
};

//=============================================================================
// 4. Concurrent Radix Tree for Pattern-Based Lookups
//=============================================================================

template<typename Value, int RADIX = 256>
class ConcurrentRadixTree {
private:
    struct CACHE_ALIGNED TrieNode {
        std::array<std::atomic<TrieNode*>, RADIX> children;
        std::atomic<Value*> value;
        std::atomic<bool> is_end;
        
        TrieNode() : value(nullptr), is_end(false) {
            for (auto& child : children) {
                child.store(nullptr, std::memory_order_relaxed);
            }
        }
        
        ~TrieNode() {
            Value* val = value.load(std::memory_order_relaxed);
            if (val) delete val;
        }
    };
    
    std::atomic<TrieNode*> root_;
    
public:
    ConcurrentRadixTree() : root_(new TrieNode()) {}
    
    HOT bool insert(const std::vector<std::uint8_t>& key, Value value) {
        TrieNode* current = root_.load(std::memory_order_acquire);
        
        for (std::uint8_t byte : key) {
            TrieNode* next = current->children[byte].load(std::memory_order_acquire);
            if (!next) {
                TrieNode* new_node = new TrieNode();
                if (current->children[byte].compare_exchange_strong(next, new_node, 
                                                                  std::memory_order_release)) {
                    next = new_node;
                } else {
                    delete new_node;
                    next = current->children[byte].load(std::memory_order_acquire);
                }
            }
            current = next;
        }
        
        Value* new_value = new Value(value);
        Value* expected = nullptr;
        if (current->value.compare_exchange_strong(expected, new_value, std::memory_order_release)) {
            current->is_end.store(true, std::memory_order_release);
            return true;
        } else {
            delete new_value;
            // Update existing value
            *expected = value;
            return true;
        }
    }
    
    HOT std::optional<Value> find(const std::vector<std::uint8_t>& key) const {
        TrieNode* current = root_.load(std::memory_order_acquire);
        
        for (std::uint8_t byte : key) {
            current = current->children[byte].load(std::memory_order_acquire);
            if (!current) return std::nullopt;
        }
        
        if (current->is_end.load(std::memory_order_acquire)) {
            Value* val = current->value.load(std::memory_order_acquire);
            return val ? std::optional<Value>(*val) : std::nullopt;
        }
        
        return std::nullopt;
    }
    
    // Convert price to byte vector for trie lookup
    static std::vector<std::uint8_t> priceToBytes(Price price) {
        std::vector<std::uint8_t> bytes(sizeof(Price));
        std::memcpy(bytes.data(), &price, sizeof(Price));
        return bytes;
    }
};

//=============================================================================
// 5. Segment Tree for Range Queries
//=============================================================================

template<typename T, T IDENTITY = T{}>
class ConcurrentSegmentTree {
private:
    struct CACHE_ALIGNED Node {
        std::atomic<T> value;
        std::atomic<T> lazy;
        std::atomic<bool> has_lazy;
        
        Node() : value(IDENTITY), lazy(IDENTITY), has_lazy(false) {}
        
        // Make it movable for std::vector
        Node(Node&& other) noexcept 
            : value(other.value.load()), 
              lazy(other.lazy.load()),
              has_lazy(other.has_lazy.load()) {}
        
        Node& operator=(Node&& other) noexcept {
            if (this != &other) {
                value.store(other.value.load());
                lazy.store(other.lazy.load());
                has_lazy.store(other.has_lazy.load());
            }
            return *this;
        }
        
        // Delete copy operations for atomics
        Node(const Node&) = delete;
        Node& operator=(const Node&) = delete;
    };
    
    std::vector<Node> tree_;
    std::size_t size_;
    
    void push(std::size_t node, std::size_t start, std::size_t end) {
        if (tree_[node].has_lazy.load(std::memory_order_relaxed)) {
            T lazy_val = tree_[node].lazy.load(std::memory_order_relaxed);
            tree_[node].value.fetch_add(lazy_val, std::memory_order_relaxed);
            
            if (start != end) {
                tree_[2*node].lazy.fetch_add(lazy_val, std::memory_order_relaxed);
                tree_[2*node].has_lazy.store(true, std::memory_order_relaxed);
                tree_[2*node+1].lazy.fetch_add(lazy_val, std::memory_order_relaxed);
                tree_[2*node+1].has_lazy.store(true, std::memory_order_relaxed);
            }
            
            tree_[node].lazy.store(IDENTITY, std::memory_order_relaxed);
            tree_[node].has_lazy.store(false, std::memory_order_relaxed);
        }
    }
    
public:
    explicit ConcurrentSegmentTree(std::size_t n) : size_(n) {
        tree_.resize(4 * n);
    }
    
    HOT void update(std::size_t left, std::size_t right, T value) {
        updateRange(1, 0, size_ - 1, left, right, value);
    }
    
    HOT T query(std::size_t left, std::size_t right) {
        return queryRange(1, 0, size_ - 1, left, right);
    }
    
private:
    void updateRange(std::size_t node, std::size_t start, std::size_t end,
                    std::size_t left, std::size_t right, T value) {
        push(node, start, end);
        
        if (start > right || end < left) return;
        
        if (start >= left && end <= right) {
            tree_[node].lazy.fetch_add(value, std::memory_order_relaxed);
            tree_[node].has_lazy.store(true, std::memory_order_relaxed);
            push(node, start, end);
            return;
        }
        
        std::size_t mid = (start + end) / 2;
        updateRange(2*node, start, mid, left, right, value);
        updateRange(2*node+1, mid+1, end, left, right, value);
        
        push(2*node, start, mid);
        push(2*node+1, mid+1, end);
        
        T left_val = tree_[2*node].value.load(std::memory_order_relaxed);
        T right_val = tree_[2*node+1].value.load(std::memory_order_relaxed);
        tree_[node].value.store(left_val + right_val, std::memory_order_relaxed);
    }
    
    T queryRange(std::size_t node, std::size_t start, std::size_t end,
                std::size_t left, std::size_t right) {
        if (start > right || end < left) return IDENTITY;
        
        push(node, start, end);
        
        if (start >= left && end <= right) {
            return tree_[node].value.load(std::memory_order_relaxed);
        }
        
        std::size_t mid = (start + end) / 2;
        T left_result = queryRange(2*node, start, mid, left, right);
        T right_result = queryRange(2*node+1, mid+1, end, left, right);
        
        return left_result + right_result;
    }
};

//=============================================================================
// 6. Order Book Pyramid - Specialized Hierarchical Structure
//=============================================================================

class OrderBookPyramid {
private:
    static constexpr int LEVELS = 8;
    static constexpr int BASE_BUCKET_SIZE = 1000;
    
    struct MarketSummary {
        Amount total_volume;
        std::size_t order_count;
        Price min_price;
        Price max_price;
    };
    
    struct CACHE_ALIGNED PyramidLevel {
        std::atomic<Amount> total_volume;
        std::atomic<std::size_t> order_count;
        std::atomic<Price> min_price;
        std::atomic<Price> max_price;
        
        PyramidLevel() : total_volume(0), order_count(0), min_price(UINT64_MAX), max_price(0) {}
        
        // Make it movable for std::vector
        PyramidLevel(PyramidLevel&& other) noexcept 
            : total_volume(other.total_volume.load()), 
              order_count(other.order_count.load()),
              min_price(other.min_price.load()),
              max_price(other.max_price.load()) {}
        
        PyramidLevel& operator=(PyramidLevel&& other) noexcept {
            if (this != &other) {
                total_volume.store(other.total_volume.load());
                order_count.store(other.order_count.load());
                min_price.store(other.min_price.load());
                max_price.store(other.max_price.load());
            }
            return *this;
        }
        
        // Delete copy operations for atomics
        PyramidLevel(const PyramidLevel&) = delete;
        PyramidLevel& operator=(const PyramidLevel&) = delete;
        
        HOT void addOrder(Price price, Amount amount) {
            total_volume.fetch_add(amount, std::memory_order_relaxed);
            order_count.fetch_add(1, std::memory_order_relaxed);
            
            // Update price range
            Price current_min = min_price.load(std::memory_order_relaxed);
            while (price < current_min && 
                   !min_price.compare_exchange_weak(current_min, price, std::memory_order_relaxed)) {
                current_min = min_price.load(std::memory_order_relaxed);
            }
            
            Price current_max = max_price.load(std::memory_order_relaxed);
            while (price > current_max && 
                   !max_price.compare_exchange_weak(current_max, price, std::memory_order_relaxed)) {
                current_max = max_price.load(std::memory_order_relaxed);
            }
        }
        
        HOT MarketSummary getSummary() const {
            return {
                total_volume.load(std::memory_order_relaxed),
                order_count.load(std::memory_order_relaxed),
                min_price.load(std::memory_order_relaxed),
                max_price.load(std::memory_order_relaxed)
            };
        }
    };
    
    std::array<std::vector<PyramidLevel>, LEVELS> pyramid_;
    std::atomic<Price> base_price_;
    std::atomic<Price> tick_size_;
    
    HOT std::size_t getBucket(Price price, int level) const {
        Price base = base_price_.load(std::memory_order_relaxed);
        Price tick = tick_size_.load(std::memory_order_relaxed);
        std::size_t bucket_size = BASE_BUCKET_SIZE << level;
        
        return (price >= base) ? (price - base) / (tick * bucket_size) : 0;
    }
    
public:
    OrderBookPyramid(Price base_price, Price tick_size) 
        : base_price_(base_price), tick_size_(tick_size) {
        
        for (int level = 0; level < LEVELS; level++) {
            std::size_t num_buckets = 1000 >> level; // Decreasing resolution
            pyramid_[level].resize(num_buckets);
        }
    }
    
    HOT void addOrder(Price price, Amount amount) {
        for (int level = 0; level < LEVELS; level++) {
            std::size_t bucket = getBucket(price, level);
            if (bucket < pyramid_[level].size()) {
                pyramid_[level][bucket].addOrder(price, amount);
            }
        }
    }
    
    HOT std::vector<MarketSummary> getMarketSummary(int detail_level = 0) const {
        std::vector<MarketSummary> summaries;
        
        if (detail_level < LEVELS) {
            for (const auto& level : pyramid_[detail_level]) {
                if (level.order_count.load(std::memory_order_relaxed) > 0) {
                    summaries.push_back(level.getSummary());
                }
            }
        }
        
        return summaries;
    }
    
    HOT Amount getVolumeInRange(Price min_price, Price max_price) const {
        Amount total_volume = 0;
        
        // Use appropriate pyramid level based on range size
        int best_level = 0;
        Price range = max_price - min_price;
        Price tick = tick_size_.load(std::memory_order_relaxed);
        
        while (best_level < LEVELS - 1 && range > (BASE_BUCKET_SIZE << best_level) * tick) {
            best_level++;
        }
        
        std::size_t start_bucket = getBucket(min_price, best_level);
        std::size_t end_bucket = getBucket(max_price, best_level);
        
        for (std::size_t bucket = start_bucket; bucket <= end_bucket && bucket < pyramid_[best_level].size(); bucket++) {
            const auto& level = pyramid_[best_level][bucket];
            Price level_min = level.min_price.load(std::memory_order_relaxed);
            Price level_max = level.max_price.load(std::memory_order_relaxed);
            
            // Check if bucket overlaps with our range
            if (level_max >= min_price && level_min <= max_price) {
                total_volume += level.total_volume.load(std::memory_order_relaxed);
            }
        }
        
        return total_volume;
    }
};

} // namespace novel
} // namespace abyssbook