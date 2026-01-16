# Home Assistant MCP Server API Documentation

## Overview

The Home Assistant MCP Server provides a Model Context Protocol (MCP) interface for Claude to interact with Home Assistant configuration files safely and efficiently. This document describes the available endpoints, operations, and security features.

## Table of Contents

- [Architecture](#architecture)
- [Security Features](#security-features)
- [Health Check API](#health-check-api)
- [Cache Management API](#cache-management-api)
- [Circuit Breaker API](#circuit-breaker-api)
- [Validation API](#validation-api)
- [Error Handling](#error-handling)
- [Rate Limiting](#rate-limiting)

## Architecture

```
┌─────────────┐    ┌─────────────┐    ┌─────────────────┐
│ Claude      │───▶│ MCP Server  │───▶│ Home Assistant  │
│ Desktop     │    │ (Node.js)   │    │ Config Files    │
└─────────────┘    └─────────────┘    └─────────────────┘
                           │
                   ┌───────┼───────┐
                   │       │       │
            ┌──────▼───┐ ┌─▼────┐ ┌▼──────┐
            │ Security │ │Cache │ │Health │
            │ Layer    │ │Layer │ │Check  │
            └──────────┘ └──────┘ └───────┘
```

## Security Features

### Input Validation

All inputs are validated using the security utilities:

- **Path Validation**: Prevents directory traversal attacks
- **File Extension Validation**: Only allows safe file types
- **File Size Validation**: Limits file sizes to prevent DoS
- **Content Sanitization**: Removes dangerous characters

### Rate Limiting

Configurable rate limiting protects against abuse:

- **Default Limit**: 100 requests per 60 seconds
- **Configurable**: Set via `RATE_LIMIT_MAX` and `RATE_LIMIT_WINDOW`
- **Per-Client Tracking**: Separate limits for different clients

### File Access Control

- **Allowed Paths**: Only files within `/config` directory
- **Allowed Extensions**: `.yaml`, `.yml`, `.json`, `.py`, `.md`, `.txt`, `.conf`, `.cfg`, `.ini`, `.log`
- **Suspicious Pattern Detection**: Blocks access to sensitive files

## Health Check API

### Endpoint: `/health`

Returns comprehensive health status of the MCP server and Home Assistant environment.

#### Request

```http
GET /health
```

#### Response Formats

##### Human Readable (Default)

```
Health Check Report
====================
Overall Status: OK
Timestamp: 2024-01-16 10:30:00
Total Checks: 10
Passed: 8
Warnings: 2
Critical: 0

✓ mcp_process:       MCP server running (PID: 1234, uptime: 2:30:45)
✓ disk_space:        Disk usage normal: 45% (45%)
⚠ memory_usage:      Memory usage high: 85% (85%)
✓ cpu_usage:         CPU usage normal: 15% (15%)
✓ config_files:      All essential config files present (1 files)
✓ yaml_syntax:       All YAML files valid (15 files)
✓ file_permissions:  File permissions OK (0 issues)
✓ docker_health:     Container healthy
✓ network_connectivity: Network connectivity OK (2 targets)
✓ mcp_response:      MCP server responding
```

##### JSON Format

```json
{
  "overall_status": "OK",
  "timestamp": 1705401000,
  "checks_total": 10,
  "checks_passed": 8,
  "checks_warnings": 2,
  "checks_critical": 0,
  "checks": {
    "mcp_process": {
      "status": "OK",
      "message": "MCP server running",
      "value": "1234",
      "unit": "pid"
    },
    "disk_space": {
      "status": "OK",
      "message": "Disk usage normal: 45%",
      "value": "45",
      "unit": "%"
    }
  }
}
```

##### Prometheus Format

```prometheus
# HELP mcp_health_check_status Health check status (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# TYPE mcp_health_check_status gauge
mcp_health_check_status{check="mcp_process"} 0
mcp_health_check_status{check="disk_space"} 0
mcp_health_check_value{check="disk_space"} 45
mcp_health_overall_status OK
mcp_health_checks_total 10
mcp_health_checks_passed 8
```

#### Available Health Checks

| Check Name | Description | Thresholds |
|------------|-------------|------------|
| `mcp_process` | MCP server process status | Running/Not Running |
| `disk_space` | Disk space usage | Warning: 80%, Critical: 90% |
| `memory_usage` | System memory usage | Warning: 80%, Critical: 95% |
| `cpu_usage` | System CPU usage | Warning: 80%, Critical: 95% |
| `config_files` | Essential config files present | Missing files |
| `yaml_syntax` | YAML file syntax validation | Syntax errors |
| `file_permissions` | File access permissions | Read/Write access |
| `docker_health` | Docker container status | Container status |
| `network_connectivity` | External network access | Ping test results |
| `mcp_response` | MCP server responsiveness | Process signals |

#### Status Codes

- `200`: All checks passed (overall status: OK)
- `503`: Some checks failed (overall status: WARNING/CRITICAL)

## Cache Management API

### Cache Operations

The caching layer provides performance optimization for frequently accessed files and operations.

#### Set Cache Entry

```bash
# Command line interface
./scripts/cache-manager.sh set "config:configuration.yaml" "file_content" 300
```

#### Get Cache Entry

```bash
# Command line interface
./scripts/cache-manager.sh get "config:configuration.yaml"
```

#### Cache Statistics

```bash
# Get cache statistics
./scripts/cache-manager.sh stats
```

```
Cache Statistics
================
Status: Enabled
Hit Rate: 75%
Total Requests: 1000
Hits: 750
Misses: 250
Sets: 300
Deletes: 50
Evictions: 25

Current State
=============
Entries: 150 / 10000
Size: 2.5MB / 100MB
TTL: 300s
Location: /tmp/mcp-cache
```

#### Cache Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `CACHE_ENABLED` | `true` | Enable/disable caching |
| `CACHE_DEFAULT_TTL` | `300` | Default TTL in seconds |
| `CACHE_MAX_SIZE` | `104857600` | Max cache size in bytes |
| `CACHE_MAX_ENTRIES` | `10000` | Maximum number of entries |

## Circuit Breaker API

### Circuit Breaker Pattern

Provides fault tolerance for external dependencies and automatic recovery.

#### Execute with Circuit Breaker

```bash
# Execute Home Assistant check with circuit breaker protection
./scripts/circuit-breaker.sh homeassistant check_config
```

#### Circuit Breaker States

| State | Description | Behavior |
|-------|-------------|----------|
| `CLOSED` | Normal operation | Requests flow normally |
| `OPEN` | Failure threshold reached | Requests blocked for recovery timeout |
| `HALF_OPEN` | Testing recovery | Limited requests allowed |

#### Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `CB_FAILURE_THRESHOLD` | `5` | Failures before opening circuit |
| `CB_RECOVERY_TIMEOUT` | `60` | Seconds before retry in open state |
| `CB_SUCCESS_THRESHOLD` | `3` | Successes to close circuit |

#### Circuit Breaker Status

```bash
# Get circuit breaker status
./scripts/circuit-breaker.sh status
```

```
Circuit Breaker Status Report
================================
Generated at: Tue Jan 16 10:30:00 UTC 2024

Service: homeassistant
  State: CLOSED
  Failures: 2
  Success Count: 0

Service: docker
  State: OPEN
  Failures: 5
  Success Count: 0
  Last Failure: 45s ago
```

## Validation API

### File Validation

Comprehensive validation ensures safe file operations.

#### Validate Configuration Path

```bash
# Validate path for security
./scripts/security-utils.sh validate-config "/config/automation.yaml"
```

#### Validate File Access

```bash
# Comprehensive file validation
./scripts/security-utils.sh validate-file "/config/scripts.yaml" "/config" 10485760
```

#### Validation Rules

| Validation Type | Rules |
|----------------|-------|
| **Path Security** | No directory traversal, absolute paths only |
| **File Extensions** | Only whitelisted extensions allowed |
| **File Size** | Configurable size limits (default: 10MB) |
| **Content Pattern** | Block suspicious file patterns |
| **Access Control** | Files must be within allowed directories |

#### Validation Errors

| Error Code | Description | Action |
|------------|-------------|---------|
| `1001` | Invalid file extension | Block file access |
| `1002` | File size too large | Block file access |
| `1003` | Suspicious file pattern | Block file access |
| `1004` | Access outside allowed path | Block file access |
| `1005` | Directory traversal attempt | Block and log security event |

## Error Handling

### Error Response Format

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "File extension not allowed",
    "details": {
      "file": "malware.exe",
      "allowed_extensions": ["yaml", "yml", "json", "py", "md", "txt"]
    },
    "timestamp": "2024-01-16T10:30:00Z"
  }
}
```

### Error Categories

| Category | HTTP Status | Description |
|----------|-------------|-------------|
| `VALIDATION_ERROR` | 400 | Input validation failed |
| `PERMISSION_ERROR` | 403 | Access denied |
| `NOT_FOUND` | 404 | Resource not found |
| `RATE_LIMITED` | 429 | Rate limit exceeded |
| `SERVER_ERROR` | 500 | Internal server error |
| `SERVICE_UNAVAILABLE` | 503 | External service down |

### Recovery Strategies

| Error Type | Recovery Action |
|------------|----------------|
| **Rate Limit** | Wait and retry with exponential backoff |
| **Validation** | Fix input and retry |
| **Permission** | Check file permissions |
| **Service Down** | Circuit breaker handles automatic recovery |
| **Network** | Retry with timeout |

## Rate Limiting

### Rate Limiting Rules

- **Global Limit**: 100 requests per minute per client
- **File Operations**: 50 operations per minute per client
- **Health Checks**: 10 checks per minute per client

### Rate Limit Headers

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1705401060
X-RateLimit-Retry-After: 60
```

### Rate Limit Configuration

```bash
# Environment variables
export RATE_LIMIT_ENABLED=true
export RATE_LIMIT_MAX=100
export RATE_LIMIT_WINDOW=60
```

## Security Best Practices

### For Developers

1. **Always validate inputs** using security utilities
2. **Use circuit breakers** for external dependencies
3. **Implement proper error handling** with appropriate status codes
4. **Log security events** for audit purposes
5. **Follow rate limiting** guidelines

### For Operators

1. **Monitor health checks** regularly
2. **Review security logs** for suspicious activity
3. **Configure appropriate thresholds** for your environment
4. **Keep cache sizes** within reasonable limits
5. **Update security rules** as needed

## Configuration Reference

### Environment Variables

```bash
# Core Configuration
HA_CONFIG_PATH=/config
LOG_LEVEL=info

# Security
RATE_LIMIT_ENABLED=true
RATE_LIMIT_MAX=100
RATE_LIMIT_WINDOW=60

# Cache
CACHE_ENABLED=true
CACHE_DEFAULT_TTL=300
CACHE_MAX_SIZE=104857600

# Circuit Breaker
CB_FAILURE_THRESHOLD=5
CB_RECOVERY_TIMEOUT=60
CB_SUCCESS_THRESHOLD=3

# Health Checks
HC_DISK_WARNING_THRESHOLD=80
HC_DISK_CRITICAL_THRESHOLD=90
HC_MEMORY_WARNING_THRESHOLD=80
HC_MEMORY_CRITICAL_THRESHOLD=95
```

### File Structure

```
/opt/gitquellen/ha-mcp-server/
├── scripts/
│   ├── security-utils.sh      # Input validation and security
│   ├── circuit-breaker.sh     # Fault tolerance
│   ├── cache-manager.sh       # Performance caching
│   ├── health-check.sh        # System monitoring
│   ├── monitor.sh             # Continuous monitoring
│   ├── backup.sh              # Backup operations
│   └── logger.sh              # Logging utilities
├── tests/
│   ├── unit/                  # Unit tests
│   ├── integration/           # Integration tests
│   └── e2e/                   # End-to-end tests
├── docs/
│   ├── API.md                 # This file
│   ├── ARCHITECTURE.md        # System architecture
│   └── TROUBLESHOOTING.md     # Common issues and solutions
└── docker-compose.yml         # Container orchestration
```

## Support and Troubleshooting

For troubleshooting common issues, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

For architectural details, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Version Information

- **API Version**: 1.0.0
- **MCP Protocol Version**: 2024-11-05
- **Supported Home Assistant Versions**: 2023.1+