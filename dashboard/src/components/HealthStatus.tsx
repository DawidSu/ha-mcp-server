import React from 'react';
import { CheckCircle, AlertTriangle, XCircle, Clock, Activity } from 'lucide-react';
import { HealthReport, HealthCheck } from '../types';
import { format } from 'date-fns';

interface HealthStatusProps {
  healthReport: HealthReport | null;
  className?: string;
}

const HealthStatus: React.FC<HealthStatusProps> = ({ healthReport, className = '' }) => {
  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'OK':
        return <CheckCircle className="w-5 h-5 text-success-500" />;
      case 'WARNING':
        return <AlertTriangle className="w-5 h-5 text-warning-500" />;
      case 'CRITICAL':
        return <XCircle className="w-5 h-5 text-error-500" />;
      default:
        return <Clock className="w-5 h-5 text-gray-500" />;
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'OK':
        return 'status-ok';
      case 'WARNING':
        return 'status-warning';
      case 'CRITICAL':
        return 'status-error';
      default:
        return 'status-badge bg-gray-50 text-gray-600';
    }
  };

  const getOverallStatusColor = (status: string) => {
    switch (status) {
      case 'OK':
        return 'border-success-200 bg-success-50';
      case 'WARNING':
        return 'border-warning-200 bg-warning-50';
      case 'CRITICAL':
        return 'border-error-200 bg-error-50';
      default:
        return 'border-gray-200 bg-gray-50';
    }
  };

  if (!healthReport) {
    return (
      <div className={`card ${className}`}>
        <div className="flex items-center space-x-3 mb-4">
          <Activity className="w-6 h-6 text-gray-400" />
          <h3 className="text-lg font-semibold text-gray-900">System Health</h3>
        </div>
        
        <div className="animate-pulse space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="flex items-center space-x-3">
              <div className="w-5 h-5 bg-gray-200 rounded-full"></div>
              <div className="flex-1">
                <div className="h-4 bg-gray-200 rounded w-1/3 mb-1"></div>
                <div className="h-3 bg-gray-200 rounded w-2/3"></div>
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  const checks = Object.entries(healthReport.checks || {});

  return (
    <div className={`card ${className}`}>
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center space-x-3">
          <Activity className="w-6 h-6 text-gray-700" />
          <h3 className="text-lg font-semibold text-gray-900">System Health</h3>
        </div>
        
        <div className="text-right">
          <div className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-medium border ${getOverallStatusColor(healthReport.overallStatus)}`}>
            {getStatusIcon(healthReport.overallStatus)}
            <span className="ml-2">{healthReport.overallStatus}</span>
          </div>
          <p className="text-xs text-gray-500 mt-1">
            {format(healthReport.timestamp, 'MMM dd, HH:mm:ss')}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        <div className="text-center p-3 bg-gray-50 rounded-lg">
          <div className="text-2xl font-bold text-gray-900">{healthReport.checksTotal}</div>
          <div className="text-sm text-gray-500">Total Checks</div>
        </div>
        
        <div className="text-center p-3 bg-success-50 rounded-lg">
          <div className="text-2xl font-bold text-success-600">{healthReport.checksPassed}</div>
          <div className="text-sm text-gray-500">Passed</div>
        </div>
        
        <div className="text-center p-3 bg-warning-50 rounded-lg">
          <div className="text-2xl font-bold text-warning-600">
            {healthReport.checksWarnings + healthReport.checksCritical}
          </div>
          <div className="text-sm text-gray-500">Issues</div>
        </div>
      </div>

      <div className="space-y-3">
        {checks.map(([name, check]) => (
          <div key={name} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors">
            <div className="flex items-center space-x-3 flex-1">
              {getStatusIcon(check.status)}
              <div className="flex-1 min-w-0">
                <div className="flex items-center space-x-2">
                  <h4 className="text-sm font-medium text-gray-900 capitalize">
                    {name.replace(/_/g, ' ')}
                  </h4>
                  <span className={`${getStatusBadge(check.status)} text-xs`}>
                    {check.status}
                  </span>
                </div>
                <p className="text-sm text-gray-600 truncate">
                  {check.message}
                </p>
              </div>
            </div>
            
            {check.value && (
              <div className="text-right ml-3">
                <div className="text-sm font-medium text-gray-900">
                  {check.value}{check.unit && ` ${check.unit}`}
                </div>
              </div>
            )}
          </div>
        ))}
      </div>

      {checks.length === 0 && (
        <div className="text-center py-8 text-gray-500">
          <Activity className="w-12 h-12 mx-auto mb-3 opacity-50" />
          <p>No health checks available</p>
        </div>
      )}
    </div>
  );
};

export default HealthStatus;