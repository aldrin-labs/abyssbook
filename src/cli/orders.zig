const std = @import("std");
const EnhancedOrderService = @import("../services/enhanced_orders.zig").EnhancedOrderService;
const args_module = @import("args.zig");
const OrdersCommandArgs = args_module.OrdersCommandArgs;
const ArgParser = args_module.ArgParser;
const ArgError = args_module.ArgError;
const logging = @import("../logging.zig");

/// Handle orders commands with blockchain integration
pub fn handleOrdersCommand(args: []const []const u8) !void {
    // Log order command execution for security monitoring
    logging.infoGlobalWithContext("cli.orders", "Order command initiated", .{
        .arg_count = args.len,
        .subcommand = if (args.len > 0) args[0] else "none",
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize the enhanced order service with blockchain and wallet integration
    var order_service = try EnhancedOrderService.init(allocator);
    defer order_service.deinit();

    if (args.len == 0) {
        // Show orders help
        logging.debugGlobal("cli.orders", "Orders help requested");
        showOrdersHelp();
        return;
    }

    const subcommand = args[0];
    if (std.mem.eql(u8, subcommand, "list")) {
        // Parse list arguments
        var parser = try OrdersCommandArgs.listArgs(allocator);
        defer parser.deinit();

        // Set arguments from command line
        if (args.len > 1) {
            parser.args = args[1..];
        }

        try parser.parse();
        const side = parser.getString("side");
        try order_service.listOrders(side);
    } else if (std.mem.eql(u8, subcommand, "place")) {
        logging.infoGlobal("cli.orders", "Place order command initiated");

        // Parse place arguments
        var parser = try OrdersCommandArgs.placeArgs(allocator);
        defer parser.deinit();

        // Set arguments from command line
        if (args.len > 1) {
            parser.args = args[1..];
        } else {
            logging.warnGlobal("cli.orders", "Insufficient arguments for place order");
            std.debug.print("Error: Insufficient arguments for place order\n", .{});
            std.debug.print("Usage: abyssbook orders place <buy|sell> <price> <size>\n", .{});
            std.debug.print("Usage: abyssbook orders place <buy|sell> <price in USD> <size in shares>\n", .{});
            return;
        }

        // Parse and validate arguments
        parser.parse() catch |err| {
            logging.errorGlobalWithContext("cli.orders", "Order placement argument parsing failed", .{
                .error_name = @errorName(err),
            });

            switch (err) {
                ArgError.MissingRequiredArgument => {
                    std.debug.print("Error: Missing required arguments for place order\n", .{});
                    std.debug.print("Usage: abyssbook orders place <buy|sell> <price in USD> <size in shares>\n", .{});
                    return;
                },
                else => return err,
            }
        };

        const side = try parser.getStringOrError("side");
        const price = try parser.getStringOrError("price");
        const size = try parser.getStringOrError("size");

        // Log order placement attempt for security monitoring
        logging.infoGlobalWithContext("cli.orders", "Order placement attempted", .{
            .side = side,
            .price_length = price.len,
            .size_length = size.len,
        });

        // Basic validation for order parameters
        if (!isValidOrderSide(side)) {
            logging.warnGlobalWithContext("cli.orders", "Invalid order side specified", .{
                .side = side,
            });
        }

        if (!isValidNumericString(price)) {
            logging.warnGlobalWithContext("cli.orders", "Invalid price format", .{
                .price_length = price.len,
            });
        }

        if (!isValidNumericString(size)) {
            logging.warnGlobalWithContext("cli.orders", "Invalid size format", .{
                .size_length = size.len,
            });
        }

        try order_service.placeOrder(side, price, size);

        logging.infoGlobal("cli.orders", "Order placement completed");
    } else if (std.mem.eql(u8, subcommand, "cancel")) {
        // Parse cancel arguments
        var parser = try OrdersCommandArgs.cancelArgs(allocator);
        defer parser.deinit();

        // Set arguments from command line
        if (args.len > 1) {
            parser.args = args[1..];
        } else {
            std.debug.print("Error: Missing order ID\n", .{});
            std.debug.print("Usage: abyssbook orders cancel <order_id>\n", .{});
            return;
        }

        // Parse and validate arguments
        parser.parse() catch |err| {
            switch (err) {
                ArgError.MissingRequiredArgument => {
                    std.debug.print("Error: Missing order ID\n", .{});
                    std.debug.print("Usage: abyssbook orders cancel <order_id>\n", .{});
                    return;
                },
                else => return err,
            }
        };

        const order_id = try parser.getStringOrError("order_id");

        // Log order cancellation attempt
        logging.infoGlobalWithContext("cli.orders", "Order cancellation attempted", .{
            .order_id_length = order_id.len,
        });

        try order_service.cancelOrder(order_id);

        logging.infoGlobal("cli.orders", "Order cancellation completed");
    } else {
        logging.warnGlobalWithContext("cli.orders", "Unknown orders subcommand", .{
            .subcommand = subcommand,
        });
        std.debug.print("Unknown orders subcommand: {s}\n", .{subcommand});
        showOrdersHelp();
    }
}

/// Validate order side parameter
fn isValidOrderSide(side: []const u8) bool {
    return std.mem.eql(u8, side, "buy") or std.mem.eql(u8, side, "sell");
}

/// Validate numeric string (basic check)
fn isValidNumericString(value: []const u8) bool {
    if (value.len == 0) return false;

    var has_decimal = false;
    for (value) |char| {
        if (char == '.') {
            if (has_decimal) return false; // Multiple decimals
            has_decimal = true;
        } else if (!std.ascii.isDigit(char)) {
            return false;
        }
    }
    return true;
}

/// Show orders command help
fn showOrdersHelp() void {
    std.debug.print("Abyssbook Orders Commands\n", .{});
    std.debug.print("=======================\n\n", .{});
    std.debug.print("Available subcommands:\n", .{});
    std.debug.print("  list [buy|sell]  - List all orders or filter by side\n", .{});
    std.debug.print("  place <buy|sell> <price in USD> <size in shares> - Place a new order\n", .{});
    std.debug.print("  cancel <order_id> - Cancel an existing order\n", .{});
}
