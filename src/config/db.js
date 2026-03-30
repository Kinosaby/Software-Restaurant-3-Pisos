/**
 * db.js — Pool de conexiones PostgreSQL.
 * Usa variables de entorno; exporta un pool reutilizable.
 */
const { Pool } = require('pg');
const env = require('./env');
const logger = require('../utils/logger');

const pool = new Pool({
  user:     env.DB_USER,
  host:     env.DB_HOST,
  database: env.DB_NAME,
  password: env.DB_PASSWORD,
  port:     env.DB_PORT,
  max:                  10,   // máximo de conexiones simultáneas
  idleTimeoutMillis:  30000,  // libera conexiones ociosas tras 30s
  connectionTimeoutMillis: 2000,
});

// Log de errores del pool (conexiones que fallan en background)
pool.on('error', (err) => {
  logger.error('Error inesperado en cliente del pool PostgreSQL', { error: err.message });
});

// Verificar conexión al arrancar
pool.query('SELECT NOW()')
  .then((res) => logger.info('✅ Base de datos conectada', { tiempo: res.rows[0].now }))
  .catch((err) => {
    logger.error('❌ No se pudo conectar a la base de datos', { error: err.message });
  });

module.exports = pool;