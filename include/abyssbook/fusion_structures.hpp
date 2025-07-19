#pragma once

#include "common.hpp"
#include "novel_structures.hpp"
#include "thread_safe_random.hpp"
#include <immintrin.h>
#include <bit>
#include <concepts>
#include <shared_mutex>
#include <mutex>
#include <cmath>

namespace abyssbook {
namespace fusion {

//=============================================================================
// 1. Fusion Tree for Word-Sized Integer Operations
//=============================================================================

template<typename T> requires std::unsigned_integral<T>
class FusionTree {
private:
    static constexpr int WORD_SIZE = sizeof(T) * 8;
    static constexpr int BRANCH_FACTOR = 5; // sqrt(w) for optimal performance
    
    struct CACHE_ALIGNED FusionNode {
        std::array<T, BRANCH_FACTOR> keys;
        std::array<void*, BRANCH_FACTOR + 1> children;
        bool is_leaf;
        int key_count;
        
        // Sketch for compressed searching
        T sketch;
        
        FusionNode(bool leaf = true) : is_leaf(leaf), key_count(0), sketch(0) {
            keys.fill(0);
            children.fill(nullptr);
        }
        
        // Create sketch from keys for parallel comparison
        HOT void updateSketch() {
            sketch = 0;
            for (int i = 0; i < key_count; i++) {
                // Extract r most significant bits and pack them
                T compressed = keys[i] >> (WORD_SIZE - 4); // 4 bits per key
                sketch |= (compressed << (i * 4));
            }
        }
        
        // Find position using sketch-based search
        HOT int findPosition(T key) const {
            T key_sketch = key >> (WORD_SIZE - 4);
            
            // Create comparison mask
            T comparison_mask = 0;
            for (int i = 0; i < key_count; i++) {
                T extracted = (sketch >> (i * 4)) & 0xF;
                if (key_sketch <= extracted) {
                    comparison_mask |= (1ULL << i);
                }
            }
            
            // Find first set bit (position where key should be)
            return comparison_mask ? __builtin_ctzll(comparison_mask) : key_count;
        }
    };
    
    std::unique_ptr<FusionNode> root_;
    std::atomic<std::size_t> size_;
    
    // Most significant r bits extraction
    HOT T extractMSR(T value, int r) const {
        return value >> (WORD_SIZE - r);
    }
    
    // Perfect hash function for fusion tree
    HOT T perfectHash(const std::array<T, BRANCH_FACTOR>& keys, int count, T query) const {
        T result = 0;
        for (int i = 0; i < count; i++) {
            T diff = query ^ keys[i];
            // Use bit manipulation to create hash
            result ^= diff * 0x9e3779b97f4a7c15ULL; // Golden ratio
        }
        return result;
    }
    
public:
    FusionTree() : root_(std::make_unique<FusionNode>()), size_(0) {}
    
    HOT bool insert(T key, void* value) {
        return insertHelper(root_.get(), key, value).first;
    }
    
private:
    // Helper for recursive insertion with proper splitting
    std::pair<bool, std::unique_ptr<FusionNode>> insertHelper(FusionNode* node, T key, void* value) {
        if (node->is_leaf) {
            return insertInLeaf(node, key, value);
        } else {
            return insertInInternal(node, key, value);
        }
    }
    
    std::pair<bool, std::unique_ptr<FusionNode>> insertInLeaf(FusionNode* leaf, T key, void* value) {
        int pos = leaf->findPosition(key);
        
        // Check for duplicate
        if (pos < leaf->key_count && leaf->keys[pos] == key) {
            return {false, nullptr}; // Duplicate
        }
        
        // Insert if not full
        if (leaf->key_count < BRANCH_FACTOR) {
            // Shift elements
            for (int i = leaf->key_count; i > pos; i--) {
                leaf->keys[i] = leaf->keys[i-1];
                leaf->children[i+1] = leaf->children[i];
            }
            
            leaf->keys[pos] = key;
            leaf->children[pos+1] = value;
            leaf->key_count++;
            leaf->updateSketch();
            
            size_.fetch_add(1, std::memory_order_relaxed);
            return {true, nullptr};
        }
        
        // Split the leaf node
        auto new_leaf = std::make_unique<FusionNode>(true);
        int mid = BRANCH_FACTOR / 2;
        
        // Move half the keys to new leaf
        for (int i = mid; i < BRANCH_FACTOR; i++) {
            new_leaf->keys[i - mid] = leaf->keys[i];
            new_leaf->children[i - mid + 1] = leaf->children[i + 1];
            new_leaf->key_count++;
        }
        leaf->key_count = mid;
        
        // Insert the new key in appropriate leaf
        if (key < leaf->keys[mid - 1]) {
            insertInLeaf(leaf, key, value);
        } else {
            insertInLeaf(new_leaf.get(), key, value);
        }
        
        // Update sketches
        leaf->updateSketch();
        new_leaf->updateSketch();
        
        return {true, std::move(new_leaf)};
    }
    
