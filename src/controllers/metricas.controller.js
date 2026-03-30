/**
 * metricas.controller.js — Endpoints de métricas para administrador.
 */
const asyncHandler    = require('../utils/asyncHandler');
const metricasService = require('../services/metricas.service');

/** GET /api/metricas/resumen  — resumen completo */
exports.resumen = asyncHandler(async (req, res) => {
  const data = await metricasService.resumen();
  res.json({ success: true, ...data });
});

/** GET /api/metricas/dia  — ventas del día */
exports.ventasDia = asyncHandler(async (req, res) => {
  const data = await metricasService.ventasDia();
  res.json({ success: true, ...data });
});

/** GET /api/metricas/estados  — pedidos por estado */
exports.pedidosPorEstado = asyncHandler(async (req, res) => {
  const data = await metricasService.pedidosPorEstado();
  res.json({ success: true, estados: data });
});

/** GET /api/metricas/ventas?dias=7  — ventas por rango de fechas */
exports.ventasPorFecha = asyncHandler(async (req, res) => {
  const dias = parseInt(req.query.dias, 10) || 7;
  const data = await metricasService.ventasPorFecha(dias);
  res.json({ success: true, ventas: data });
});

/** GET /api/metricas/productos-top  — productos más pedidos */
exports.productosTop = asyncHandler(async (req, res) => {
  const limit = parseInt(req.query.limit, 10) || 5;
  const data  = await metricasService.productosTop(limit);
  res.json({ success: true, productos: data });
});
