/**
 * logger.js — Logger estructurado con timestamps.
 * Usa console con formato JSON en producción, legible en desarrollo.
 */
const env = require('../config/env');

const isDev = env.NODE_ENV !== 'production';

function formatMessage(level, message, meta = {}) {
  const timestamp = new Date().toISOString();
  if (isDev) {
    // Formato legible para desarrollo
    const metaStr = Object.keys(meta).length ? JSON.stringify(meta) : '';
    return `[${timestamp}] ${level.toUpperCase().padEnd(5)} — ${message} ${metaStr}`;
  }
  // JSON estructurado para producción
  return JSON.stringify({ timestamp, level, message, ...meta });
}

const logger = {
  info:  (message, meta) => console.log(formatMessage('info',  message, meta)),
  warn:  (message, meta) => console.warn(formatMessage('warn',  message, meta)),
  error: (message, meta) => console.error(formatMessage('error', message, meta)),
  debug: (message, meta) => { if (isDev) console.log(formatMessage('debug', message, meta)); },
  /** Log de petición HTTP (compatible con morgan) */
  http:  (message, meta) => console.log(formatMessage('http', message, meta)),
};

module.exports = logger;
