/**
 * db.js — Pool de conexiones PostgreSQL.
 * Usa variables de entorno; exporta un pool reutilizable.
 * TIMEZONE: configurado en America/Mexico_City para que CURRENT_DATE
 * coincida con el día del restaurante (no UTC).
 */
const { Pool } = require('pg');
const env = require('./env');
const logger = require('../utils/logger');
const useSsl = env.DB_SSL
  || env.NODE_ENV === 'production'
  || /railway|rlwy/i.test(env.DATABASE_URL || '');

const pool = new Pool(
  // Railway provee DATABASE_URL directamente; si existe, se usa
  env.DATABASE_URL
    ? {
        connectionString: env.DATABASE_URL,
        ...(useSsl
          ? { ssl: { rejectUnauthorized: false } }
          : {}),
        max: 10,
        idleTimeoutMillis: 30000,
        connectionTimeoutMillis: 5000,
      }
    : {
        user:     env.DB_USER,
        host:     env.DB_HOST,
        database: env.DB_NAME,
        password: env.DB_PASSWORD,
        port:     env.DB_PORT,
        max:      10,
        idleTimeoutMillis:       30000,
        connectionTimeoutMillis: 2000,
      }
);

// Forzar zona horaria México en cada conexión nueva del pool
pool.on('connect', (client) => {
  client.query("SET TIME ZONE 'America/Mexico_City'").catch(() => {});
});

// Log de errores del pool (conexiones que fallan en background)
pool.on('error', (err) => {
  logger.error('Error inesperado en cliente del pool PostgreSQL', { error: err.message });
});

module.exports = pool;
