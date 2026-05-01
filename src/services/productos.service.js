/**
 * productos.service.js — CRUD de productos.
 * Columnas reales: id, nombre, precio, categoria, activo, created_at
 */
const pool    = require('../config/db');
const AppError = require('../utils/AppError');

async function listar() {
  const result = await pool.query(
    'SELECT * FROM productos ORDER BY categoria ASC, nombre ASC'
  );
  return result.rows;
}

async function crear({ nombre, precio, categoria = 'General', activo = true }) {
  const result = await pool.query(
    `INSERT INTO productos (nombre, precio, categoria, activo)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [nombre.trim(), precio, categoria, activo]
  );
  return result.rows[0];
}

async function actualizar(id, { nombre, precio, categoria, activo }) {
  const result = await pool.query(
    `UPDATE productos
     SET nombre = $1, precio = $2, categoria = $3, activo = $4
     WHERE id = $5
     RETURNING *`,
    [nombre.trim(), precio, categoria || 'General', activo ?? true, id]
  );
  if (result.rows.length === 0) {
    throw new AppError('Producto no encontrado.', 404, 'PRODUCT_NOT_FOUND');
  }
  return result.rows[0];
}

async function eliminar(id) {
  const result = await pool.query(
    'DELETE FROM productos WHERE id = $1 RETURNING *',
    [id]
  );
  if (result.rows.length === 0) {
    throw new AppError('Producto no encontrado.', 404, 'PRODUCT_NOT_FOUND');
  }
  return result.rows[0];
}

module.exports = { listar, crear, actualizar, eliminar };