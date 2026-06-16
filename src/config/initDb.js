/**
 * initDb.js — Inicializa la base de datos ejecutando schema.sql
 */
const fs = require('fs');
const path = require('path');
const pool = require('./db');
const logger = require('../utils/logger');

async function initializeDatabase() {
  try {
    const schemaPath = path.join(__dirname, 'schema.sql');
    const schema = fs.readFileSync(schemaPath, 'utf8');
    
    await pool.query(schema);
    logger.info('✅ Base de datos inicializada correctamente');
  } catch (err) {
    logger.error('❌ Error al inicializar la base de datos', { error: err.message });
    throw err;
  }
}

module.exports = { initializeDatabase };
