# Troubleshooting Guide

## Common Issues and Solutions

### MCP Server Issues

#### Issue: MCP Server Won't Start
**Symptoms:**
- `npx: command not found`
- `server-filesystem package not found`
- Container exits immediately

**Solutions:**
```bash
# Check if Node.js is installed
node --version
npm --version

# Install MCP server package manually
npm install -g @modelcontextprotocol/server-filesystem

# Check Docker logs
docker logs homeassistant-mcp-server

# Run health check
./scripts/health-check.sh
```

#### Issue: Permission Denied Errors
**Symptoms:**
- `EACCES: permission denied`
- Health check shows permission issues

**Solutions:**
```bash
# Fix file permissions
sudo chown -R $(id -u):$(id -g) /config
chmod -R 755 /config

# Check Docker volume permissions
ls -la /config
```

### Performance Issues

#### Issue: High Memory Usage
**Symptoms:**
- Health check shows memory warnings
- Container being killed (OOMKilled)

**Solutions:**
```bash
# Check current memory usage
./scripts/health-check.sh check memory_usage

# Clear cache
./scripts/cache-manager.sh clear

# Restart with more memory
docker-compose down
docker-compose up -d
```

#### Issue: Slow File Operations
**Solutions:**
```bash
# Enable caching
export CACHE_ENABLED=true
./scripts/cache-manager.sh init

# Check disk space
df -h /config

# Run performance test
time ls -la /config
```

### Configuration Issues

#### Issue: YAML Validation Errors
**Solutions:**
```bash
# Check YAML syntax
./scripts/health-check.sh check yaml_syntax

# Validate specific file
python3 -c "import yaml; yaml.safe_load(open('/config/configuration.yaml'))"

# Fix common YAML issues:
# - Check indentation (2 spaces, no tabs)
# - Check quotes and special characters
# - Validate file encoding (UTF-8)
```

### Network Issues

#### Issue: Network Connectivity Problems
**Solutions:**
```bash
# Test network connectivity
./scripts/health-check.sh check network_connectivity

# Check DNS resolution
nslookup google.com

# Test from container
docker exec homeassistant-mcp-server ping -c 3 8.8.8.8
```

### Circuit Breaker Issues

#### Issue: Circuit Breaker Stuck Open
**Solutions:**
```bash
# Check circuit breaker status
./scripts/circuit-breaker.sh status

# Reset circuit breaker (restart service)
docker-compose restart ha-mcp-server

# Adjust thresholds if needed
export CB_FAILURE_THRESHOLD=10
export CB_RECOVERY_TIMEOUT=120
```

## Diagnostic Commands

### Quick Health Check
```bash
./scripts/health-check.sh all
```

### Performance Analysis
```bash
# Cache statistics
./scripts/cache-manager.sh stats

# System resources
docker stats homeassistant-mcp-server

# Disk usage
du -sh /config/*
```

### Log Analysis
```bash
# Container logs
docker logs -f homeassistant-mcp-server

# System logs
journalctl -u docker -f

# Health check logs
./scripts/health-check.sh all --verbose
```

## Emergency Recovery

### Service Recovery
```bash
# Full restart
docker-compose down
docker-compose pull
docker-compose up -d

# Reset all caches and state
./scripts/cache-manager.sh clear
rm -rf /tmp/mcp-*
```

### Backup Recovery
```bash
# List available backups
./scripts/backup.sh list

# Restore from backup
./scripts/backup.sh restore backup_20240116_103000
```

## Getting Help

1. **Check logs first**: `docker logs homeassistant-mcp-server`
2. **Run health checks**: `./scripts/health-check.sh all`
3. **Check documentation**: [API.md](API.md), [ARCHITECTURE.md](ARCHITECTURE.md)
4. **Report issues**: Include health check output and logs