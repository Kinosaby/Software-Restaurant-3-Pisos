/**
 * error.middleware.js — Manejador global de errores Express.
 * DEBE registrarse como último middleware en app.js
 */
const logger = require('../utils/logger');
const env    = require('../config/env');

// eslint-disable-next-line no-unused-vars
const errorMiddleware = (err, req, res, next) => {
  // Código y estado por defecto
  const statusCode = err.statusCode || 500;
  const code       = err.code || 'INTERNAL_ERROR';

  // Log del error
  if (statusCode >= 500) {
    logger.error('Error interno del servidor', {
      method:  req.method,
      url:     req.originalUrl,
      status:  statusCode,
      code,
      message: err.message,
      stack:   env.NODE_ENV === 'development' ? err.stack : undefined,
    });
  } else {
    logger.warn('Error operacional', {
      method:  req.method,
      url:     req.originalUrl,
      status:  statusCode,
      code,
      message: err.message,
    });
  }

  // Errores de validación de express-validator (arreglo de errores)
  if (err.errors && Array.isArray(err.errors)) {
    return res.status(400).json({
      success: false,
      code:    'VALIDATION_ERROR',
      errors:  err.errors,
    });
  }

  // Respuesta al cliente
  const response = {
    success: false,
    code,
    error: err.isOperational ? err.message : 'Error interno del servidor',
  };

  // Stack solo en desarrollo
  if (env.NODE_ENV === 'development' && err.stack) {
    response.stack = err.stack;
  }

  res.status(statusCode).json(response);
};

module.exports = errorMiddleware;
