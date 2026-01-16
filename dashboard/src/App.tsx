import React from 'react';
import Dashboard from './pages/Dashboard';
import { SocketProvider } from './hooks/useSocket';

function App() {
  return (
    <SocketProvider>
      <div className="min-h-screen bg-gray-50">
        <Dashboard />
      </div>
    </SocketProvider>
  );
}

export default App;