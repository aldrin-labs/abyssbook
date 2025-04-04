# Abyssbook Onchain Integration

This document describes the integration of real blockchain data into the Abyssbook application, replacing all mocked data with actual onchain calls.

## Architecture Overview

The onchain integration follows a layered architecture:

1. **Blockchain Client Layer** - Handles direct communication with the Solana blockchain
2. **Service Layer** - Provides business logic and interfaces between CLI and blockchain
3. **CLI Layer** - User interface for interacting with the blockchain
4. **Wallet Layer** - Manages keys and transaction signing
5. **Error Handling Layer** - Provides robust error handling with retry logic
6. **Caching Layer** - Optimizes performance by caching frequently accessed data

## Components

### Blockchain Client

The `BlockchainClient` module connects to the Solana blockchain through external APIs, providing methods to:
- Retrieve orderbook data
- Place orders
- Cancel orders
- Query market information

The enhanced version (`EnhancedBlockchainClient`) adds caching and error handling.

### Order Service

The `OrderService` replaces mocked order data with real blockchain calls, providing:
- Order listing with filtering
- Order placement with price and size validation
- Order cancellation

### Wallet Integration

The `Wallet` module manages keys and transaction signing:
- Secure key storage
- Transaction signing for order operations
- Address management

### Error Handling

The `ErrorHandler` provides robust error handling for blockchain operations:
- Retry logic with exponential backoff
- Error categorization
- User-friendly error messages

### Caching

The `OrderbookCache` improves performance by:
- Caching orderbook data with time-based expiration
- Reducing network calls for frequently accessed data
- Proper memory management for cached objects

## Usage Examples

### Listing Orders

```
abyssbook orders list
```

This command retrieves and displays all orders from the blockchain.

### Placing an Order

```
abyssbook orders place buy 26.45 10.5
```

This places a buy order at $26.45 USD for 10.5 shares.

### Canceling an Order

```
abyssbook orders cancel 487344531683332573044094
```

This cancels the order with the specified ID.

## Testing

To test the onchain integration, make sure you have all required dependencies installed and properly configured:

1. Zig Compiler: Verify that the Zig compiler is installed (version X.Y.Z or later). You can download it from https://ziglang.org/download/ if needed.
2. Environment Setup: Confirm that any necessary environment variables or configuration settings (e.g., blockchain API keys, network settings) are correctly set as detailed in the Configuration section.
3. Test Execution: Run the test script by executing:
   ./test_onchain.sh

The test script performs the following verifications:
- Blockchain client initialization.
- Orderbook retrieval.
- Caching functionality.
- Error handling.

## Configuration

The blockchain connection can be configured in the following ways:

1. **API Key**: Set your API key in the blockchain configuration
2. **Network**: Choose between mainnet, testnet, or devnet
3. **Caching**: Adjust TTL settings for cached data

## Error Handling

The application handles various blockchain-related errors:
- Network errors with automatic retry
- Rate limiting with exponential backoff
- Authentication failures
- Invalid parameters
- Service unavailability

## Performance Considerations

The caching layer significantly improves performance by:
- Reducing network calls
- Storing frequently accessed data in memory
- Using time-based expiration to ensure data freshness

## Security Considerations

- API keys are loaded from secure configuration
- Private keys never leave the wallet module
- All transactions are properly signed
- Memory containing sensitive data is cleared after use
