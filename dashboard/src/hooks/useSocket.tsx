import React, { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { io, Socket } from 'socket.io-client';
import { DashboardData } from '../types';

interface SocketContextType {
  socket: Socket | null;
  connected: boolean;
  dashboardData: DashboardData | null;
}

const SocketContext = createContext<SocketContextType>({
  socket: null,
  connected: false,
  dashboardData: null,
});

export const useSocket = () => {
  const context = useContext(SocketContext);
  if (!context) {
    throw new Error('useSocket must be used within a SocketProvider');
  }
  return context;
};

interface SocketProviderProps {
  children: ReactNode;
}

export const SocketProvider: React.FC<SocketProviderProps> = ({ children }) => {
  const [socket, setSocket] = useState<Socket | null>(null);
  const [connected, setConnected] = useState(false);
  const [dashboardData, setDashboardData] = useState<DashboardData | null>(null);

  useEffect(() => {
    // Detect if running in Ingress mode
    const isIngress = window.location.pathname.startsWith('/dashboard');
    const socketUrl = isIngress 
      ? `${window.location.protocol}//${window.location.host}`
      : 'http://localhost:3000';
    
    // Initialize socket connection
    const newSocket = io(socketUrl, {
      transports: ['websocket', 'polling'],
      autoConnect: true,
      path: isIngress ? '/socket.io/' : '/socket.io/',
    });

    newSocket.on('connect', () => {
      console.log('Connected to MCP Server');
      setConnected(true);
    });

    newSocket.on('disconnect', () => {
      console.log('Disconnected from MCP Server');
      setConnected(false);
    });

    // Listen for dashboard data updates
    newSocket.on('dashboard_update', (data: DashboardData) => {
      setDashboardData(data);
    });

    // Listen for individual metric updates
    newSocket.on('metrics_update', (metrics) => {
      setDashboardData(prev => prev ? { ...prev, systemMetrics: metrics } : null);
    });

    newSocket.on('health_update', (health) => {
      setDashboardData(prev => prev ? { ...prev, healthReport: health } : null);
    });

    newSocket.on('cache_update', (cache) => {
      setDashboardData(prev => prev ? { ...prev, cacheStats: cache } : null);
    });

    newSocket.on('logs_update', (logs) => {
      setDashboardData(prev => prev ? { ...prev, recentLogs: logs } : null);
    });

    setSocket(newSocket);

    // Cleanup on unmount
    return () => {
      newSocket.close();
    };
  }, []);

  return (
    <SocketContext.Provider value={{ socket, connected, dashboardData }}>
      {children}
    </SocketContext.Provider>
  );
};