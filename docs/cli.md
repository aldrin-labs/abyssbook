# Abyssbook CLI Documentation

The Abyssbook CLI provides a command-line interface for managing and interacting with an Abyssbook node.

## Installation

The CLI is included with the Abyssbook node software. After building the project, you can run the CLI using:

```
./abyssbook [command] [options]
```

## Available Commands

### Help

Display help information about available commands.

```
abyssbook help [command]
```

### TUI (Text-based User Interface)

Launch the interactive text-based user interface for monitoring the orderbook in real-time.

```
abyssbook tui
```

### Status

Display the current status and performance metrics of the node.

```
abyssbook status
```

### Config

View or modify configuration settings.

```
abyssbook config [get|set|list] [key] [value]
```

Examples:
- `abyssbook config list` - Show all configuration settings
- `abyssbook config get node.name` - Get a specific configuration value
- `abyssbook config set orderbook.max_orders 20000` - Update a configuration value

### Orders

Manage orders in the orderbook.

```
abyssbook orders [list|place|cancel] [options]
```

Examples:
- `abyssbook orders list` - List all orders
- `abyssbook orders list buy` - List only buy orders
- `abyssbook orders place buy 100.50 5.0` - Place a buy order at price 100.50 USD for size 5.0 shares
- `abyssbook orders cancel ord-1001` - Cancel order with ID ord-1001

### Debug

Debug and diagnostic commands.

```
abyssbook debug [log|dump|perf] [options]
```

Examples:
- `abyssbook debug log debug` - Set log level to debug
- `abyssbook debug dump orderbook` - Dump the current orderbook state
- `abyssbook debug perf` - Run performance tests

## TUI Interface

The TUI provides a real-time view of the orderbook with color-coded buy and sell orders.

### Controls

- `q` - Quit the TUI
- `r` - Refresh data
- `h` - Toggle help panel

### Panels

1. **Buy Orders** - Shows current buy orders sorted by price (highest first)
2. **Sell Orders** - Shows current sell orders sorted by price (lowest first)
3. **Recent Trades** - Shows recently executed trades
4. **Status Bar** - Shows system status and performance metrics

## Configuration

The CLI can manage the node's configuration settings. The configuration is stored in a file and can be modified using the `config` command.

### Important Configuration Keys

- `node.name` - The name of the node
- `node.log_level` - Logging level (debug, info, warn, error)
- `orderbook.max_orders` - Maximum number of orders in the orderbook
- `orderbook.price_precision` - Decimal precision for prices
- `orderbook.size_precision` - Decimal precision for order sizes
- `perf.threads` - Number of threads to use for processing
- `perf.batch_size` - Batch size for processing orders
