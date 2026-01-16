# HA MCP Server Dashboard

A modern, responsive web dashboard for monitoring and managing the Home Assistant MCP Server.

## Features

### 🚀 **Real-time Monitoring**
- Live system metrics (CPU, Memory, Disk usage)
- Performance charts with historical data
- Real-time WebSocket updates every 5 seconds

### 🏥 **Health Monitoring** 
- Comprehensive health checks visualization
- System component status tracking
- Alert indicators for warnings and critical issues

### 📊 **Cache Management**
- Cache statistics and hit rate monitoring
- Interactive cache management controls
- Storage and performance optimization insights

### 📋 **Log Management**
- Real-time log streaming
- Advanced filtering (level, search terms)
- Log export functionality
- Terminal-style viewer with syntax highlighting

### 📱 **Responsive Design**
- Mobile-first responsive layout
- Modern Material Design principles
- Dark/light theme ready
- Accessible interface

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   React SPA     │    │   Express API   │    │  MCP Scripts    │
│   (Frontend)    │◄───┤   (Backend)     │◄───┤   (Data)       │
│   Port: 3001    │    │   Port: 3000    │    │   /opt/scripts  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                        ▲
         │                        │
         ▼                        ▼
┌─────────────────┐    ┌─────────────────┐
│   WebSocket     │    │   Health Checks │
│   Real-time     │    │   System Stats  │
│   Updates       │    │   Cache Mgmt    │
└─────────────────┘    └─────────────────┘
```

## Quick Start

### Using Docker Compose (Recommended)

1. **Start the complete stack:**
```bash
docker-compose up -d
```

2. **Access the dashboard:**
- Frontend: http://localhost:3001
- API: http://localhost:3000

### Manual Setup

1. **Install dependencies:**
```bash
# Frontend
cd dashboard
npm install

# API  
cd api
npm install
```

2. **Build frontend:**
```bash
npm run build
```

3. **Start services:**
```bash
# Start API (Terminal 1)
cd api && npm start

# Start frontend (Terminal 2)  
cd dashboard && npm start
```

## API Endpoints

### Health & Monitoring
- `GET /api/health` - System health status
- `GET /api/metrics` - System performance metrics
- `GET /api/dashboard` - Combined dashboard data

### Cache Management
- `GET /api/cache` - Cache statistics
- `POST /api/cache/clear` - Clear cache

### Logs & Circuit Breakers
- `GET /api/logs` - Recent system logs
- `GET /api/circuit-breakers` - Circuit breaker status

### WebSocket Events
- `dashboard_update` - Complete dashboard data
- `metrics_update` - System metrics only
- `health_update` - Health status only
- `cache_update` - Cache statistics only
- `logs_update` - New log entries

## Configuration

### Environment Variables

```bash
# API Configuration
DASHBOARD_PORT=3000          # API server port
FRONTEND_PORT=3001           # Frontend server port  
NODE_ENV=production          # Environment mode
MCP_SERVER_URL=http://localhost:3000  # MCP server URL

# Update Intervals
MONITOR_INTERVAL=5000        # WebSocket update interval (ms)
LOG_LEVEL=info               # Logging level

# Cache Settings (inherited from main MCP server)
CACHE_ENABLED=true
CACHE_DEFAULT_TTL=300
CACHE_MAX_SIZE=104857600

# Health Check Thresholds
HC_DISK_WARNING_THRESHOLD=80
HC_MEMORY_WARNING_THRESHOLD=80
```

### Docker Configuration

The dashboard is automatically included in the main `docker-compose.yml`:

```yaml
dashboard:
  build:
    context: ./dashboard
    dockerfile: Dockerfile
  container_name: mcp-dashboard
  ports:
    - "3001:3001"  # Frontend
    - "3000:3000"  # API
  volumes:
    - ./scripts:/opt/scripts:ro
    - ./logs:/var/log:ro
  depends_on:
    - ha-mcp-server
