/**
 * metricas.routes.js — Rutas de métricas (solo admin).
 */
const express = require('express');
const router  = express.Router();
const ctrl    = require('../controllers/metricas.controller');
const { authMiddleware, isAdmin } = require('../middlewares/auth.middleware');

router.use(authMiddleware, isAdmin);   // todas requieren admin

router.get('/resumen',        ctrl.resumen);
router.get('/dia',            ctrl.ventasDia);
router.get('/estados',        ctrl.pedidosPorEstado);
router.get('/ventas',         ctrl.ventasPorFecha);
router.get('/productos-top',  ctrl.productosTop);

module.exports = router;