    std::pair<bool, std::unique_ptr<FusionNode>> insertInInternal(FusionNode* internal, T key, void* value) {
        int pos = internal->findPosition(key);
        FusionNode* child = static_cast<FusionNode*>(internal->children[pos]);
        
        auto [success, new_child] = insertHelper(child, key, value);
        
        if (!success) return {false, nullptr};
        if (!new_child) return {true, nullptr}; // No split needed
        
        // Child was split, need to insert separator key
        T separator_key = new_child->keys[0];
        
        // Insert separator if internal node has space
        if (internal->key_count < BRANCH_FACTOR) {
            // Shift to make room
            for (int i = internal->key_count; i > pos; i--) {
                internal->keys[i] = internal->keys[i-1];
                internal->children[i+1] = internal->children[i];
            }
            
            internal->keys[pos] = separator_key;
            internal->children[pos+1] = new_child.release();
            internal->key_count++;
            internal->updateSketch();
            
            return {true, nullptr};
        }
        
        // Split internal node
        auto new_internal = std::make_unique<FusionNode>(false);
        int mid = BRANCH_FACTOR / 2;
        
        // Move half the keys and children to new internal node
        for (int i = mid + 1; i < BRANCH_FACTOR; i++) {
            new_internal->keys[i - mid - 1] = internal->keys[i];
            new_internal->children[i - mid] = internal->children[i + 1];
            new_internal->key_count++;
        }
        
        // T promoted_key = internal->keys[mid]; // Currently unused
        internal->key_count = mid;
        
        // Insert separator and new child in appropriate node
        if (pos <= mid) {
            insertInInternal(internal, separator_key, new_child.release());
        } else {
            insertInInternal(new_internal.get(), separator_key, new_child.release());
        }
        
        // Update sketches
        internal->updateSketch();
        new_internal->updateSketch();
        
        return {true, std::move(new_internal)};
    }
    
public:
    
    HOT void* find(T key) const {
        FusionNode* current = root_.get();
        
        while (!current->is_leaf) {
            int pos = current->findPosition(key);
            current = static_cast<FusionNode*>(current->children[pos]);
        }
        
        // Binary search in leaf using sketch
        int pos = current->findPosition(key);
        if (pos < current->key_count && current->keys[pos] == key) {
            return current->children[pos+1];
        }
        
        return nullptr;
    }
    
    std::size_t size() const { return size_.load(std::memory_order_relaxed); }
};

//=============================================================================
// 2. Cache-Oblivious B-Tree
//=============================================================================

template<typename Key, typename Value>
class CacheObliviousBTree {
private:
    struct CACHE_ALIGNED Node {
        static constexpr int MIN_DEGREE = 2;
        static constexpr int MAX_KEYS = 2 * MIN_DEGREE - 1;
        
        std::array<Key, MAX_KEYS> keys;
        std::array<Value, MAX_KEYS> values;
        std::array<std::unique_ptr<Node>, MAX_KEYS + 1> children;
        int key_count;
        bool is_leaf;
        
        Node(bool leaf = true) : key_count(0), is_leaf(leaf) {
            keys.fill(Key{});
            values.fill(Value{});
        }
        
