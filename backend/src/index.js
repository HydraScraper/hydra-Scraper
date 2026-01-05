/**
 * HydraScraper Backend - Main Application Entry Point
 * Sets up Express app with middleware, error handling, and worker threads
 */

const express = require('express');
const { Worker } = require('worker_threads');
const path = require('path');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const dotenv = require('dotenv');

// Load environment variables
dotenv.config();

// Initialize Express application
const app = express();
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';

// ============================================================================
// MIDDLEWARE SETUP
// ============================================================================

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:3000',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// Logging middleware
if (NODE_ENV === 'development') {
  app.use(morgan('dev'));
} else {
  app.use(morgan('combined'));
}

// Body parser middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));

// Request ID middleware for tracking
app.use((req, res, next) => {
  req.id = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  res.setHeader('X-Request-ID', req.id);
  next();
});

// ============================================================================
// WORKER THREADS SETUP
// ============================================================================

/**
 * Worker Pool for handling CPU-intensive scraping tasks
 */
class WorkerPool {
  constructor(workerScript, poolSize = 4) {
    this.workers = [];
    this.taskQueue = [];
    this.activeWorkers = new Map();
    this.poolSize = poolSize;
    this.workerScript = workerScript;
    
    this.initializeWorkers();
  }

  /**
   * Initialize worker threads
   */
  initializeWorkers() {
    try {
      for (let i = 0; i < this.poolSize; i++) {
        const worker = new Worker(this.workerScript);
        
        worker.on('message', (result) => {
          const taskId = result.taskId;
          const task = this.activeWorkers.get(taskId);
          
          if (task) {
            task.resolve(result);
            this.activeWorkers.delete(taskId);
            this.processQueue();
          }
        });

        worker.on('error', (error) => {
          console.error(`Worker ${i} error:`, error);
          const taskId = Array.from(this.activeWorkers.entries())
            .find(([_, task]) => task.worker === worker)?.[0];
          
          if (taskId) {
            const task = this.activeWorkers.get(taskId);
            task.reject(error);
            this.activeWorkers.delete(taskId);
            this.processQueue();
          }
        });

        worker.on('exit', (code) => {
          if (code !== 0) {
            console.error(`Worker ${i} exited with code ${code}`);
          }
        });

        worker.taskId = null;
        this.workers.push(worker);
      }
      console.log(`✓ Worker pool initialized with ${this.poolSize} workers`);
    } catch (error) {
      console.error('Failed to initialize worker pool:', error);
    }
  }

  /**
   * Execute a task using available worker
   */
  execute(data) {
    return new Promise((resolve, reject) => {
      const taskId = `task-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      
      const task = {
        taskId,
        data,
        resolve,
        reject,
        worker: null,
      };

      const availableWorker = this.workers.find(w => !w.taskId);

      if (availableWorker) {
        this.assignTask(availableWorker, task);
      } else {
        this.taskQueue.push(task);
      }
    });
  }

  /**
   * Assign task to worker
   */
  assignTask(worker, task) {
    worker.taskId = task.taskId;
    task.worker = worker;
    this.activeWorkers.set(task.taskId, task);
    worker.postMessage(task.data);
  }

  /**
   * Process queued tasks
   */
  processQueue() {
    if (this.taskQueue.length === 0) return;

    const availableWorker = this.workers.find(w => !w.taskId);
    if (availableWorker) {
      const task = this.taskQueue.shift();
      this.assignTask(availableWorker, task);
      this.processQueue();
    }
  }

  /**
   * Gracefully terminate all workers
   */
  terminate() {
    return Promise.all(this.workers.map(worker => worker.terminate()));
  }
}

// Initialize worker pool
const workerPath = path.join(__dirname, 'workers', 'scraper.worker.js');
const workerPool = new WorkerPool(workerPath, process.env.WORKER_POOL_SIZE || 4);

// Expose worker pool to app
app.locals.workerPool = workerPool;

// ============================================================================
// ROUTES SETUP
// ============================================================================

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    environment: NODE_ENV,
    uptime: process.uptime(),
  });
});

/**
 * API status endpoint
 */
app.get('/api/status', (req, res) => {
  res.status(200).json({
    status: 'ok',
    message: 'HydraScraper API is running',
    version: process.env.APP_VERSION || '1.0.0',
    timestamp: new Date().toISOString(),
  });
});

/**
 * Worker pool stats endpoint
 */
app.get('/api/workers/stats', (req, res) => {
  const stats = {
    poolSize: workerPool.poolSize,
    activeWorkers: workerPool.activeWorkers.size,
    queuedTasks: workerPool.taskQueue.length,
    totalWorkers: workerPool.workers.length,
  };
  res.status(200).json(stats);
});

// Route placeholder for scraping endpoints
app.post('/api/scrape', (req, res) => {
  res.status(501).json({
    error: 'Scraping endpoint not yet implemented',
    message: 'Please implement route handlers in routes/',
  });
});

// ============================================================================
// ERROR HANDLING MIDDLEWARE
// ============================================================================

/**
 * 404 Not Found handler
 */
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    message: `Cannot ${req.method} ${req.path}`,
    requestId: req.id,
    timestamp: new Date().toISOString(),
  });
});

/**
 * Global error handler middleware
 */
app.use((err, req, res, next) => {
  const status = err.status || err.statusCode || 500;
  const message = err.message || 'Internal Server Error';
  const details = NODE_ENV === 'development' ? err.stack : undefined;

  console.error(`[${req.id}] Error (${status}):`, message);
  if (NODE_ENV === 'development') {
    console.error(details);
  }

  res.status(status).json({
    error: message,
    status,
    requestId: req.id,
    timestamp: new Date().toISOString(),
    ...(NODE_ENV === 'development' && { details }),
  });
});

// ============================================================================
// SERVER INITIALIZATION
// ============================================================================

/**
 * Handle graceful shutdown
 */
const gracefulShutdown = async (signal) => {
  console.log(`\n${signal} received. Starting graceful shutdown...`);

  try {
    // Terminate worker pool
    await workerPool.terminate();
    console.log('✓ Worker pool terminated');

    // Close HTTP server
    server.close(() => {
      console.log('✓ HTTP server closed');
      process.exit(0);
    });

    // Force exit after timeout
    setTimeout(() => {
      console.error('✗ Forced shutdown due to timeout');
      process.exit(1);
    }, 30000);
  } catch (error) {
    console.error('Error during shutdown:', error);
    process.exit(1);
  }
};

// Register signal handlers
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  process.exit(1);
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

// ============================================================================
// START SERVER
// ============================================================================

const server = app.listen(PORT, () => {
  console.log('\n╔════════════════════════════════════════════════════════╗');
  console.log('║         HydraScraper Backend Server Started             ║');
  console.log('╚════════════════════════════════════════════════════════╝');
  console.log(`🚀 Server running on http://localhost:${PORT}`);
  console.log(`📦 Environment: ${NODE_ENV}`);
  console.log(`🔧 Worker Pool Size: ${workerPool.poolSize}`);
  console.log(`⏰ Start Time: ${new Date().toISOString()}\n`);
});

// Export for testing
module.exports = { app, workerPool, server };
