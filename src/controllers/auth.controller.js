/**
 * auth.controller.js — Controladores de autenticación y gestión de usuarios.
 */
const asyncHandler = require('../utils/asyncHandler');
const authService  = require('../services/auth.service');
const logger       = require('../utils/logger');

/** POST /api/auth/login */
exports.login = asyncHandler(async (req, res) => {
  const { username, password } = req.body;
  const result = await authService.login(username, password);
  logger.info('Login exitoso', { username });
  res.json({ success: true, ...result });
});

/** POST /api/auth/register  (solo admin) */
exports.register = asyncHandler(async (req, res) => {
  const { username, password, role } = req.body;
  const user = await authService.crearUsuario(username, password, role);
  logger.info('Usuario creado', { username, role });
  res.status(201).json({ success: true, mensaje: 'Usuario creado', user });
});

/** GET /api/auth/usuarios  (solo admin) */
exports.listarUsuarios = asyncHandler(async (req, res) => {
  const usuarios = await authService.listarUsuarios();
  res.json({ success: true, usuarios });
});

/** PUT /api/auth/:id  (solo admin) */
exports.actualizarUsuario = asyncHandler(async (req, res) => {
  const user = await authService.actualizarUsuario(req.params.id, req.body);
  res.json({ success: true, user });
});

/** DELETE /api/auth/:id  (solo admin) */
exports.eliminarUsuario = asyncHandler(async (req, res) => {
  const user = await authService.eliminarUsuario(req.params.id);
  res.json({ success: true, mensaje: 'Usuario eliminado', user });
});

/** GET /api/auth/me — devuelve el usuario autenticado */
exports.me = asyncHandler(async (req, res) => {
  res.json({ success: true, user: req.user });
});
