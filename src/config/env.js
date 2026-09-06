/**
 * env.js — Carga y valida variables de entorno.
 * Importar este módulo PRIMERO en app.js para asegurar que .env esté cargado.
 */
require('dotenv').config();

const databaseUrl = process.env.DATABASE_URL?.trim();
const required = [
  'JWT_SECRET',
  ...(databaseUrl ? [] : ['DB_NAME', 'DB_USER', 'DB_PASSWORD']),
];

const missing = required.filter((key) => !process.env[key]);

if (missing.length > 0) {
  throw new Error(`Variables de entorno requeridas faltantes: ${missing.join(', ')}`);
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
  DATABASE_URL:  databaseUrl,
  DB_SSL:        process.env.DB_SSL === 'true',

  // JWT
  JWT_SECRET:    process.env.JWT_SECRET,
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || '8h',

  // Usuario inicial. Solo se utiliza cuando la tabla usuarios está vacía.
  ADMIN_USERNAME: process.env.ADMIN_USERNAME || 'admin',
  ADMIN_PASSWORD: process.env.ADMIN_PASSWORD,

  // CORS
  CORS_ORIGINS:  (process.env.CORS_ORIGINS || 'http://localhost:3000')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
};
