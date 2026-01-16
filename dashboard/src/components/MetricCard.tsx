import React from 'react';
import { TrendingUp, TrendingDown, Minus } from 'lucide-react';

interface MetricCardProps {
  title: string;
  value: string | number;
  unit?: string;
  change?: number;
  changeLabel?: string;
  status?: 'success' | 'warning' | 'error' | 'neutral';
  icon?: React.ReactNode;
  className?: string;
}

const MetricCard: React.FC<MetricCardProps> = ({
  title,
  value,
  unit = '',
  change,
  changeLabel,
  status = 'neutral',
  icon,
  className = ''
}) => {
  const getStatusColor = () => {
    switch (status) {
      case 'success':
        return 'text-success-600 bg-success-50 border-success-200';
      case 'warning':
        return 'text-warning-600 bg-warning-50 border-warning-200';
      case 'error':
        return 'text-error-600 bg-error-50 border-error-200';
      default:
        return 'text-gray-600 bg-white border-gray-200';
    }
  };

  const getTrendIcon = () => {
    if (change === undefined) return null;
    if (change > 0) return <TrendingUp className="w-4 h-4 text-success-500" />;
    if (change < 0) return <TrendingDown className="w-4 h-4 text-error-500" />;
    return <Minus className="w-4 h-4 text-gray-400" />;
  };

  const getTrendColor = () => {
    if (change === undefined) return 'text-gray-500';
    if (change > 0) return 'text-success-600';
    if (change < 0) return 'text-error-600';
    return 'text-gray-500';
  };

  return (
    <div className={`metric-card ${getStatusColor()} ${className}`}>
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-2">
          {icon && <div className="text-gray-500">{icon}</div>}
          <h3 className="text-sm font-medium text-gray-700 truncate">{title}</h3>
        </div>
      </div>
      
      <div className="mt-2">
        <div className="flex items-baseline space-x-1">
          <p className="text-2xl font-semibold text-gray-900">
            {typeof value === 'number' ? value.toLocaleString() : value}
          </p>
          {unit && <span className="text-sm text-gray-500">{unit}</span>}
        </div>
        
        {(change !== undefined || changeLabel) && (
          <div className="flex items-center space-x-1 mt-1">
            {getTrendIcon()}
            <span className={`text-xs font-medium ${getTrendColor()}`}>
              {change !== undefined && (
                <>
                  {change > 0 ? '+' : ''}{change.toFixed(1)}%
                </>
              )}
              {changeLabel && (
                <span className="ml-1 text-gray-500">
                  {changeLabel}
                </span>
              )}
            </span>
          </div>
        )}
      </div>
    </div>
  );
};

export default MetricCard;