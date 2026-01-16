import React, { useState, useEffect } from 'react';
import { Home, Wifi, WifiOff, Settings, Server } from 'lucide-react';
import { useSocket } from '../hooks/useSocket';
import SystemMetrics from '../components/SystemMetrics';
import PerformanceChart from '../components/PerformanceChart';
import HealthStatus from '../components/HealthStatus';
import LogViewer from '../components/LogViewer';
import CacheManagement from '../components/CacheManagement';
import MetricCard from '../components/MetricCard';

interface HistoricalData {
  timestamp: number;
  cpu: number;
  memory: number;
  disk: number;
}

const Dashboard: React.FC = () => {
  const { connected, dashboardData } = useSocket();
  const [historicalData, setHistoricalData] = useState<HistoricalData[]>([]);

  // Update historical data when new metrics arrive
  useEffect(() => {
    if (dashboardData?.systemMetrics) {
      const newDataPoint: HistoricalData = {
        timestamp: dashboardData.systemMetrics.timestamp,
        cpu: dashboardData.systemMetrics.cpu,
        memory: dashboardData.systemMetrics.memory.percentage,
        disk: dashboardData.systemMetrics.disk.percentage,
      };

      setHistoricalData(prev => {
        const updated = [...prev, newDataPoint];
        // Keep only last 50 data points (about 4 minutes at 5s intervals)
        return updated.slice(-50);
      });
    }
  }, [dashboardData?.systemMetrics]);

  const handleCacheCleared = () => {
    // This would typically trigger a refresh of cache stats
    console.log('Cache cleared, refreshing stats...');
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <Home className="w-8 h-8 text-primary-600" />
              <div>
                <h1 className="text-2xl font-bold text-gray-900">
                  HA MCP Server Dashboard
                </h1>
                <p className="text-sm text-gray-500">
                  Home Assistant Model Context Protocol Server
                </p>
              </div>
            </div>
            
            <div className="flex items-center space-x-4">
              <div className="flex items-center space-x-2">
                {connected ? (
                  <>
                    <Wifi className="w-5 h-5 text-success-500" />
                    <span className="text-sm text-success-600 font-medium">Connected</span>
                  </>
                ) : (
                  <>
                    <WifiOff className="w-5 h-5 text-error-500" />
                    <span className="text-sm text-error-600 font-medium">Disconnected</span>
                  </>
                )}
              </div>
              
              <button className="btn-secondary">
                <Settings className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {!connected && (
          <div className="mb-6 p-4 bg-warning-50 border border-warning-200 rounded-lg">
            <div className="flex items-center space-x-2">
              <WifiOff className="w-5 h-5 text-warning-600" />
              <span className="text-sm text-warning-700">
                Dashboard is not connected to the MCP server. Some data may be outdated.
              </span>
            </div>
          </div>
        )}

        {/* Overview Cards */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <MetricCard
            title="Total Requests"
            value={dashboardData?.totalRequests || 0}
            icon={<Server className="w-5 h-5" />}
            status="neutral"
          />
          
          <MetricCard
            title="Error Rate"
            value={dashboardData?.errorRate?.toFixed(2) || '0.0'}
            unit="%"
            status={
              !dashboardData?.errorRate ? 'neutral' :
              dashboardData.errorRate > 5 ? 'error' :
              dashboardData.errorRate > 1 ? 'warning' : 'success'
            }
          />
          
          <MetricCard
            title="Active Connections"
            value={dashboardData?.activeConnections || 0}
            status="success"
          />
          
          <MetricCard
            title="Cache Hit Rate"
            value={dashboardData?.cacheStats?.hitRate?.toFixed(1) || '0.0'}
            unit="%"
            status={
              !dashboardData?.cacheStats ? 'neutral' :
              dashboardData.cacheStats.hitRate >= 80 ? 'success' :
              dashboardData.cacheStats.hitRate >= 60 ? 'warning' : 'error'
            }
          />
        </div>

        {/* System Metrics */}
        <div className="mb-8">
          <SystemMetrics metrics={dashboardData?.systemMetrics || null} />
        </div>

        {/* Performance Chart */}
        <div className="mb-8">
          <PerformanceChart data={historicalData} height={300} />
        </div>

        {/* Two Column Layout */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
          {/* Health Status */}
          <HealthStatus 
            healthReport={dashboardData?.healthReport || null} 
            className="h-fit"
          />
          
          {/* Cache Management */}
          <CacheManagement 
            cacheStats={dashboardData?.cacheStats || null}
            onCacheCleared={handleCacheCleared}
            className="h-fit"
          />
        </div>

        {/* Log Viewer */}
        <LogViewer logs={dashboardData?.recentLogs || []} />
      </main>
    </div>
  );
};

export default Dashboard;