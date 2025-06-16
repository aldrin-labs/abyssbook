# Logging and Monitoring

This document describes the structured logging and monitoring capabilities of Abyssbook, designed to enhance security breach detection and operational observability.

## Overview

Abyssbook implements a comprehensive structured logging system with the following key features:

- **JSON-formatted structured logs** for easy parsing and analysis
- **Configurable log levels** (DEBUG, INFO, WARN, ERROR, CRITICAL)
- **Thread-safe operation** with minimal performance impact
- **Security-focused logging** for CLI commands, authentication, and orderbook operations
- **Context-aware logging** with key-value metadata
- **Real-time monitoring** capabilities

## Log Levels

The system supports five log levels in order of severity:

| Level    | Description                                      |
|----------|--------------------------------------------------|
| DEBUG    | Detailed diagnostic information                  |
| INFO     | General operational information                  |
| WARN     | Warning conditions that don't stop execution    |
| ERROR    | Error conditions that may affect functionality  |
| CRITICAL | Critical conditions that require immediate attention |

## Log Format

All logs are output in structured JSON format:

```json
{
  "timestamp": "1703123456",
  "level": "INFO",
  "module": "cli.orders",
  "message": "Order placement attempted",
  "context": {
    "side": "buy",
    "price_length": 6,
    "size_length": 4
  }
}
```

### Fields

- **timestamp**: Unix timestamp of when the event occurred
- **level**: Log level (DEBUG, INFO, WARN, ERROR, CRITICAL)
- **module**: Source module that generated the log entry
- **message**: Human-readable description of the event
- **context**: Optional key-value pairs providing additional context

## Security Monitoring

The logging system automatically captures security-sensitive events:

### CLI Command Monitoring

- All CLI commands and their arguments are logged
- Suspicious input patterns are detected and flagged
- Failed authentication attempts are recorded
- Configuration changes are tracked

### Order Management Security

- Order placement, modification, and cancellation events
- Invalid order parameters and validation failures
- Suspicious trading patterns

### System Security Events

- Configuration changes, especially to security settings
- Access to sensitive system state (debug dumps, performance data)
- Error conditions that might indicate security issues

## Configuration

### Setting Log Level

You can configure the log level using the CLI:

```bash
# Set log level via debug command
abyssbook debug log info

# Set log level via configuration
abyssbook config set logging.level debug
```

### Available Configuration Keys

| Key                        | Description                          | Default |
|----------------------------|--------------------------------------|---------|
| `logging.level`           | Global log level                     | info    |
| `logging.format`          | Log format (currently only JSON)    | json    |
| `logging.output`          | Output destination                   | stderr  |
| `logging.security_events` | Enable security event logging       | true    |

## Usage Examples

### Basic Logging

```zig
const logging = @import("logging.zig");

// Initialize global logger
try logging.initGlobalLogger(allocator, .INFO);
defer logging.deinitGlobalLogger();

// Simple logging
logging.infoGlobal("module_name", "Operation completed successfully");
logging.warnGlobal("module_name", "Potential issue detected");
logging.errorGlobal("module_name", "Operation failed");
```

### Contextual Logging

```zig
// Log with additional context
logging.logGlobalWithContext(.INFO, "auth", "User login attempt", .{
    .username = "admin",
    .ip_address = "192.168.1.100",
    .success = false,
});

// Security event logging
logging.logGlobalWithContext(.WARN, "security", "Suspicious activity", .{
    .event_type = "multiple_failed_logins",
    .user_id = 12345,
    .attempt_count = 5,
    .time_window = "5_minutes",
});
```

### Instance Logging

```zig
// Create dedicated logger instance
var logger = try logging.Logger.init(allocator, .DEBUG);
defer logger.deinit();

// Use instance methods
try logger.infoWithContext("orders", "Order processed", .{
    .order_id = "ord-123456",
    .side = "buy",
    .price = 100.50,
    .quantity = 10,
});
```

## Security Best Practices

### Input Validation Logging

The system automatically logs suspicious input patterns:

- Path traversal attempts (`../`, `./`)
- Command injection patterns (`;`, `|`, `&`, `$()`)
- Script injection attempts (`<script`, `javascript:`)
- Excessive special characters

### Sensitive Data Protection

- Passwords and private keys are never logged
- Financial amounts are logged as length indicators, not actual values
- User IDs are logged instead of usernames when possible

### Monitoring Recommendations

1. **Set up log aggregation** to collect logs from all instances
2. **Configure alerting** for CRITICAL and ERROR level events
3. **Monitor for suspicious patterns**:
   - Multiple failed authentication attempts
   - Unusual CLI command sequences
   - High error rates
   - Security event clusters

4. **Regular log review** for security analysis
5. **Log retention policies** to balance storage with compliance needs

## Integration with Monitoring Systems

The JSON log format is compatible with popular monitoring and alerting systems:

- **ELK Stack** (Elasticsearch, Logstash, Kibana)
- **Grafana + Loki** for log aggregation and visualization
- **Prometheus** for metrics extraction from logs
- **Splunk** for enterprise log analysis

## Performance Considerations

- Logging is designed to be **asynchronous** and **non-blocking**
- **Thread-safe** operations with minimal lock contention
- **Configurable log levels** to reduce overhead in production
- **Efficient JSON serialization** for structured data

## Troubleshooting

### Common Issues

1. **Logs not appearing**: Check log level configuration
2. **Performance impact**: Consider raising log level to WARN or ERROR
3. **Missing context**: Ensure contextual logging is used for security events

### Debug Commands

```bash
# Check current log level
abyssbook config get logging.level

# Change log level temporarily
abyssbook debug log debug

# Dump system state for debugging
abyssbook debug dump stats
```

## Future Enhancements

Planned improvements include:

- **Log rotation** and archival policies
- **Centralized configuration** management
- **Real-time dashboards** for security monitoring
- **Automated alerting** rules
- **Machine learning** for anomaly detection
- **Compliance reporting** features

---

For more information on CLI usage, see [CLI Documentation](cli.md).
For system architecture details, see [Architecture Documentation](architecture.md).