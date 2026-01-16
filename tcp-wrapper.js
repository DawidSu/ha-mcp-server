#!/usr/bin/env node

const net = require('net');
const { spawn } = require('child_process');

const PORT = process.env.MCP_PORT || 3000;
const CONFIG_PATH = process.argv[2] || '/config';

console.log(`Starting MCP TCP Server on port ${PORT}`);
console.log(`Home Assistant config path: ${CONFIG_PATH}`);

const server = net.createServer((socket) => {
    console.log('Client connected:', socket.remoteAddress);
    
    // Start MCP server process for this connection
    const mcpProcess = spawn('npx', ['-y', '@modelcontextprotocol/server-filesystem', CONFIG_PATH], {
        stdio: ['pipe', 'pipe', 'pipe']
    });
    
    // Pipe socket data to MCP process stdin
    socket.pipe(mcpProcess.stdin);
    
    // Pipe MCP process stdout to socket
    mcpProcess.stdout.pipe(socket);
    
    // Handle process errors
    mcpProcess.stderr.on('data', (data) => {
        console.error('MCP Error:', data.toString());
    });
    
    mcpProcess.on('error', (err) => {
        console.error('MCP Process Error:', err);
        socket.end();
    });
    
    mcpProcess.on('exit', (code) => {
        console.log('MCP Process exited with code:', code);
        socket.end();
    });
    
    // Handle socket close
    socket.on('close', () => {
        console.log('Client disconnected');
        mcpProcess.kill();
    });
    
    socket.on('error', (err) => {
        console.error('Socket error:', err);
        mcpProcess.kill();
    });
});

server.listen(PORT, () => {
    console.log(`✓ MCP TCP Server listening on port ${PORT}`);
    console.log(`Connect Claude to: tcp://localhost:${PORT}`);
});

server.on('error', (err) => {
    console.error('Server error:', err);
    process.exit(1);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('Received SIGTERM, shutting down gracefully');
    server.close(() => {
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('Received SIGINT, shutting down gracefully');
    server.close(() => {
        process.exit(0);
    });
});