```

## Screenshots

### Main Dashboard
![Dashboard Overview](docs/screenshots/dashboard-overview.png)

### Health Status
![Health Status](docs/screenshots/health-status.png) 

### Cache Management
![Cache Management](docs/screenshots/cache-management.png)

### Log Viewer
![Log Viewer](docs/screenshots/log-viewer.png)

## Development

### Tech Stack
- **Frontend:** React 18 + TypeScript + Tailwind CSS
- **Charts:** Recharts for data visualization  
- **Icons:** Lucide React
- **Backend:** Express.js + Socket.io
- **Real-time:** WebSocket connections

### File Structure
```
dashboard/
├── src/
│   ├── components/          # React components
│   │   ├── MetricCard.tsx
│   │   ├── SystemMetrics.tsx
│   │   ├── PerformanceChart.tsx
│   │   ├── HealthStatus.tsx
│   │   ├── CacheManagement.tsx
│   │   └── LogViewer.tsx
│   ├── hooks/               # React hooks
│   │   └── useSocket.tsx
│   ├── pages/               # Page components
│   │   └── Dashboard.tsx
│   ├── types/               # TypeScript types
│   │   └── index.ts
│   └── utils/               # Utility functions
├── api/                     # Express API server
│   ├── server.js
│   └── package.json
├── public/                  # Static files
├── Dockerfile               # Multi-stage build
├── start.sh                # Container startup script
└── README.md               # This file
```

### Adding New Features

1. **New API Endpoint:**
```javascript
// api/server.js
app.get('/api/my-feature', async (req, res) => {
  try {
    const data = await getMyFeatureData();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
```

2. **New React Component:**
```typescript
// src/components/MyComponent.tsx
import React from 'react';

interface MyComponentProps {
  data: MyDataType;
}

const MyComponent: React.FC<MyComponentProps> = ({ data }) => {
  return (
    <div className="card">
      {/* Your component JSX */}
    </div>
  );
};

export default MyComponent;
```

3. **Add to Dashboard:**
```typescript
// src/pages/Dashboard.tsx
import MyComponent from '../components/MyComponent';

// In component:
<MyComponent data={dashboardData?.myFeature} />
```

## Performance Optimization

### Caching Strategy
- API responses cached for 5 seconds
- Frontend state optimized with React hooks
- WebSocket updates batched for efficiency

### Bundle Optimization
- Code splitting with React.lazy()
- Tree shaking with modern build tools
- Compressed assets in production

### Monitoring
- Real-time performance metrics
- Error boundary for graceful error handling
- Automated health checks

## Troubleshooting

### Common Issues

**Dashboard not loading:**
```bash
# Check if containers are running
docker ps | grep dashboard

# Check logs
docker logs mcp-dashboard

# Verify ports are available
netstat -tulpn | grep :300[01]
```

**API connection errors:**
```bash
# Test API health
curl http://localhost:3000/health

# Check scripts directory
ls -la /opt/scripts/

# Verify permissions
docker exec mcp-dashboard ls -la /opt/scripts/
```

**WebSocket connection issues:**
```bash
# Check Socket.io connection
curl -X POST http://localhost:3000/socket.io/?transport=polling

# Browser console should show:
# "Connected to MCP Server"
```

**Cache not updating:**
```bash
# Manual cache clear
curl -X POST http://localhost:3000/api/cache/clear

# Check cache stats  
curl http://localhost:3000/api/cache
```

### Performance Issues

**Slow chart rendering:**
- Reduce historical data points (default: 50)
- Increase update interval in production
- Use chart virtualization for large datasets

**High memory usage:**
- Monitor WebSocket connection count
- Check for memory leaks in browser dev tools
- Restart dashboard container if needed

## Security Considerations

### Network Security
- Dashboard runs on internal network only
- No external API access required
- Read-only access to MCP scripts
- Docker socket access for monitoring only

### Data Security  
- No sensitive data stored in frontend
- Logs filtered to remove secrets
- Cache cleared periodically
- Secure WebSocket connections

## Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am 'Add my feature'`
4. Push branch: `git push origin feature/my-feature`  
5. Submit Pull Request

## License

MIT License - see main project LICENSE file.

---

**Dashboard Version:** 1.0.0  
**Last Updated:** 2024-01-16  
**Compatibility:** HA MCP Server v1.0.0+