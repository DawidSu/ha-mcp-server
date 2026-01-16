# System Architecture

## Overview

The Home Assistant MCP Server is a comprehensive solution that provides secure, reliable, and performant access to Home Assistant configuration files through the Model Context Protocol (MCP).

## High-Level Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Claude UI     │    │   Claude API    │    │  Claude Desktop │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │ MCP Protocol
                                 │
                    ┌────────────▼────────────┐
                    │    MCP Server Core      │
                    │  (Node.js Process)      │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
    ┌─────────▼─────────┐ ┌─────▼─────┐ ┌─────────▼─────────┐
    │  Security Layer   │ │Cache Layer│ │  Monitoring Layer │
    │                   │ │           │ │                   │
    │ • Input Valid.    │ │• File Cache│ │• Health Checks    │
    │ • Rate Limiting   │ │• Cmd Cache │ │• Circuit Breakers │
    │ • Access Control  │ │• LRU Evict │ │• Performance Mon. │
    └─────────┬─────────┘ └─────┬─────┘ └─────────┬─────────┘
              │                 │                 │
              └─────────────────┼─────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │  File System Access   │
                    │  (Home Assistant      │
                    │   Config Directory)   │
                    └───────────────────────┘
```

## Core Components

### 1. MCP Server Core
- **Technology**: Node.js with @modelcontextprotocol/server-filesystem
- **Role**: Handles MCP protocol communication with Claude
- **Features**:
  - File system operations (read, write, list)
  - Protocol compliance with MCP 2024-11-05 specification
  - Async/await based operations

### 2. Security Layer
- **Scripts**: `security-utils.sh`
- **Functions**:
  - Input validation and sanitization
  - Path traversal protection
  - File extension whitelisting
  - Size limit enforcement
  - Rate limiting per client
- **Integration**: All file operations pass through security checks

### 3. Cache Layer
- **Scripts**: `cache-manager.sh`
- **Features**:
  - File-based caching with TTL
  - LRU eviction strategy
  - Configurable size limits
  - Command output caching
  - Cache statistics and monitoring
- **Storage**: `/tmp/mcp-cache/` with organized subdirectories

### 4. Monitoring Layer
- **Health Checks**: `health-check.sh`
  - System resource monitoring
  - Service availability checks
  - Configuration validation
  - Multiple output formats (human, JSON, Prometheus)
- **Circuit Breakers**: `circuit-breaker.sh`
  - Fault tolerance for external dependencies
  - Automatic recovery mechanisms
  - State tracking and reporting

## Data Flow

### 1. Request Processing Flow

```
Claude Request
      │
      ▼
┌─────────────────┐
│  Rate Limiter   │ ── Rate exceeded? ──▶ HTTP 429
└─────────┬───────┘
          │
          ▼
┌─────────────────┐
│ Input Validator │ ── Invalid input? ──▶ HTTP 400
└─────────┬───────┘
          │
          ▼
┌─────────────────┐
│  Cache Check    │ ── Cache hit? ────────▶ Return cached result
└─────────┬───────┘
          │ Cache miss
          ▼
┌─────────────────┐
│Circuit Breaker  │ ── Circuit open? ───▶ HTTP 503
└─────────┬───────┘
          │
          ▼
┌─────────────────┐
│File Operation   │ ── Success? ─────────▶ Cache result & return
└─────────┬───────┘
          │ Error
          ▼
┌─────────────────┐
│ Error Handler   │ ──────────────────▶ HTTP 5xx
└─────────────────┘
```

### 2. File Operation Flow

```
File Request
      │
      ▼
┌─────────────────┐
│Path Validation  │ ── Path safe? ────▶ Continue
└─────────┬───────┘           │
          │                   ▼ No
          ▼                 Block
┌─────────────────┐
│Extension Check  │ ── Allowed? ─────▶ Continue
└─────────┬───────┘           │
          │                   ▼ No
          ▼                 Block
┌─────────────────┐
│Size Check       │ ── Within limit? ─▶ Continue
└─────────┬───────┘           │
          │                   ▼ No
          ▼                 Block
┌─────────────────┐
│Permission Check │ ── Accessible? ──▶ Execute
└─────────────────┘           │
                              ▼ No
                            Block
```

## Security Architecture

### Defense in Depth

1. **Input Layer**: Validate all user inputs
2. **Application Layer**: Rate limiting and business logic validation
3. **File System Layer**: Access control and permission checks
4. **Infrastructure Layer**: Container isolation and resource limits

### Security Controls

| Layer | Controls | Implementation |
|-------|----------|----------------|
| **Network** | Rate limiting, IP filtering | `security-utils.sh` |
| **Application** | Input validation, sanitization | Built into all operations |
| **File System** | Path validation, extension filtering | Pre-operation checks |
| **Container** | Resource limits, isolation | Docker configuration |

## Performance Architecture

### Caching Strategy

1. **L1 Cache**: In-memory operation cache (future enhancement)
2. **L2 Cache**: File-based cache with TTL
3. **Cache Invalidation**: Time-based and manual
4. **Cache Warming**: Automatic for frequently accessed files

### Performance Optimizations

- **Circuit Breakers**: Prevent cascading failures
- **Connection Pooling**: Reuse connections where possible
- **Lazy Loading**: Load resources only when needed
- **Batch Operations**: Group related operations

## Reliability Architecture

### Fault Tolerance

1. **Circuit Breakers**: Automatic failure detection and recovery
2. **Health Checks**: Continuous system monitoring
3. **Graceful Degradation**: Fallback to basic operations
4. **Retry Logic**: Exponential backoff for transient failures

### Monitoring and Observability

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Health Checks  │    │  Performance    │    │     Logs        │
│                 │    │   Metrics       │    │                 │
│ • System Status │    │ • Cache Stats   │    │ • Error Logs    │
│ • Service Health│    │ • Response Time │    │ • Access Logs   │
│ • Resource Use  │    │ • Throughput    │    │ • Security Logs │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   Monitoring Dashboard  │
                    │  (Future Enhancement)   │
                    └─────────────────────────┘
```

