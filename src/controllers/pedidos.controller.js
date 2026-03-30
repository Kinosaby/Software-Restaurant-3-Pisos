/**
 * pedidos.controller.js — Controladores de pedidos.
 * Accede a io a través de req.app.get('io').
 */
const asyncHandler    = require('../utils/asyncHandler');
const pedidosService  = require('../services/pedidos.service');

const getIo = (req) => req.app.get('io');

/** GET /api/pedidos */
exports.listar = asyncHandler(async (req, res) => {
  const { estado } = req.query;
  const pedidos = await pedidosService.listar({ estado });
  res.json({ success: true, pedidos });
});

/** GET /api/pedidos/:id */
exports.obtener = asyncHandler(async (req, res) => {
  const pedido = await pedidosService.obtenerPorId(req.params.id);
  res.json({ success: true, pedido });
});

/** POST /api/pedidos  (mesero, admin) */
exports.crear = asyncHandler(async (req, res) => {
  const io     = getIo(req);
  const body   = { ...req.body, usuario_id: req.user?.id || null };
  const pedido = await pedidosService.crear(body, io);
  res.status(201).json({ success: true, mensaje: 'Pedido creado', pedido });
});

/** PUT /api/pedidos/:id/estado  (cocina, mesero, admin) */
exports.cambiarEstado = asyncHandler(async (req, res) => {
  const io     = getIo(req);
  const pedido = await pedidosService.cambiarEstado(req.params.id, req.body.estado, io);
  res.json({ success: true, mensaje: 'Estado actualizado', pedido });
});

/** PATCH /api/pedidos/:id/cancelar */
exports.cancelar = asyncHandler(async (req, res) => {
  const io     = getIo(req);
  const pedido = await pedidosService.cancelar(req.params.id, io);
  res.json({ success: true, mensaje: 'Pedido cancelado', pedido });
});

/** DELETE /api/pedidos/:id  (admin) */
exports.eliminar = asyncHandler(async (req, res) => {
  const pedido = await pedidosService.eliminar(req.params.id);
  res.json({ success: true, mensaje: 'Pedido eliminado', pedido });
});
