/**
 * env.js — Carga y valida variables de entorno.
 * Importar este módulo PRIMERO en app.js para asegurar que .env esté cargado.
 */
require('dotenv').config();

const required = ['JWT_SECRET', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'];

for (const key of required) {
  if (!process.env[key]) {
    console.error(`❌ Variable de entorno requerida faltante: ${key}`);
    process.exit(1);
  }
}

module.exports = {
  PORT:          parseInt(process.env.PORT, 10) || 3000,
  NODE_ENV:      process.env.NODE_ENV || 'development',

  // Base de datos
  DB_USER:       process.env.DB_USER,
  DB_HOST:       process.env.DB_HOST     || 'localhost',
  DB_NAME:       process.env.DB_NAME,
  DB_PASSWORD:   process.env.DB_PASSWORD,
  DB_PORT:       parseInt(process.env.DB_PORT, 10) || 5432,

  // JWT
  JWT_SECRET:    process.env.JWT_SECRET,
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || '8h',

  // CORS
  CORS_ORIGINS:  (process.env.CORS_ORIGINS || 'http://localhost:3000').split(','),
};