        // Van Emde Boas layout for cache efficiency
        HOT void layoutVEB(std::vector<Node*>& linear_layout, int& index) {
            if (key_count == 0) return;
            
            linear_layout[index++] = this;
            
            if (!is_leaf) {
                int mid = key_count / 2;
                
                // Layout top subtree
                if (children[mid]) {
                    children[mid]->layoutVEB(linear_layout, index);
                }
                
                // Layout left subtrees
                for (int i = 0; i < mid; i++) {
                    if (children[i]) {
                        children[i]->layoutVEB(linear_layout, index);
                    }
                }
                
                // Layout right subtrees
                for (int i = mid + 1; i <= key_count; i++) {
                    if (children[i]) {
                        children[i]->layoutVEB(linear_layout, index);
                    }
                }
            }
        }
    };
    
    std::unique_ptr<Node> root_;
    std::vector<Node*> veb_layout_;
    std::atomic<std::size_t> size_;
    
    HOT void rebuildVEBLayout() {
        veb_layout_.clear();
        veb_layout_.resize(size_.load(std::memory_order_relaxed) + 1);
        int index = 0;
        if (root_) {
            root_->layoutVEB(veb_layout_, index);
        }
    }
    
public:
    CacheObliviousBTree() : root_(std::make_unique<Node>()), size_(0) {}
    
    HOT bool insert(Key key, Value value) {
        // Simplified insertion
        Node* current = root_.get();
        
        // Find leaf
        while (!current->is_leaf) {
            int i = 0;
            while (i < current->key_count && key > current->keys[i]) {
                i++;
            }
            current = current->children[i].get();
        }
        
        // Insert in leaf if not full
        if (current->key_count < Node::MAX_KEYS) {
            int i = current->key_count - 1;
            while (i >= 0 && current->keys[i] > key) {
                current->keys[i + 1] = current->keys[i];
                current->values[i + 1] = current->values[i];
                i--;
            }
            current->keys[i + 1] = key;
            current->values[i + 1] = value;
            current->key_count++;
            
            size_.fetch_add(1, std::memory_order_relaxed);
            
            // Rebuild layout periodically
            if (size_.load(std::memory_order_relaxed) % 1000 == 0) {
                rebuildVEBLayout();
            }
            
            return true;
        }
        
        return false; // Node full, split needed
    }
    
    HOT std::optional<Value> find(Key key) const {
        Node* current = root_.get();
        
        while (current) {
            // Binary search in node
            int left = 0, right = current->key_count - 1;
            while (left <= right) {
                int mid = (left + right) / 2;
                if (current->keys[mid] == key) {
                    return current->values[mid];
                } else if (current->keys[mid] < key) {
                    left = mid + 1;
                } else {
                    right = mid - 1;
                }
            }
            
            if (current->is_leaf) break;
            
            // Find child to follow
            int i = 0;
            while (i < current->key_count && key > current->keys[i]) {
                i++;
            }
            current = current->children[i].get();
        }
        
        return std::nullopt;
    }
    
    std::size_t size() const { return size_.load(std::memory_order_relaxed); }
};

//=============================================================================
// 3. Parallel Exponential Search Tree
//=============================================================================

template<typename Key, typename Value>
class ParallelExpSearchTree {
private:
    struct CACHE_ALIGNED SearchNode {
        Key key;
        Value value;
        std::atomic<SearchNode*> next;
        std::atomic<int> level;
        
        SearchNode(Key k, Value v, int lvl) : key(k), value(v), next(nullptr), level(lvl) {}
    };
    
    std::atomic<SearchNode*> head_;
    std::atomic<std::size_t> size_;
    
    // Exponential search with parallel optimization
    HOT SearchNode* exponentialSearch(Key key) const {
        SearchNode* current = head_.load(std::memory_order_acquire);
        if (!current || current->key >= key) {
            return current;
        }
        
        // Exponential search phase
        int bound = 1;
        SearchNode* prev = current;
        current = current->next.load(std::memory_order_acquire);
        
        while (current && current->key < key) {
            for (int i = 0; i < bound && current; i++) {
                prev = current;
                current = current->next.load(std::memory_order_acquire);
                if (current && current->key >= key) {
                    break;
                }
            }
            bound *= 2;
        }
        
        // Binary search phase in found range
        SearchNode* start = prev;
        SearchNode* end = current;
        
        while (start && end && start != end) {
            // Find middle node (approximation)
            SearchNode* mid = start;
            int steps = bound / 4;
            for (int i = 0; i < steps && mid && mid != end; i++) {
                mid = mid->next.load(std::memory_order_acquire);
            }
            
            if (!mid || mid->key >= key) {
                end = mid;
            } else {
                start = mid;
            }
        }
        
        return start;
    }
    
public:
    ParallelExpSearchTree() : head_(nullptr), size_(0) {}
    
