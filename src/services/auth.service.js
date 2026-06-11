/**
 * auth.service.js — Lógica de negocio para autenticación y usuarios.
 * Columnas de la BD: id, username, password, role, created_at
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
    id:         row.id,
    username:   row.username,
    role:       row.role,
    created_at: row.created_at,
  };
}

/** Intenta hacer login; devuelve { token, user } o lanza AppError */
async function login(username, password) {
  const result = await pool.query(
    'SELECT * FROM usuarios WHERE username = $1',
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
      'INSERT INTO usuarios (username, password, role) VALUES ($1, $2, $3) RETURNING id, username, role',
      [username, hashedPass, role]
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
    'SELECT id, username, role, created_at FROM usuarios ORDER BY id ASC'
  );
  return result.rows.map(normalizar);
}

/** Actualiza usuario; opcionalmente cambia contraseña */
async function actualizarUsuario(id, { username, password, role }) {
  let query  = 'UPDATE usuarios SET username = $1, role = $2';
  let params = [username, role];

  if (password) {
    const hashed = await bcrypt.hash(password, 12);
    query  += ', password = $3 WHERE id = $4 RETURNING id, username, role';
    params.push(hashed, id);
  } else {
    query  += ' WHERE id = $3 RETURNING id, username, role';
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
    'DELETE FROM usuarios WHERE id = $1 RETURNING id, username, role',
    [id]
  );
  if (result.rows.length === 0) {
    throw new AppError('Usuario no encontrado.', 404, 'USER_NOT_FOUND');
  }
  return normalizar(result.rows[0]);
}

module.exports = { login, crearUsuario, listarUsuarios, actualizarUsuario, eliminarUsuario };