/**
 * auth.service.js — Lógica de negocio para autenticación y usuarios.
 * Columnas reales de la BD: id, nombre, usuario, password, rol, creado_en
 */
const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');
const pool     = require('../config/db');
const env      = require('../config/env');
const AppError = require('../utils/AppError');

/** Normaliza una fila de BD al formato estándar del sistema */
function normalizar(row) {
  if (!row) return null;
  return {
    id:       row.id,
    username: row.usuario  || row.username,
    nombre:   row.nombre   || row.usuario  || row.username,
    role:     row.rol      || row.role,
  };
}

/** Intenta hacer login; devuelve { token, user } o lanza AppError */
async function login(username, password) {
  // La columna real en la BD es 'usuario'
  const result = await pool.query(
    'SELECT * FROM usuarios WHERE usuario = $1',
    [username]
  );

  if (result.rows.length === 0) {
    throw new AppError('Usuario o contraseña incorrectos.', 401, 'INVALID_CREDENTIALS');
  }

  const user    = result.rows[0];
  const isMatch = await bcrypt.compare(password, user.password);

  if (!isMatch) {
    throw new AppError('Usuario o contraseña incorrectos.', 401, 'INVALID_CREDENTIALS');
  }

  const norm  = normalizar(user);
  const token = jwt.sign(
    { id: norm.id, username: norm.username, role: norm.role },
    env.JWT_SECRET,
    { expiresIn: env.JWT_EXPIRES_IN }
  );

  return { token, user: norm };
}

/** Crea un nuevo usuario con contraseña hasheada */
async function crearUsuario(username, password, role = 'mesero') {
  const hashedPass = await bcrypt.hash(password, 12);
  try {
    const result = await pool.query(
      'INSERT INTO usuarios (nombre, usuario, password, rol) VALUES ($1, $2, $3, $4) RETURNING id, nombre, usuario, rol',
      [username, username, hashedPass, role]
    );
    return normalizar(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      throw new AppError('El nombre de usuario ya existe.', 409, 'DUPLICATE_USER');
    }
    throw err;
  }
}

/** Lista todos los usuarios (sin contraseña) */
async function listarUsuarios() {
  const result = await pool.query(
    'SELECT id, nombre, usuario, rol, creado_en FROM usuarios ORDER BY id ASC'
  );
  return result.rows.map(normalizar);
}

/** Actualiza usuario; opcionalmente cambia contraseña */
async function actualizarUsuario(id, { username, password, role }) {
  let query  = 'UPDATE usuarios SET nombre = $1, usuario = $2, rol = $3';
  let params = [username, username, role];

  if (password) {
    const hashed = await bcrypt.hash(password, 12);
    query  += ', password = $4 WHERE id = $5 RETURNING id, nombre, usuario, rol';
    params.push(hashed, id);
  } else {
    query  += ' WHERE id = $4 RETURNING id, nombre, usuario, rol';
    params.push(id);
  }

  const result = await pool.query(query, params);
  if (result.rows.length === 0) {
    throw new AppError('Usuario no encontrado.', 404, 'USER_NOT_FOUND');
  }
  return normalizar(result.rows[0]);
}

/** Elimina un usuario */
async function eliminarUsuario(id) {
  const result = await pool.query(
    'DELETE FROM usuarios WHERE id = $1 RETURNING id, nombre, usuario, rol',
    [id]
  );
  if (result.rows.length === 0) {
    throw new AppError('Usuario no encontrado.', 404, 'USER_NOT_FOUND');
  }
  return normalizar(result.rows[0]);
}

module.exports = { login, crearUsuario, listarUsuarios, actualizarUsuario, eliminarUsuario };