    HOT bool insert(Key key, Value value) {
        SearchNode* new_node = new SearchNode(key, value, 0);
        SearchNode* current = head_.load(std::memory_order_acquire);
        
        if (!current || key < current->key) {
            new_node->next.store(current, std::memory_order_relaxed);
            if (head_.compare_exchange_strong(current, new_node, std::memory_order_release)) {
                size_.fetch_add(1, std::memory_order_relaxed);
                return true;
            } else {
                delete new_node;
                return false; // Retry needed
            }
        }
        
        // Find insertion point
        SearchNode* prev = nullptr;
        while (current && current->key < key) {
            prev = current;
            current = current->next.load(std::memory_order_acquire);
        }
        
        if (current && current->key == key) {
            delete new_node;
            return false; // Duplicate
        }
        
        new_node->next.store(current, std::memory_order_relaxed);
        if (prev && prev->next.compare_exchange_strong(current, new_node, std::memory_order_release)) {
            size_.fetch_add(1, std::memory_order_relaxed);
            return true;
        }
        
        delete new_node;
        return false; // Retry needed
    }
    
    HOT std::optional<Value> find(Key key) const {
        SearchNode* node = exponentialSearch(key);
        
        while (node && node->key <= key) {
            if (node->key == key) {
                return node->value;
            }
            node = node->next.load(std::memory_order_acquire);
        }
        
        return std::nullopt;
    }
    
    std::size_t size() const { return size_.load(std::memory_order_relaxed); }
};

//=============================================================================
// 4. SIMD-Accelerated Sorted Array
//=============================================================================

template<typename Key, typename Value>
class SIMDSortedArray {
private:
    static constexpr std::size_t SIMD_WIDTH = 8; // AVX2 can handle 8 32-bit integers
    static constexpr std::size_t BLOCK_SIZE = 512;
    
    struct CACHE_ALIGNED Block {
        std::array<Key, BLOCK_SIZE> keys;
        std::array<Value, BLOCK_SIZE> values;
        std::atomic<std::size_t> size;
        
        Block() : size(0) {
            keys.fill(Key{});
            values.fill(Value{});
        }
        
        // SIMD-accelerated search within block
        HOT int simdSearch(Key key) const {
            std::size_t block_size = size.load(std::memory_order_relaxed);
            
            if constexpr (sizeof(Key) == 4) {
                // Use AVX2 for 32-bit keys
                __m256i key_vec = _mm256_set1_epi32(static_cast<std::uint32_t>(key));
                
                std::size_t i = 0;
                for (; i + SIMD_WIDTH <= block_size; i += SIMD_WIDTH) {
                    __m256i data_vec = _mm256_loadu_si256(
                        reinterpret_cast<const __m256i*>(&keys[i]));
                    
                    __m256i cmp_result = _mm256_cmpeq_epi32(data_vec, key_vec);
                    int mask = _mm256_movemask_epi8(cmp_result);
                    
                    if (mask != 0) {
                        // Found match, determine exact position
                        return i + (__builtin_ctz(mask) / 4);
                    }
                    
                    // Check if we've passed the key
                    __m256i gt_result = _mm256_cmpgt_epi32(data_vec, key_vec);
                    int gt_mask = _mm256_movemask_epi8(gt_result);
                    if (gt_mask != 0) {
                        return i + (__builtin_ctz(gt_mask) / 4);
                    }
                }
                
                // Handle remaining elements
                for (; i < block_size; i++) {
                    if (keys[i] >= key) {
                        return i;
                    }
                }
            } else {
                // Fallback to binary search for other key sizes
                int left = 0, right = static_cast<int>(block_size) - 1;
                while (left <= right) {
                    int mid = (left + right) / 2;
                    if (keys[mid] == key) {
                        return mid;
                    } else if (keys[mid] < key) {
                        left = mid + 1;
                    } else {
                        right = mid - 1;
                    }
                }
                return left;
            }
            
            return static_cast<int>(block_size);
        }
        
