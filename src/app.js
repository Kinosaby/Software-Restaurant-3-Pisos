/**
 * app.js — Configuración central de Express.
 * Orden correcto: env → seguridad → CORS → logging → rutas → 404 → errores
 */

// 1. Cargar env PRIMERO
require('./config/env');

const express       = require('express');
const cors          = require('cors');
const path          = require('path');
const env           = require('./config/env');
const logger        = require('./utils/logger');

// Inicializar base de datos
const { initializeDatabase } = require('./config/initDb');
initializeDatabase().catch(err => {
  logger.error('Fallo crítico al inicializar BD', { error: err.message });
  process.exit(1);
});

// Rutas
const authRoutes     = require('./routes/auth');
const pedidosRoutes  = require('./routes/pedidos');
const productosRoutes = require('./routes/productos');
const metricasRoutes = require('./routes/metricas');

// Middlewares
const errorMiddleware = require('./middlewares/error.middleware');
const AppError        = require('./utils/AppError');

const app = express();

// ── Seguridad ────────────────────────────────────────────────────────────────
// (helmet requiere instalación: npm install helmet)
try {
  const helmet = require('helmet');
  app.use(helmet({
    contentSecurityPolicy: false,  // desactivar para servir el frontend
    crossOriginEmbedderPolicy: false,
  }));
} catch (_) {
  logger.warn('Helmet no instalado. Se recomienda: npm install helmet');
}

// ── CORS ─────────────────────────────────────────────────────────────────────
app.use(cors({
  origin: env.CORS_ORIGINS,
  credentials: true,
}));

// ── Body parsers ─────────────────────────────────────────────────────────────
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

// ── Logging HTTP ─────────────────────────────────────────────────────────────
app.use((req, res, next) => {
  res.on('finish', () => {
    logger.http(`${req.method} ${req.originalUrl}`, {
      status: res.statusCode,
      ip:     req.ip,
    });
  });
  next();
});

// ── Frontend estático ─────────────────────────────────────────────────────────
const frontendPath = path.join(process.cwd(), 'restaurante-app');
app.use(express.static(frontendPath));
logger.info(`Sirviendo frontend desde: ${frontendPath}`);

// ── Rutas de la API ───────────────────────────────────────────────────────────
app.use('/api/auth',      authRoutes);
app.use('/api/productos', productosRoutes);
app.use('/api/pedidos',   pedidosRoutes);
app.use('/api/metricas',  metricasRoutes);

// ── Health check ──────────────────────────────────────────────────────────────
const healthHandler = (req, res) => {
  res.json({
    success: true,
    status: 'ok',
    timestamp: new Date().toISOString(),
    env: env.NODE_ENV,
  });
};
app.get('/health',      healthHandler);
app.get('/api/health',  healthHandler);

// ── SPA fallback — sirve index.html para rutas del frontend ───────────────────
app.get('*', (req, res, next) => {
  // No interceptar rutas de la API
  if (req.originalUrl.startsWith('/api/')) {
    return next(new AppError('Ruta no encontrada.', 404, 'NOT_FOUND'));
  }
  res.sendFile(path.join(frontendPath, 'index.html'));
});

// ── Manejo global de errores (SIEMPRE al final) ───────────────────────────────
app.use(errorMiddleware);

module.exports = app;