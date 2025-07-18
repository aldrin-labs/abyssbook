#pragma once

#include "common.hpp"
#include <optional>
#include <functional>
#include <string>
#include <cstring>

namespace abyssbook {

// Forward declarations
struct CacheAlignedOrder;

// Advanced order parameters structures

// TWAP (Time-Weighted Average Price) order parameters
struct TWAPParams {
    Amount total_amount;
    std::uint64_t interval_seconds;
    std::uint64_t num_intervals;
    Timestamp start_time;
    Amount amount_per_interval;
    std::uint64_t intervals_executed = 0;
    
    TWAPParams() = default;
    
    TWAPParams(Amount total_amt, std::uint64_t intervals, std::uint64_t interval_sec)
        : total_amount(total_amt)
        , interval_seconds(interval_sec)
        , num_intervals(intervals)
        , start_time(getCurrentTimestamp())
        , amount_per_interval(total_amt / intervals)
        , intervals_executed(0) {}
};

// Trailing Stop order parameters
struct TrailingStopParams {
    Amount distance;              // Fixed distance from market price
    Price last_trigger_price;     // Last price that updated the stop price
    Price current_stop_price;     // Current stop price
    
    TrailingStopParams() = default;
    
    TrailingStopParams(Amount dist, Price trigger_price, Price stop_price)
        : distance(dist)
        , last_trigger_price(trigger_price)
        , current_stop_price(stop_price) {}
};

// OSO (One-Sends-Other) order parameters
struct OSOParams {
    std::unique_ptr<CacheAlignedOrder> child_order;
    bool is_child_placed = false;
    
    OSOParams() = default;
    OSOParams(std::unique_ptr<CacheAlignedOrder> child) 
        : child_order(std::move(child)) {}
};

// OCO (One-Cancels-Other) order parameters
struct OCOParams {
    std::unique_ptr<CacheAlignedOrder> linked_order;
    bool is_cancelled = false;
    
    OCOParams() = default;
    OCOParams(std::unique_ptr<CacheAlignedOrder> linked) 
        : linked_order(std::move(linked)) {}
};

// Peg order parameters
struct PegParams {
    PegType peg_type;
    std::int64_t offset;           // Can be positive or negative
    std::optional<Price> limit_price;
    
    PegParams() = default;
    
    PegParams(PegType type, std::int64_t off, std::optional<Price> limit = std::nullopt)
        : peg_type(type), offset(off), limit_price(limit) {}
};

// Discretionary order parameters
struct DiscretionaryParams {
    Price base_price;              // Displayed limit price
    Price discretionary_price;     // Hidden discretionary price
    std::optional<Price> last_executed_price;
    
    DiscretionaryParams() = default;
    
    DiscretionaryParams(Price base, Price discretionary)
        : base_price(base), discretionary_price(discretionary) {}
};

// Conditional order parameters
struct ConditionalParams {
    ConditionalType condition_type;
    std::optional<Price> price_threshold;
    std::optional<Timestamp> time_threshold;
    std::optional<Amount> volume_threshold;
    std::function<bool(const CacheAlignedOrder&)> custom_condition;
    std::optional<std::string> reference_symbol;
    bool is_condition_met = false;
    
    ConditionalParams() = default;
    
    ConditionalParams(ConditionalType type) : condition_type(type) {}
};

// Order key for hash maps
struct OrderKey {
    Price price;
    OrderId id;
    
    OrderKey() = default;
    OrderKey(Price p, OrderId order_id) : price(p), id(order_id) {}
    
    bool operator==(const OrderKey& other) const {
        return price == other.price && id == other.id;
    }
    
    bool operator<(const OrderKey& other) const {
        if (price != other.price) return price < other.price;
        return id < other.id;
    }
};

// Hash function for OrderKey
struct OrderKeyHash {
    std::size_t operator()(const OrderKey& key) const noexcept {
        // Combine hash of price and id
        std::size_t h1 = std::hash<Price>{}(key.price);
        std::size_t h2 = std::hash<OrderId>{}(key.id);
        return h1 ^ (h2 << 1); // Simple hash combination
    }
};

// Cache-aligned order structure for optimal performance
struct CACHE_ALIGNED CacheAlignedOrder {
    Price price;
    Amount amount;
    OrderId id;
    OrderSide side;
    OrderType order_type;
    std::optional<Price> stop_price;
    OrderFlags flags;
    
    // Advanced order parameters
    std::optional<Timestamp> expiry_time;        // For GTD orders
    std::optional<Amount> display_amount;        // For iceberg orders
    std::unique_ptr<TWAPParams> twap_params;
    std::unique_ptr<TrailingStopParams> trailing_params;
    std::unique_ptr<OSOParams> oso_params;
    std::unique_ptr<OCOParams> oco_params;
    std::unique_ptr<PegParams> peg_params;
    std::unique_ptr<DiscretionaryParams> discretionary_params;
    std::unique_ptr<ConditionalParams> conditional_params;
    
