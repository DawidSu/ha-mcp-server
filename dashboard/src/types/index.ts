export interface SystemMetrics {
  timestamp: number;
  cpu: number;
  memory: {
    used: number;
    total: number;
    percentage: number;
  };
  disk: {
    used: number;
    total: number;
    percentage: number;
  };
  uptime: number;
}

export interface CacheStats {
  enabled: boolean;
  hitRate: number;
  totalRequests: number;
  hits: number;
  misses: number;
  sets: number;
  deletes: number;
  evictions: number;
  entries: number;
  maxEntries: number;
  size: number;
  maxSize: number;
  ttl: number;
}

export interface HealthCheck {
  name: string;
  status: 'OK' | 'WARNING' | 'CRITICAL' | 'UNKNOWN';
  message: string;
  value?: string;
  unit?: string;
  timestamp: number;
}

export interface HealthReport {
  overallStatus: 'OK' | 'WARNING' | 'CRITICAL';
  timestamp: number;
  checksTotal: number;
  checksPassed: number;
  checksWarnings: number;
  checksCritical: number;
  checks: Record<string, HealthCheck>;
}

export interface CircuitBreakerStatus {
  service: string;
  state: 'CLOSED' | 'OPEN' | 'HALF_OPEN';
  failures: number;
  successCount: number;
  lastFailure?: number;
}

export interface RateLimitInfo {
  enabled: boolean;
  maxRequests: number;
  windowSize: number;
  currentRequests: number;
  resetTime: number;
  blocked: boolean;
}

export interface LogEntry {
  timestamp: number;
  level: 'DEBUG' | 'INFO' | 'WARN' | 'ERROR' | 'CRITICAL';
  message: string;
  source?: string;
  details?: Record<string, any>;
}

export interface DashboardData {
  systemMetrics: SystemMetrics;
  cacheStats: CacheStats;
  healthReport: HealthReport;
  circuitBreakers: CircuitBreakerStatus[];
  rateLimits: RateLimitInfo[];
  recentLogs: LogEntry[];
  activeConnections: number;
  totalRequests: number;
  errorRate: number;
}