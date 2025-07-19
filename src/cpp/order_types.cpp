#include "abyssbook/order_types.hpp"
#include <sstream>
#include <algorithm>
#include <cstring>

namespace abyssbook {

// CacheAlignedOrder implementation

CacheAlignedOrder::CacheAlignedOrder(const CacheAlignedOrder& other)
    : price(other.price)
    , amount(other.amount)
    , id(other.id)
    , timestamp(other.timestamp)
    , side(other.side)
    , order_type(other.order_type)
    , flags(other.flags)
    , stop_price(other.stop_price)
    , expiry_time(other.expiry_time)
    , display_amount(other.display_amount)
{
    // Deep copy of unique_ptr members
    if (other.twap_params) {
        twap_params = std::make_unique<TWAPParams>(*other.twap_params);
    }
    if (other.trailing_params) {
        trailing_params = std::make_unique<TrailingStopParams>(*other.trailing_params);
    }
    if (other.oso_params) {
        oso_params = std::make_unique<OSOParams>();
        oso_params->is_child_placed = other.oso_params->is_child_placed;
        if (other.oso_params->child_order) {
            oso_params->child_order = std::make_unique<CacheAlignedOrder>(*other.oso_params->child_order);
        }
    }
    if (other.oco_params) {
        oco_params = std::make_unique<OCOParams>();
        oco_params->is_cancelled = other.oco_params->is_cancelled;
        if (other.oco_params->linked_order) {
            oco_params->linked_order = std::make_unique<CacheAlignedOrder>(*other.oco_params->linked_order);
        }
    }
    if (other.peg_params) {
        peg_params = std::make_unique<PegParams>(*other.peg_params);
    }
    if (other.discretionary_params) {
        discretionary_params = std::make_unique<DiscretionaryParams>(*other.discretionary_params);
    }
    if (other.conditional_params) {
        conditional_params = std::make_unique<ConditionalParams>(*other.conditional_params);
    }
    
    std::memset(padding1, 0, sizeof(padding1));
}

CacheAlignedOrder& CacheAlignedOrder::operator=(const CacheAlignedOrder& other) {
    if (this != &other) {
        price = other.price;
        amount = other.amount;
        id = other.id;
        side = other.side;
        order_type = other.order_type;
        stop_price = other.stop_price;
        flags = other.flags;
        expiry_time = other.expiry_time;
        display_amount = other.display_amount;
        
        // Deep copy unique_ptr members
        twap_params.reset();
        if (other.twap_params) {
            twap_params = std::make_unique<TWAPParams>(*other.twap_params);
        }
        
        trailing_params.reset();
        if (other.trailing_params) {
            trailing_params = std::make_unique<TrailingStopParams>(*other.trailing_params);
        }
        
        oso_params.reset();
        if (other.oso_params) {
            oso_params = std::make_unique<OSOParams>();
            oso_params->is_child_placed = other.oso_params->is_child_placed;
            if (other.oso_params->child_order) {
                oso_params->child_order = std::make_unique<CacheAlignedOrder>(*other.oso_params->child_order);
            }
        }
        
        oco_params.reset();
        if (other.oco_params) {
            oco_params = std::make_unique<OCOParams>();
            oco_params->is_cancelled = other.oco_params->is_cancelled;
            if (other.oco_params->linked_order) {
                oco_params->linked_order = std::make_unique<CacheAlignedOrder>(*other.oco_params->linked_order);
            }
        }
        
        peg_params.reset();
        if (other.peg_params) {
            peg_params = std::make_unique<PegParams>(*other.peg_params);
        }
        
        discretionary_params.reset();
        if (other.discretionary_params) {
            discretionary_params = std::make_unique<DiscretionaryParams>(*other.discretionary_params);
        }
        
        conditional_params.reset();
        if (other.conditional_params) {
            conditional_params = std::make_unique<ConditionalParams>(*other.conditional_params);
        }
        
        std::memset(padding1, 0, sizeof(padding1));
    }
    return *this;
}

CacheAlignedOrder::CacheAlignedOrder(CacheAlignedOrder&& other) noexcept
    : price(other.price)
    , amount(other.amount)
    , id(other.id)
    , timestamp(other.timestamp)
    , side(other.side)
    , order_type(other.order_type)
    , flags(other.flags)
    , stop_price(other.stop_price)
    , expiry_time(other.expiry_time)
    , display_amount(other.display_amount)
    , twap_params(std::move(other.twap_params))
    , trailing_params(std::move(other.trailing_params))
    , oso_params(std::move(other.oso_params))
    , oco_params(std::move(other.oco_params))
    , peg_params(std::move(other.peg_params))
    , discretionary_params(std::move(other.discretionary_params))
    , conditional_params(std::move(other.conditional_params))
{
    std::memset(padding1, 0, sizeof(padding1));
}

CacheAlignedOrder& CacheAlignedOrder::operator=(CacheAlignedOrder&& other) noexcept {
    if (this != &other) {
        price = other.price;
        amount = other.amount;
        id = other.id;
        side = other.side;
        order_type = other.order_type;
        stop_price = other.stop_price;
        flags = other.flags;
        expiry_time = other.expiry_time;
        display_amount = other.display_amount;
        
        twap_params = std::move(other.twap_params);
        trailing_params = std::move(other.trailing_params);
        oso_params = std::move(other.oso_params);
        oco_params = std::move(other.oco_params);
        peg_params = std::move(other.peg_params);
        discretionary_params = std::move(other.discretionary_params);
        conditional_params = std::move(other.conditional_params);
        
        std::memset(padding1, 0, sizeof(padding1));
    }
    return *this;
}

void CacheAlignedOrder::updateFlags() {
    flags = OrderFlags{};
    
    switch (order_type) {
        case OrderType::Stop:
        case OrderType::StopLimit:
            flags.is_stop = true;
            break;
        case OrderType::TrailingStop:
            flags.is_stop = true;
            flags.is_trailing_stop = true;
            break;
        case OrderType::IOC:
            flags.is_ioc = true;
            break;
        case OrderType::FOK:
            flags.is_fok = true;
            break;
        case OrderType::PostOnly:
            flags.is_post_only = true;
            break;
        case OrderType::GTD:
            flags.is_gtd = true;
            break;
        case OrderType::Iceberg:
            flags.is_iceberg = true;
            break;
        case OrderType::OCO:
            flags.is_oco = true;
            break;
        case OrderType::TWAP:
            flags.is_twap = true;
            break;
        case OrderType::OSO:
            flags.is_oso = true;
            break;
        case OrderType::Peg:
            flags.is_peg = true;
            break;
        case OrderType::MidpointPeg:
            flags.is_midpoint_peg = true;
            break;
        case OrderType::Discretionary:
            flags.is_discretionary = true;
            break;
        case OrderType::Conditional:
            flags.is_conditional = true;
            break;
        default:
            break;
    }
}

bool CacheAlignedOrder::hasExpired() const {
    if (!flags.is_gtd || !expiry_time) {
        return false;
    }
    return getCurrentTimestamp() > *expiry_time;
}

Amount CacheAlignedOrder::getDisplayAmount() const {
    if (flags.is_iceberg && display_amount) {
        return std::min(*display_amount, amount);
    }
    return amount;
}

bool CacheAlignedOrder::shouldTrigger(Price market_price) const {
    if (!flags.is_stop || !stop_price) {
        return false;
    }
    
    if (side == OrderSide::Buy) {
        return market_price >= *stop_price;
    } else {
        return market_price <= *stop_price;
    }
}

std::optional<Timestamp> CacheAlignedOrder::getNextTWAPTime() const {
    if (!flags.is_twap || !twap_params) {
        return std::nullopt;
    }
    
    const auto& params = *twap_params;
    if (params.intervals_executed >= params.num_intervals) {
        return std::nullopt;
    }
    
    return params.start_time + (params.intervals_executed + 1) * params.interval_seconds * 1000000000LL; // nanoseconds
}

void CacheAlignedOrder::updateTrailingStop(Price market_price) {
    if (!flags.is_trailing_stop || !trailing_params) {
        return;
    }
    
    auto& params = *trailing_params;
    bool should_update = false;
    
    if (side == OrderSide::Buy) {
        // For buy trailing stops, update when market goes down
        if (market_price < params.last_trigger_price) {
            params.last_trigger_price = market_price;
            params.current_stop_price = market_price + params.distance;
            should_update = true;
        }
    } else {
        // For sell trailing stops, update when market goes up
        if (market_price > params.last_trigger_price) {
            params.last_trigger_price = market_price;
            params.current_stop_price = market_price - params.distance;
            should_update = true;
        }
    }
    
    if (should_update) {
        stop_price = params.current_stop_price;
    }
}

bool CacheAlignedOrder::checkConditions(Price market_price, Amount market_volume) const {
    if (!flags.is_conditional || !conditional_params) {
        return false;
    }
    
    const auto& params = *conditional_params;
    
    switch (params.condition_type) {
        case ConditionalType::Price:
            if (params.price_threshold) {
                if (side == OrderSide::Buy) {
                    return market_price <= *params.price_threshold;
                } else {
                    return market_price >= *params.price_threshold;
                }
            }
            break;
            
        case ConditionalType::Time:
            if (params.time_threshold) {
                return getCurrentTimestamp() >= *params.time_threshold;
            }
            break;
            
        case ConditionalType::Volume:
            if (params.volume_threshold) {
                return market_volume >= *params.volume_threshold;
            }
            break;
            
        case ConditionalType::Custom:
            if (params.custom_condition) {
                return params.custom_condition(*this);
            }
            break;
    }
    
    return false;
}

std::optional<Price> CacheAlignedOrder::getPeggedPrice(Price best_bid, Price best_ask, std::optional<Price> last_trade) const {
    if (!flags.is_peg && !flags.is_midpoint_peg) {
        return std::nullopt;
    }
    
    Price reference_price = 0;
    
    if (flags.is_midpoint_peg) {
        if (best_bid == 0 || best_ask == 0) {
            return std::nullopt;
        }
        reference_price = (best_bid + best_ask) / 2;
    } else if (peg_params) {
        switch (peg_params->peg_type) {
            case PegType::BestBid:
                if (best_bid == 0) return std::nullopt;
                reference_price = best_bid;
                break;
            case PegType::BestAsk:
                if (best_ask == 0) return std::nullopt;
                reference_price = best_ask;
                break;
            case PegType::Midpoint:
                if (best_bid == 0 || best_ask == 0) return std::nullopt;
                reference_price = (best_bid + best_ask) / 2;
                break;
            case PegType::LastTrade:
                if (!last_trade) return std::nullopt;
                reference_price = *last_trade;
                break;
        }
    } else {
        return std::nullopt;
    }
    
    // Apply offset
    std::int64_t offset = peg_params ? peg_params->offset : 0;
    Price pegged_price;
    
    if (offset >= 0) {
        pegged_price = reference_price + static_cast<Price>(offset);
    } else {
        Price negative_offset = static_cast<Price>(-offset);
        pegged_price = (negative_offset > reference_price) ? 0 : reference_price - negative_offset;
    }
    
    // Apply limit price if specified
    if (peg_params && peg_params->limit_price) {
        Price limit = *peg_params->limit_price;
        if (side == OrderSide::Buy) {
            pegged_price = std::min(pegged_price, limit);
        } else {
            pegged_price = std::max(pegged_price, limit);
        }
    }
    
    return pegged_price;
}

OrderError CacheAlignedOrder::validate() const {
    if (price == 0 && order_type != OrderType::Market) {
        return OrderError::InvalidPrice;
    }
    
    if (amount == 0) {
        return OrderError::InvalidAmount;
    }
    
    if (id == 0) {
        return OrderError::InvalidParameters;
    }
    
    // Validate stop price
    if (flags.is_stop && !stop_price) {
        return OrderError::InvalidParameters;
    }
    
    // Validate iceberg display amount
    if (flags.is_iceberg) {
        if (!display_amount || *display_amount == 0 || *display_amount > amount) {
            return OrderError::InvalidParameters;
        }
    }
    
    // Validate GTD expiry time
    if (flags.is_gtd) {
        if (!expiry_time || *expiry_time <= getCurrentTimestamp()) {
            return OrderError::InvalidParameters;
        }
    }
    
    // Validate TWAP parameters
    if (flags.is_twap && twap_params) {
        if (twap_params->num_intervals == 0 || twap_params->interval_seconds == 0) {
            return OrderError::InvalidParameters;
        }
    }
    
    return OrderError::Success;
}

std::string CacheAlignedOrder::toString() const {
    std::ostringstream oss;
    oss << "Order{id=" << id 
        << ", side=" << (side == OrderSide::Buy ? "Buy" : "Sell")
        << ", type=" << static_cast<int>(order_type)
        << ", price=" << price
        << ", amount=" << amount;
    
    if (stop_price) {
        oss << ", stop_price=" << *stop_price;
    }
    
    if (expiry_time) {
        oss << ", expiry_time=" << *expiry_time;
    }
    
    if (display_amount) {
        oss << ", display_amount=" << *display_amount;
    }
    
    oss << "}";
    return oss.str();
}

// OrderFactory implementation

CacheAlignedOrder OrderFactory::createLimit(Price price, Amount amount, OrderId id, OrderSide side) {
    return CacheAlignedOrder(price, amount, id, side, OrderType::Limit);
}

CacheAlignedOrder OrderFactory::createMarket(Amount amount, OrderId id, OrderSide side) {
    Price market_price = (side == OrderSide::Buy) ? UINT64_MAX : 0;
    return CacheAlignedOrder(market_price, amount, id, side, OrderType::Market);
}

CacheAlignedOrder OrderFactory::createStop(Price limit_price, Amount amount, OrderId id, OrderSide side, Price stop_price) {
    CacheAlignedOrder order(limit_price, amount, id, side, OrderType::Stop, stop_price);
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createStopLimit(Price limit_price, Amount amount, OrderId id, OrderSide side, Price stop_price) {
    CacheAlignedOrder order(limit_price, amount, id, side, OrderType::StopLimit, stop_price);
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createIOC(Price price, Amount amount, OrderId id, OrderSide side) {
    CacheAlignedOrder order(price, amount, id, side, OrderType::IOC);
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createFOK(Price price, Amount amount, OrderId id, OrderSide side) {
    CacheAlignedOrder order(price, amount, id, side, OrderType::FOK);
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createPostOnly(Price price, Amount amount, OrderId id, OrderSide side) {
    CacheAlignedOrder order(price, amount, id, side, OrderType::PostOnly);
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createGTD(Price price, Amount amount, OrderId id, OrderSide side, Timestamp expiry_time) {
    CacheAlignedOrder order(price, amount, id, side, OrderType::GTD);
    order.expiry_time = expiry_time;
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createIceberg(Price price, Amount total_amount, Amount display_amount, OrderId id, OrderSide side) {
    CacheAlignedOrder order(price, total_amount, id, side, OrderType::Iceberg);
    order.display_amount = display_amount;
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createTWAP(Price price, Amount total_amount, OrderId id, OrderSide side,
                                          std::uint64_t num_intervals, std::uint64_t interval_seconds) {
    CacheAlignedOrder order(price, total_amount, id, side, OrderType::TWAP);
    order.twap_params = std::make_unique<TWAPParams>(total_amount, num_intervals, interval_seconds);
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createTrailingStop(Price price, Amount amount, OrderId id, OrderSide side, Amount distance) {
    CacheAlignedOrder order(price, amount, id, side, OrderType::TrailingStop);
    order.trailing_params = std::make_unique<TrailingStopParams>(distance, price, price);
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createPeg(Amount amount, OrderId id, OrderSide side, PegType peg_type,
                                         std::int64_t offset, std::optional<Price> limit_price) {
    CacheAlignedOrder order(0, amount, id, side, OrderType::Peg); // Price will be calculated dynamically
    order.peg_params = std::make_unique<PegParams>(peg_type, offset, limit_price);
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createDiscretionary(Price base_price, Amount amount, OrderId id, 
                                                   OrderSide side, Price discretionary_price) {
    CacheAlignedOrder order(base_price, amount, id, side, OrderType::Discretionary);
    order.discretionary_params = std::make_unique<DiscretionaryParams>(base_price, discretionary_price);
    order.updateFlags();
    return order;
}

CacheAlignedOrder OrderFactory::createConditional(Price price, Amount amount, OrderId id, OrderSide side,
                                                 ConditionalType condition_type, Price threshold) {
    CacheAlignedOrder order(price, amount, id, side, OrderType::Conditional);
    order.conditional_params = std::make_unique<ConditionalParams>(condition_type);
    order.conditional_params->price_threshold = threshold;
    order.updateFlags();
    return order;
}

} // namespace abyssbook