    // Padding to ensure cache alignment
    char padding[8];
    
    // Constructors
    CacheAlignedOrder() = default;
    
    CacheAlignedOrder(Price p, Amount amt, OrderId order_id, OrderSide s, 
                     OrderType type, std::optional<Price> stop = std::nullopt)
        : price(p), amount(amt), id(order_id), side(s), order_type(type), 
          stop_price(stop) {
        updateFlags();
        std::memset(padding, 0, sizeof(padding));
    }
    
    // Copy constructor (deep copy)
    CacheAlignedOrder(const CacheAlignedOrder& other);
    
    // Copy assignment (deep copy)
    CacheAlignedOrder& operator=(const CacheAlignedOrder& other);
    
    // Move constructor
    CacheAlignedOrder(CacheAlignedOrder&& other) noexcept;
    
    // Move assignment
    CacheAlignedOrder& operator=(CacheAlignedOrder&& other) noexcept;
    
    // Destructor
    ~CacheAlignedOrder() = default;
    
    // Update flags based on order type
    void updateFlags();
    
    // Check if order has expired (for GTD orders)
    bool hasExpired() const;
    
    // Get effective display amount (for iceberg orders)
    Amount getDisplayAmount() const;
    
    // Check if order should be triggered (for stop orders)
    bool shouldTrigger(Price market_price) const;
    
    // Get next TWAP execution time
    std::optional<Timestamp> getNextTWAPTime() const;
    
    // Update trailing stop price
    void updateTrailingStop(Price market_price);
    
    // Check if conditional order conditions are met
    bool checkConditions(Price market_price, Amount market_volume) const;
    
    // Get pegged price based on market data
    std::optional<Price> getPeggedPrice(Price best_bid, Price best_ask, 
                                       std::optional<Price> last_trade = std::nullopt) const;
    
    // Validate order parameters
    OrderError validate() const;
    
    // Get order summary string (for logging/debugging)
    std::string toString() const;
};

// Order snapshot for serialization/persistence
struct OrderSnapshot {
    Price price;
    Amount amount;
    OrderId id;
    OrderSide side;
    OrderType order_type;
    std::optional<Price> stop_price;
    std::optional<Timestamp> expiry_time;
    std::optional<Amount> display_amount;
    
    OrderSnapshot() = default;
    
    explicit OrderSnapshot(const CacheAlignedOrder& order)
        : price(order.price)
        , amount(order.amount)
        , id(order.id)
        , side(order.side)
        , order_type(order.order_type)
        , stop_price(order.stop_price)
        , expiry_time(order.expiry_time)
        , display_amount(order.display_amount) {}
};

// Order factory for creating different order types
class OrderFactory {
public:
    // Create basic limit order
    static CacheAlignedOrder createLimit(Price price, Amount amount, OrderId id, OrderSide side);
    
    // Create market order
    static CacheAlignedOrder createMarket(Amount amount, OrderId id, OrderSide side);
    
    // Create stop order
    static CacheAlignedOrder createStop(Price limit_price, Amount amount, OrderId id, 
                                       OrderSide side, Price stop_price);
    
    // Create stop-limit order
    static CacheAlignedOrder createStopLimit(Price limit_price, Amount amount, OrderId id, 
                                            OrderSide side, Price stop_price);
    
    // Create IOC order
    static CacheAlignedOrder createIOC(Price price, Amount amount, OrderId id, OrderSide side);
    
    // Create FOK order
    static CacheAlignedOrder createFOK(Price price, Amount amount, OrderId id, OrderSide side);
    
    // Create post-only order
    static CacheAlignedOrder createPostOnly(Price price, Amount amount, OrderId id, OrderSide side);
    
    // Create GTD order
    static CacheAlignedOrder createGTD(Price price, Amount amount, OrderId id, OrderSide side, 
                                      Timestamp expiry_time);
    
    // Create iceberg order
    static CacheAlignedOrder createIceberg(Price price, Amount total_amount, Amount display_amount, 
                                          OrderId id, OrderSide side);
    
    // Create TWAP order
    static CacheAlignedOrder createTWAP(Price price, Amount total_amount, OrderId id, OrderSide side,
                                       std::uint64_t num_intervals, std::uint64_t interval_seconds);
    
    // Create trailing stop order
    static CacheAlignedOrder createTrailingStop(Price price, Amount amount, OrderId id, OrderSide side,
                                               Amount distance);
    
    // Create pegged order
    static CacheAlignedOrder createPeg(Amount amount, OrderId id, OrderSide side, PegType peg_type,
                                      std::int64_t offset, std::optional<Price> limit_price = std::nullopt);
    
    // Create discretionary order
    static CacheAlignedOrder createDiscretionary(Price base_price, Amount amount, OrderId id, 
                                                OrderSide side, Price discretionary_price);
    
    // Create conditional order
    static CacheAlignedOrder createConditional(Price price, Amount amount, OrderId id, OrderSide side,
                                              ConditionalType condition_type, Price threshold);
};

} // namespace abyssbook