## Deployment Architecture

### Container Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                        Docker Host                          │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │   MCP Server    │  │    Monitor      │  │Log Aggregator│ │
│  │                 │  │                 │  │              │ │
│  │ • Node.js App   │  │ • Health Checks │  │ • Log Rotate │ │
│  │ • Security      │  │ • Metrics       │  │ • Cleanup    │ │
│  │ • Cache         │  │ • Recovery      │  │ • Archive    │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│           │                     │                   │       │
│           └─────────────────────┼───────────────────┘       │
│                                 │                           │
│  ┌─────────────────────────────▼─────────────────────────┐   │
│  │            Shared Volumes                             │   │
│  │                                                       │   │
│  │ • /config (HA config files)                          │   │
│  │ • /logs (Application logs)                            │   │
│  │ • /backups (Configuration backups)                    │   │
│  │ • /scripts (Utility scripts)                          │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Scalability Considerations

1. **Horizontal Scaling**: Multiple MCP server instances (future)
2. **Vertical Scaling**: Resource allocation per container
3. **Load Balancing**: Request distribution (future enhancement)
4. **Resource Management**: CPU, memory, and disk limits

## Technology Stack

### Core Technologies
- **Runtime**: Node.js 18+ 
- **Protocol**: MCP (Model Context Protocol) 2024-11-05
- **Container**: Docker with multi-stage builds
- **Orchestration**: Docker Compose
- **Shell**: Bash 4+ with set -euo pipefail

### Dependencies
- **@modelcontextprotocol/server-filesystem**: Core MCP implementation
- **Standard Unix Tools**: grep, awk, sed, find, etc.
- **Optional Tools**: yamllint, python3 (for YAML validation)

### File Structure
```
/opt/gitquellen/ha-mcp-server/
├── scripts/                  # Core functionality scripts
│   ├── security-utils.sh     # Security validation
│   ├── cache-manager.sh      # Performance caching  
│   ├── circuit-breaker.sh    # Fault tolerance
│   ├── health-check.sh       # System monitoring
│   ├── monitor.sh            # Continuous monitoring
│   ├── backup.sh             # Data backup
│   ├── logger.sh             # Logging utilities
│   └── validate-config.sh    # Configuration validation
├── tests/                    # Test suite
│   ├── unit/                 # Unit tests
│   ├── integration/          # Integration tests
│   └── e2e/                  # End-to-end tests
├── docs/                     # Documentation
│   ├── API.md                # API documentation
│   ├── ARCHITECTURE.md       # This document
│   └── TROUBLESHOOTING.md    # Problem resolution
├── .github/                  # CI/CD workflows
│   └── workflows/
├── docker-compose.yml        # Container orchestration
├── Dockerfile               # Container definition
└── README.md                # Project overview
```

## Integration Points

### Home Assistant Integration
- **Config Directory**: Read/write access to HA configuration
- **File Types**: YAML, Python, JSON configuration files
- **Validation**: YAML syntax checking before modifications
- **Backup**: Automatic backup before changes

### Claude Integration
- **Protocol**: MCP over stdio/pipes
- **Operations**: File read, write, list, directory operations
- **Security**: All operations filtered through security layer
- **Caching**: Intelligent caching of frequently accessed files

## Future Enhancements

### Planned Features
1. **Web Dashboard**: Real-time monitoring interface
2. **Multi-tenant Support**: Support multiple HA instances
3. **Advanced Analytics**: Performance and usage analytics  
4. **Plugin System**: Extensible functionality
5. **High Availability**: Multi-instance deployment

### API Evolution
1. **REST API**: Additional HTTP endpoints
2. **WebSocket Support**: Real-time communication
3. **GraphQL**: Flexible query interface
4. **Metrics Export**: Prometheus/Grafana integration

## Configuration Management

### Environment-Based Configuration
- **Development**: Local testing with mock data
- **Production**: Full security and monitoring enabled
- **Testing**: Automated test environment

### Configuration Sources
1. **Environment Variables**: Runtime configuration
2. **Config Files**: Structured settings
3. **Command Line**: Override parameters
4. **Defaults**: Sensible default values

This architecture provides a robust, secure, and scalable foundation for Claude's interaction with Home Assistant configurations while maintaining high availability and performance.