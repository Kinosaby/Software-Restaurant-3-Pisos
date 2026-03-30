/**
 * productos.controller.js — Controladores de productos.
 */
const asyncHandler      = require('../utils/asyncHandler');
const productosService  = require('../services/productos.service');

/** GET /api/productos */
exports.listar = asyncHandler(async (req, res) => {
  const productos = await productosService.listar();
  res.json({ success: true, productos });
});

/** POST /api/productos  (admin) */
exports.crear = asyncHandler(async (req, res) => {
  const producto = await productosService.crear(req.body);
  res.status(201).json({ success: true, producto });
});

/** PUT /api/productos/:id  (admin) */
exports.actualizar = asyncHandler(async (req, res) => {
  const producto = await productosService.actualizar(req.params.id, req.body);
  res.json({ success: true, producto });
});

/** DELETE /api/productos/:id  (admin) */
exports.eliminar = asyncHandler(async (req, res) => {
  const producto = await productosService.eliminar(req.params.id);
  res.json({ success: true, mensaje: 'Producto eliminado', producto });
});
