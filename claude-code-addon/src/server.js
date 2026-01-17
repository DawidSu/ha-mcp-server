const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const path = require('path');
const fs = require('fs').promises;
const Anthropic = require('@anthropic-ai/sdk');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const { body, validationResult } = require('express-validator');
const { RateLimiterMemory } = require('rate-limiter-flexible');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Configuration from Home Assistant addon options
const getConfig = () => {
  try {
    const options = JSON.parse(process.env.ADDON_OPTIONS || '{}');
    return {
      apiKey: options.anthropic_api_key || process.env.ANTHROPIC_API_KEY,
      model: options.model || 'claude-3-5-sonnet-20241022',
      maxTokens: options.max_tokens || 4096,
      autoConnectMCP: options.auto_connect_mcp !== false,
      mcpHost: options.mcp_server_host || 'localhost',
      mcpPort: options.mcp_server_port || 3000,
      logLevel: options.log_level || 'info'
    };
  } catch (error) {
    console.error('Error reading addon options:', error);
    return {
      apiKey: process.env.ANTHROPIC_API_KEY,
      model: 'claude-3-5-sonnet-20241022',
      maxTokens: 4096,
      autoConnectMCP: true,
      mcpHost: 'localhost',
      mcpPort: 3000,
      logLevel: 'info'
    };
  }
};

const config = getConfig();
let anthropic;

// Initialize Anthropic client if API key is provided
if (config.apiKey) {
  anthropic = new Anthropic({
    apiKey: config.apiKey
  });
  console.log('✅ Anthropic client initialized');
} else {
  console.warn('⚠️ No Anthropic API key provided - Claude functionality disabled');
}

// Rate limiting
const rateLimiter = new RateLimiterMemory({
  keyPrefix: 'claude_chat',
  points: 10, // Number of requests
  duration: 60, // Per 60 seconds
});

// Middleware
app.use(helmet({
  contentSecurityPolicy: false // Allow inline scripts for chat interface
}));
app.use(compression());
app.use(morgan('combined'));
app.use(express.json({ limit: '10mb' }));
app.use(express.static(path.join(__dirname, 'public')));

// Rate limiting middleware
const rateLimitMiddleware = async (req, res, next) => {
  try {
    const key = req.ip;
    await rateLimiter.consume(key);
    next();
  } catch (rejRes) {
    const totalHits = rejRes.totalHits;
    const remainingTime = Math.round(rejRes.msBeforeNext / 1000);
    res.status(429).json({
      error: 'Too many requests',
      retryAfter: remainingTime
    });
  }
};

// MCP Server connection helper
class MCPConnection {
  constructor() {
    this.connected = false;
    this.ws = null;
  }

  async connect() {
    if (!config.autoConnectMCP) return false;
    
    try {
      const WebSocket = require('ws');
      this.ws = new WebSocket(`ws://${config.mcpHost}:${config.mcpPort}`);
      
      return new Promise((resolve) => {
        this.ws.on('open', () => {
          this.connected = true;
          console.log('✅ Connected to MCP server');
          resolve(true);
        });
        
        this.ws.on('error', (error) => {
          console.warn('⚠️ MCP connection failed:', error.message);
          this.connected = false;
          resolve(false);
        });
      });
    } catch (error) {
      console.warn('⚠️ MCP connection error:', error.message);
      return false;
    }
  }

  disconnect() {
    if (this.ws) {
      this.ws.close();
      this.connected = false;
    }
  }

  async sendCommand(command) {
    if (!this.connected || !this.ws) {
      throw new Error('Not connected to MCP server');
    }
    
    return new Promise((resolve, reject) => {
      this.ws.send(JSON.stringify(command));
      
      const timeout = setTimeout(() => {
        reject(new Error('MCP command timeout'));
      }, 10000);
      
      this.ws.once('message', (data) => {
        clearTimeout(timeout);
        try {
          resolve(JSON.parse(data));
        } catch (error) {
          reject(new Error('Invalid MCP response'));
        }
      });
    });
  }
}

const mcpConnection = new MCPConnection();

// Routes
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/health', (req, res) => {
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    claude: !!anthropic,
    mcp: mcpConnection.connected,
    connections: io.sockets.sockets.size
  });
});

app.get('/api/config', (req, res) => {
  res.json({
    model: config.model,
    maxTokens: config.maxTokens,
    mcpEnabled: config.autoConnectMCP,
    mcpConnected: mcpConnection.connected,
    claudeEnabled: !!anthropic
  });
});

// Chat endpoint
app.post('/api/chat', 
  rateLimitMiddleware,
  [
    body('message').isString().isLength({ min: 1, max: 10000 }),
    body('conversation').optional().isArray()
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Invalid input', details: errors.array() });
    }

    if (!anthropic) {
      return res.status(503).json({ 
        error: 'Claude not available', 
        details: 'No Anthropic API key configured' 
      });
    }

    const { message, conversation = [] } = req.body;
    
    try {
      // Build conversation history
      const messages = [
        ...conversation.map(msg => ({
          role: msg.role,
          content: msg.content
        })),
        {
          role: 'user',
          content: message
        }
      ];

      // Add MCP context if connected
      let systemPrompt = 'You are Claude Code, an AI assistant running in Home Assistant. You can help with Home Assistant configuration, automation, and general coding tasks.';
      
      if (mcpConnection.connected) {
        systemPrompt += ' You have access to the Home Assistant configuration files through the MCP server.';
      }

      const response = await anthropic.messages.create({
        model: config.model,
        max_tokens: config.maxTokens,
        system: systemPrompt,
        messages: messages
      });

      const content = response.content[0]?.text || 'No response generated';
      
      res.json({
        response: content,
        model: config.model,
        usage: {
          input_tokens: response.usage?.input_tokens || 0,
          output_tokens: response.usage?.output_tokens || 0
        }
      });

    } catch (error) {
      console.error('Chat error:', error);
      res.status(500).json({
        error: 'Chat failed',
        details: error.message
      });
    }
  }
);

// WebSocket handling
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);

  socket.emit('status', {
    claude: !!anthropic,
    mcp: mcpConnection.connected,
    model: config.model
  });

  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });

  socket.on('ping', () => {
    socket.emit('pong');
  });
});

// Startup
const PORT = process.env.PORT || 8080;

async function startup() {
  console.log('🚀 Starting Claude Code Addon...');
  console.log(`📋 Model: ${config.model}`);
  console.log(`🔑 API Key: ${config.apiKey ? 'Configured' : 'Missing'}`);
  console.log(`🔗 MCP: ${config.autoConnectMCP ? 'Enabled' : 'Disabled'}`);
  
  if (config.autoConnectMCP) {
    await mcpConnection.connect();
  }
  
  server.listen(PORT, () => {
    console.log(`✅ Claude Code Addon running on http://localhost:${PORT}`);
    console.log(`🌐 Access via Home Assistant Ingress`);
  });
}

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Shutting down...');
  mcpConnection.disconnect();
  server.close();
  process.exit(0);
});

startup().catch(error => {
  console.error('Startup failed:', error);
  process.exit(1);
});