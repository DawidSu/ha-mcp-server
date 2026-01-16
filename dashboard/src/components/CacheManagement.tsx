import React, { useState } from 'react';
import { Database, Trash2, BarChart3, RefreshCw, Settings } from 'lucide-react';
import { CacheStats } from '../types';
import axios from 'axios';

interface CacheManagementProps {
  cacheStats: CacheStats | null;
  onCacheCleared?: () => void;
  className?: string;
}

const CacheManagement: React.FC<CacheManagementProps> = ({ 
  cacheStats, 
  onCacheCleared,
  className = '' 
}) => {
  const [isClearing, setIsClearing] = useState(false);
  const [showDetails, setShowDetails] = useState(false);

  const handleClearCache = async () => {
    setIsClearing(true);
    try {
      await axios.post('/api/cache/clear');
      onCacheCleared?.();
    } catch (error) {
      console.error('Failed to clear cache:', error);
    } finally {
      setIsClearing(false);
    }
  };

  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const formatPercentage = (value: number, max: number) => {
    if (max === 0) return 0;
    return Math.round((value / max) * 100);
  };

  if (!cacheStats) {
    return (
      <div className={`card ${className}`}>
        <div className="flex items-center space-x-3 mb-4">
          <Database className="w-6 h-6 text-gray-400" />
          <h3 className="text-lg font-semibold text-gray-900">Cache Management</h3>
        </div>
        
        <div className="animate-pulse">
          <div className="h-4 bg-gray-200 rounded w-1/2 mb-4"></div>
          <div className="space-y-3">
            <div className="h-3 bg-gray-200 rounded"></div>
            <div className="h-3 bg-gray-200 rounded w-3/4"></div>
            <div className="h-3 bg-gray-200 rounded w-1/2"></div>
          </div>
        </div>
      </div>
    );
  }

  const hitRateColor = cacheStats.hitRate >= 80 ? 'text-success-600' : 
                     cacheStats.hitRate >= 60 ? 'text-warning-600' : 'text-error-600';

  const sizePercentage = formatPercentage(cacheStats.size, cacheStats.maxSize);
  const entriesPercentage = formatPercentage(cacheStats.entries, cacheStats.maxEntries);

  return (
    <div className={`card ${className}`}>
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center space-x-3">
          <Database className="w-6 h-6 text-gray-700" />
          <h3 className="text-lg font-semibold text-gray-900">Cache Management</h3>
          <span className={`status-badge ${cacheStats.enabled ? 'bg-success-50 text-success-600' : 'bg-gray-50 text-gray-600'}`}>
            {cacheStats.enabled ? 'Enabled' : 'Disabled'}
          </span>
        </div>
        
        <div className="flex items-center space-x-2">
          <button
            onClick={() => setShowDetails(!showDetails)}
            className="btn-secondary text-sm"
            title="Toggle details"
          >
            <BarChart3 className="w-4 h-4" />
          </button>
          
          <button
            onClick={handleClearCache}
            disabled={isClearing || !cacheStats.enabled}
            className="btn-secondary text-sm text-error-600 hover:bg-error-50 disabled:opacity-50"
            title="Clear cache"
          >
            {isClearing ? (
              <RefreshCw className="w-4 h-4 animate-spin" />
            ) : (
              <Trash2 className="w-4 h-4" />
            )}
          </button>
        </div>
      </div>

      {/* Key Metrics */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        <div className="text-center p-4 bg-gray-50 rounded-lg">
          <div className={`text-2xl font-bold ${hitRateColor}`}>
            {cacheStats.hitRate.toFixed(1)}%
          </div>
          <div className="text-sm text-gray-500">Hit Rate</div>
          <div className="text-xs text-gray-400 mt-1">
            {cacheStats.hits.toLocaleString()} / {cacheStats.totalRequests.toLocaleString()}
          </div>
        </div>
        
        <div className="text-center p-4 bg-gray-50 rounded-lg">
          <div className="text-2xl font-bold text-gray-900">
            {formatBytes(cacheStats.size)}
          </div>
          <div className="text-sm text-gray-500">Cache Size</div>
          <div className="text-xs text-gray-400 mt-1">
            {sizePercentage}% of {formatBytes(cacheStats.maxSize)}
          </div>
        </div>
        
        <div className="text-center p-4 bg-gray-50 rounded-lg">
          <div className="text-2xl font-bold text-gray-900">
            {cacheStats.entries.toLocaleString()}
          </div>
          <div className="text-sm text-gray-500">Entries</div>
          <div className="text-xs text-gray-400 mt-1">
            {entriesPercentage}% of {cacheStats.maxEntries.toLocaleString()}
          </div>
        </div>
      </div>

      {/* Progress Bars */}
      <div className="space-y-4 mb-6">
        <div>
          <div className="flex justify-between text-sm text-gray-600 mb-2">
            <span>Storage Usage</span>
            <span>{sizePercentage}%</span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-2">
            <div
              className={`h-2 rounded-full transition-all duration-300 ${
                sizePercentage >= 90 ? 'bg-error-500' :
                sizePercentage >= 70 ? 'bg-warning-500' : 'bg-success-500'
              }`}
              style={{ width: `${Math.min(sizePercentage, 100)}%` }}
            ></div>
          </div>
        </div>

        <div>
          <div className="flex justify-between text-sm text-gray-600 mb-2">
            <span>Entry Count</span>
            <span>{entriesPercentage}%</span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-2">
            <div
              className={`h-2 rounded-full transition-all duration-300 ${
                entriesPercentage >= 90 ? 'bg-error-500' :
                entriesPercentage >= 70 ? 'bg-warning-500' : 'bg-success-500'
              }`}
              style={{ width: `${Math.min(entriesPercentage, 100)}%` }}
            ></div>
          </div>
        </div>
      </div>

      {/* Detailed Statistics */}
      {showDetails && (
        <div className="border-t pt-4">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
            <div>
              <div className="text-gray-500">Hits</div>
              <div className="font-semibold text-success-600">
                {cacheStats.hits.toLocaleString()}
              </div>
            </div>
            
            <div>
              <div className="text-gray-500">Misses</div>
              <div className="font-semibold text-error-600">
                {cacheStats.misses.toLocaleString()}
              </div>
            </div>
            
            <div>
              <div className="text-gray-500">Sets</div>
              <div className="font-semibold text-blue-600">
                {cacheStats.sets.toLocaleString()}
              </div>
            </div>
            
            <div>
              <div className="text-gray-500">Evictions</div>
              <div className="font-semibold text-warning-600">
                {cacheStats.evictions.toLocaleString()}
              </div>
            </div>
            
            <div>
              <div className="text-gray-500">Deletes</div>
              <div className="font-semibold text-gray-600">
                {cacheStats.deletes.toLocaleString()}
              </div>
            </div>
            
            <div>
              <div className="text-gray-500">TTL</div>
              <div className="font-semibold text-gray-900">
                {cacheStats.ttl}s
              </div>
            </div>
            
            <div className="sm:col-span-2">
              <div className="text-gray-500">Total Requests</div>
              <div className="font-semibold text-gray-900">
                {cacheStats.totalRequests.toLocaleString()}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Cache Status Warning */}
      {!cacheStats.enabled && (
        <div className="mt-4 p-3 bg-warning-50 border border-warning-200 rounded-lg">
          <div className="flex items-center space-x-2">
            <Settings className="w-4 h-4 text-warning-600" />
            <span className="text-sm text-warning-700">
              Cache is currently disabled. Enable it to improve performance.
            </span>
          </div>
        </div>
      )}
    </div>
  );
};

export default CacheManagement;