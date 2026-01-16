import React from 'react';
import { Cpu, MemoryStick, HardDrive, Clock } from 'lucide-react';
import { SystemMetrics as SystemMetricsType } from '../types';
import MetricCard from './MetricCard';
import { formatDistanceToNow } from 'date-fns';

interface SystemMetricsProps {
  metrics: SystemMetricsType | null;
}

const SystemMetrics: React.FC<SystemMetricsProps> = ({ metrics }) => {
  if (!metrics) {
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="metric-card animate-pulse">
            <div className="h-4 bg-gray-200 rounded w-3/4 mb-4"></div>
            <div className="h-8 bg-gray-200 rounded w-1/2"></div>
          </div>
        ))}
      </div>
    );
  }

  const formatUptime = (timestamp: number) => {
    try {
      return formatDistanceToNow(timestamp, { addSuffix: false });
    } catch {
      return 'Unknown';
    }
  };

  const getStatusFromPercentage = (percentage: number) => {
    if (percentage >= 90) return 'error';
    if (percentage >= 80) return 'warning';
    return 'success';
  };

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
      <MetricCard
        title="CPU Usage"
        value={metrics.cpu.toFixed(1)}
        unit="%"
        icon={<Cpu className="w-5 h-5" />}
        status={getStatusFromPercentage(metrics.cpu)}
      />
      
      <MetricCard
        title="Memory Usage"
        value={metrics.memory.percentage}
        unit="%"
        changeLabel={`${(metrics.memory.used / 1024 / 1024 / 1024).toFixed(1)}GB / ${(metrics.memory.total / 1024 / 1024 / 1024).toFixed(1)}GB`}
        icon={<MemoryStick className="w-5 h-5" />}
        status={getStatusFromPercentage(metrics.memory.percentage)}
      />
      
      <MetricCard
        title="Disk Usage"
        value={metrics.disk.percentage}
        unit="%"
        changeLabel={`${metrics.disk.used} / ${metrics.disk.total}`}
        icon={<HardDrive className="w-5 h-5" />}
        status={getStatusFromPercentage(metrics.disk.percentage)}
      />
      
      <MetricCard
        title="Uptime"
        value={formatUptime(metrics.uptime)}
        icon={<Clock className="w-5 h-5" />}
        status="neutral"
      />
    </div>
  );
};

export default SystemMetrics;