        HOT bool insert(Key key, Value value) {
            std::size_t current_size = size.load(std::memory_order_relaxed);
            if (current_size >= BLOCK_SIZE) return false;
            
            int pos = simdSearch(key);
            
            // Shift elements
            for (int i = static_cast<int>(current_size); i > pos; i--) {
                keys[i] = keys[i-1];
                values[i] = values[i-1];
            }
            
            keys[pos] = key;
            values[pos] = value;
            size.fetch_add(1, std::memory_order_relaxed);
            
            return true;
        }
    };
    
    std::vector<std::unique_ptr<Block>> blocks_;
    std::atomic<std::size_t> total_size_;
    mutable std::shared_mutex mutex_;
    
public:
    SIMDSortedArray() : total_size_(0) {
        blocks_.push_back(std::make_unique<Block>());
    }
    
    HOT bool insert(Key key, Value value) {
        std::shared_lock lock(mutex_);
        
        // Find appropriate block
        for (auto& block : blocks_) {
            std::size_t block_size = block->size.load(std::memory_order_relaxed);
            if (block_size == 0 || 
                (block_size < BLOCK_SIZE && key >= block->keys[0] && key <= block->keys[block_size-1])) {
                
                if (block->insert(key, value)) {
                    total_size_.fetch_add(1, std::memory_order_relaxed);
                    return true;
                }
            }
        }
        
        // Need new block
        lock.unlock();
        std::unique_lock unique_lock(mutex_);
        
        auto new_block = std::make_unique<Block>();
        if (new_block->insert(key, value)) {
            blocks_.push_back(std::move(new_block));
            total_size_.fetch_add(1, std::memory_order_relaxed);
            return true;
        }
        
        return false;
    }
    
    HOT std::optional<Value> find(Key key) const {
        std::shared_lock lock(mutex_);
        
        for (const auto& block : blocks_) {
            std::size_t block_size = block->size.load(std::memory_order_relaxed);
            if (block_size > 0 && key >= block->keys[0] && key <= block->keys[block_size-1]) {
                int pos = block->simdSearch(key);
                if (pos < static_cast<int>(block_size) && block->keys[pos] == key) {
                    return block->values[pos];
                }
            }
        }
        
        return std::nullopt;
    }
    
    std::size_t size() const { return total_size_.load(std::memory_order_relaxed); }
};

//=============================================================================
// 5. Quantum-Inspired Superposition Tree
//=============================================================================

template<typename Key, typename Value>
class QuantumSuperpositionTree {
private:
    struct CACHE_ALIGNED QuantumNode {
        // Superposition of multiple possible states
        std::array<Key, 4> quantum_keys;
        std::array<Value, 4> quantum_values;
        std::array<float, 4> probability_amplitudes;
        std::atomic<QuantumNode*> left;
        std::atomic<QuantumNode*> right;
        std::atomic<int> state_count;
        
        QuantumNode() : left(nullptr), right(nullptr), state_count(0) {
            quantum_keys.fill(Key{});
            quantum_values.fill(Value{});
            probability_amplitudes.fill(0.0f);
        }
        
        // Quantum measurement collapses superposition
        HOT std::pair<Key, Value> measure(Key search_key) const {
            float total_probability = 0.0f;
            std::vector<float> cumulative_prob;
            
            int count = state_count.load(std::memory_order_relaxed);
            for (int i = 0; i < count; i++) {
                // Calculate probability based on key similarity
                float similarity = 1.0f / (1.0f + std::abs(static_cast<int64_t>(quantum_keys[i] - search_key)));
                float prob = probability_amplitudes[i] * similarity;
                total_probability += prob;
                cumulative_prob.push_back(total_probability);
            }
            
            // Quantum measurement
            float random_val = random::FastRNG::fastRandomFloat() * total_probability;
            for (int i = 0; i < count; i++) {
                if (random_val <= cumulative_prob[i]) {
                    return {quantum_keys[i], quantum_values[i]};
                }
            }
            
            return {quantum_keys[0], quantum_values[0]};
        }
        
