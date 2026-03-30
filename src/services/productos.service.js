/**
 * productos.service.js — CRUD de productos.
 * Columnas reales: id, nombre, precio, activo, creado_en
 */
const pool    = require('../config/db');
const AppError = require('../utils/AppError');

async function listar() {
  const result = await pool.query(
    'SELECT * FROM productos ORDER BY nombre ASC'
  );
  return result.rows;
}

async function crear({ nombre, precio, activo = true }) {
  const result = await pool.query(
    `INSERT INTO productos (nombre, precio, activo)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [nombre.trim(), precio, activo]
  );
  return result.rows[0];
}

async function actualizar(id, { nombre, precio, activo }) {
  const result = await pool.query(
    `UPDATE productos
     SET nombre = $1, precio = $2, activo = $3
     WHERE id = $4
     RETURNING *`,
    [nombre.trim(), precio, activo ?? true, id]
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