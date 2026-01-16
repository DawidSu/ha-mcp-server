import React, { useState, useEffect, useRef } from 'react';
import { Terminal, Filter, Download, RefreshCw, Search } from 'lucide-react';
import { LogEntry } from '../types';
import { format } from 'date-fns';

interface LogViewerProps {
  logs: LogEntry[];
  className?: string;
}

const LogViewer: React.FC<LogViewerProps> = ({ logs, className = '' }) => {
  const [filteredLogs, setFilteredLogs] = useState<LogEntry[]>([]);
  const [levelFilter, setLevelFilter] = useState<string>('all');
  const [searchFilter, setSearchFilter] = useState<string>('');
  const [autoScroll, setAutoScroll] = useState<boolean>(true);
  const logsEndRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let filtered = logs;

    // Filter by level
    if (levelFilter !== 'all') {
      filtered = filtered.filter(log => 
        log.level.toLowerCase() === levelFilter.toLowerCase()
      );
    }

    // Filter by search term
    if (searchFilter.trim()) {
      const searchTerm = searchFilter.toLowerCase();
      filtered = filtered.filter(log =>
        log.message.toLowerCase().includes(searchTerm) ||
        (log.source && log.source.toLowerCase().includes(searchTerm))
      );
    }

    setFilteredLogs(filtered);
  }, [logs, levelFilter, searchFilter]);

  useEffect(() => {
    if (autoScroll && logsEndRef.current) {
      logsEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [filteredLogs, autoScroll]);

  const getLevelColor = (level: string) => {
    switch (level.toUpperCase()) {
      case 'ERROR':
      case 'CRITICAL':
        return 'text-error-600 bg-error-50';
      case 'WARN':
      case 'WARNING':
        return 'text-warning-600 bg-warning-50';
      case 'INFO':
        return 'text-primary-600 bg-primary-50';
      case 'DEBUG':
        return 'text-gray-600 bg-gray-50';
      default:
        return 'text-gray-600 bg-gray-50';
    }
  };

  const handleExport = () => {
    const logText = filteredLogs
      .map(log => `[${format(log.timestamp, 'yyyy-MM-dd HH:mm:ss')}] ${log.level}: ${log.message}`)
      .join('\\n');
    
    const blob = new Blob([logText], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `mcp-logs-${format(Date.now(), 'yyyy-MM-dd-HHmmss')}.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const handleScroll = () => {
    if (containerRef.current) {
      const { scrollTop, scrollHeight, clientHeight } = containerRef.current;
      const isAtBottom = scrollTop + clientHeight >= scrollHeight - 10;
      setAutoScroll(isAtBottom);
    }
  };

  return (
    <div className={`card ${className}`}>
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-4">
        <div className="flex items-center space-x-3">
          <Terminal className="w-6 h-6 text-gray-700" />
          <h3 className="text-lg font-semibold text-gray-900">System Logs</h3>
          <span className="status-badge bg-gray-50 text-gray-600">
            {filteredLogs.length} entries
          </span>
        </div>
        
        <div className="flex items-center space-x-2">
          <button
            onClick={handleExport}
            className="btn-secondary text-sm"
            title="Export logs"
          >
            <Download className="w-4 h-4" />
          </button>
          
          <button
            onClick={() => setAutoScroll(!autoScroll)}
            className={`btn-secondary text-sm ${autoScroll ? 'bg-primary-50 text-primary-700 border-primary-300' : ''}`}
            title="Toggle auto-scroll"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      <div className="flex flex-col sm:flex-row gap-4 mb-4">
        <div className="flex items-center space-x-2">
          <Filter className="w-4 h-4 text-gray-500" />
          <select
            value={levelFilter}
            onChange={(e) => setLevelFilter(e.target.value)}
            className="text-sm border-gray-300 rounded-md focus:ring-primary-500 focus:border-primary-500"
          >
            <option value="all">All Levels</option>
            <option value="error">Error</option>
            <option value="warn">Warning</option>
            <option value="info">Info</option>
            <option value="debug">Debug</option>
          </select>
        </div>
        
        <div className="flex-1 max-w-sm">
          <div className="relative">
            <Search className="w-4 h-4 absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400" />
            <input
              type="text"
              placeholder="Search logs..."
              value={searchFilter}
              onChange={(e) => setSearchFilter(e.target.value)}
              className="w-full pl-10 text-sm border-gray-300 rounded-md focus:ring-primary-500 focus:border-primary-500"
            />
          </div>
        </div>
      </div>

      <div
        ref={containerRef}
        onScroll={handleScroll}
        className="bg-gray-900 rounded-lg p-4 h-96 overflow-y-auto font-mono text-sm text-gray-100"
      >
        {filteredLogs.length === 0 ? (
          <div className="text-center py-8 text-gray-400">
            {logs.length === 0 ? 'No logs available' : 'No logs match current filters'}
          </div>
        ) : (
          <div className="space-y-1">
            {filteredLogs.map((log, index) => (
              <div key={`${log.timestamp}-${index}`} className="flex items-start space-x-3 py-1 hover:bg-gray-800 rounded px-2 -mx-2">
                <span className="text-gray-400 text-xs w-20 flex-shrink-0 mt-0.5">
                  {format(log.timestamp, 'HH:mm:ss')}
                </span>
                <span className={`text-xs px-2 py-0.5 rounded flex-shrink-0 mt-0.5 ${getLevelColor(log.level)}`}>
                  {log.level}
                </span>
                {log.source && (
                  <span className="text-blue-400 text-xs flex-shrink-0 mt-0.5">
                    [{log.source}]
                  </span>
                )}
                <span className="text-gray-100 break-all flex-1">
                  {log.message}
                </span>
              </div>
            ))}
            <div ref={logsEndRef} />
          </div>
        )}
      </div>
      
      {!autoScroll && (
        <button
          onClick={() => {
            setAutoScroll(true);
            logsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
          }}
          className="mt-2 btn-secondary text-sm w-full"
        >
          Jump to bottom
        </button>
      )}
    </div>
  );
};

export default LogViewer;