        HOT bool addState(Key key, Value value, float amplitude = 1.0f) {
            int count = state_count.load(std::memory_order_relaxed);
            if (count >= 4) return false;
            
            quantum_keys[count] = key;
            quantum_values[count] = value;
            probability_amplitudes[count] = amplitude;
            state_count.fetch_add(1, std::memory_order_relaxed);
            
            // Normalize amplitudes
            float sum_squares = 0.0f;
            for (int i = 0; i <= count; i++) {
                sum_squares += probability_amplitudes[i] * probability_amplitudes[i];
            }
            float norm = std::sqrt(sum_squares);
            for (int i = 0; i <= count; i++) {
                probability_amplitudes[i] /= norm;
            }
            
            return true;
        }
    };
    
    std::atomic<QuantumNode*> root_;
    std::atomic<std::size_t> size_;
    
    // Quantum tunneling allows bypassing normal tree traversal
    HOT QuantumNode* quantumTunnel(Key key) const {
        QuantumNode* current = root_.load(std::memory_order_acquire);
        
        // Calculate tunneling probability based on key properties
        std::uint64_t key_bits = static_cast<std::uint64_t>(key);
        float tunnel_prob = static_cast<float>(__builtin_popcountll(key_bits)) / 64.0f;
        
        // Random tunneling through the tree structure
        while (current && random::FastRNG::fastRandomFloat() < tunnel_prob) {
            QuantumNode* left = current->left.load(std::memory_order_acquire);
            QuantumNode* right = current->right.load(std::memory_order_acquire);
            
            if (left && right) {
                current = random::FastRNG::fastRandomBool() ? left : right;
            } else if (left) {
                current = left;
            } else if (right) {
                current = right;
            } else {
                break;
            }
            
            tunnel_prob *= 0.7f; // Decrease tunneling probability
        }
        
        return current;
    }
    
public:
    QuantumSuperpositionTree() : root_(new QuantumNode()), size_(0) {}
    
    HOT bool insert(Key key, Value value) {
        QuantumNode* current = root_.load(std::memory_order_acquire);
        
        // Try quantum tunneling first
        QuantumNode* tunnel_node = quantumTunnel(key);
        if (tunnel_node && tunnel_node->addState(key, value)) {
            size_.fetch_add(1, std::memory_order_relaxed);
            return true;
        }
        
        // Normal insertion if tunneling fails
        while (current) {
            if (current->addState(key, value)) {
                size_.fetch_add(1, std::memory_order_relaxed);
                return true;
            }
            
            // Navigate based on quantum measurement
            auto [measured_key, _] = current->measure(key);
            
            if (key < measured_key) {
                QuantumNode* left = current->left.load(std::memory_order_acquire);
                if (!left) {
                    QuantumNode* new_node = new QuantumNode();
                    if (current->left.compare_exchange_strong(left, new_node, std::memory_order_release)) {
                        left = new_node;
                    } else {
                        delete new_node;
                        left = current->left.load(std::memory_order_acquire);
                    }
                }
                current = left;
            } else {
                QuantumNode* right = current->right.load(std::memory_order_acquire);
                if (!right) {
                    QuantumNode* new_node = new QuantumNode();
                    if (current->right.compare_exchange_strong(right, new_node, std::memory_order_release)) {
                        right = new_node;
                    } else {
                        delete new_node;
                        right = current->right.load(std::memory_order_acquire);
                    }
                }
                current = right;
            }
        }
        
        return false;
    }
    
    HOT std::optional<Value> find(Key key) const {
        QuantumNode* current = root_.load(std::memory_order_acquire);
        
        // Try quantum tunneling
        QuantumNode* tunnel_node = quantumTunnel(key);
        if (tunnel_node) {
            auto [measured_key, measured_value] = tunnel_node->measure(key);
            if (measured_key == key) {
                return measured_value;
            }
        }
        
        // Normal search
        while (current) {
            auto [measured_key, measured_value] = current->measure(key);
            
            if (measured_key == key) {
                return measured_value;
            } else if (key < measured_key) {
                current = current->left.load(std::memory_order_acquire);
            } else {
                current = current->right.load(std::memory_order_acquire);
            }
        }
        
        return std::nullopt;
    }
    
    std::size_t size() const { return size_.load(std::memory_order_relaxed); }
};

} // namespace fusion
} // namespace abyssbook