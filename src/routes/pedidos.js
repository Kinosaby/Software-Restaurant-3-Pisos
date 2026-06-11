/**
 * pedidos.routes.js — Rutas de pedidos con validación y control de roles.
 */
const express = require('express');
const { body, param, query } = require('express-validator');

const router = express.Router();
const ctrl   = require('../controllers/pedidos.controller');
const { authMiddleware, requireRole, isAdmin } = require('../middlewares/auth.middleware');
const { validate } = require('../middlewares/validate.middleware');

// ===== Validaciones =====
const crearPedidoRules = [
  body('mesa')
    .isInt({ min: 1 }).withMessage('La mesa debe ser un número entero positivo.'),
  body('tipo')
    .optional().isIn(['aqui','llevar']).withMessage('Tipo inválido. Valores: aqui, llevar.'),
  body('comensal')
    .optional({ nullable: true }).isString().trim()
    .isLength({ max: 50 }).withMessage('El comensal no puede superar 50 caracteres.'),
  body('productos')
    .isArray({ min: 1 }).withMessage('Debe incluir al menos un producto.'),
  body('productos.*.producto_id')
    .isInt({ min: 1 }).withMessage('producto_id debe ser un entero positivo.'),
  body('productos.*.cantidad')
    .isInt({ min: 1 }).withMessage('La cantidad debe ser al menos 1.'),
  body('productos.*.nota')
    .optional().isString().isLength({ max: 200 }).withMessage('La nota no puede superar 200 caracteres.'),
];

const cambiarEstadoRules = [
  param('id').isInt({ min: 1 }).withMessage('ID inválido.'),
  body('estado')
    .notEmpty().withMessage('El estado es requerido.')
    .isIn(['pendiente', 'preparando', 'listo', 'pagado', 'cancelado'])
    .withMessage('Estado inválido. Valores: pendiente, preparando, listo, pagado, cancelado.'),
];

// ===== Endpoints =====
/** Mesero y Admin pueden ver pedidos; cocina puede ver los suyos (filtrado por estado en query) */
router.get('/',
  authMiddleware,
  requireRole('admin', 'mesero', 'cocina'),
  ctrl.listar
);

router.get('/:id',
  authMiddleware,
  requireRole('admin', 'mesero', 'cocina'),
  param('id').isInt({ min: 1 }),
  validate,
  ctrl.obtener
);

/** Solo mesero y admin crean pedidos */
router.post('/',
  authMiddleware,
  requireRole('admin', 'mesero'),
  crearPedidoRules,
  validate,
  ctrl.crear
);

/** Cambio de estado: cocina puede cambiar a preparando/listo; mesero/admin pueden todo */
router.put('/:id/estado',
  authMiddleware,
  requireRole('admin', 'mesero', 'cocina'),
  cambiarEstadoRules,
  validate,
  ctrl.cambiarEstado
);

/** Cancelar pedido */
router.patch('/:id/cancelar',
  authMiddleware,
  requireRole('admin', 'mesero'),
  param('id').isInt({ min: 1 }),
  validate,
  ctrl.cancelar
);

/** Agregar productos a pedido activo (mesero/admin) */
const agregarProductosRules = [
  param('id').isInt({ min: 1 }).withMessage('ID inválido.'),
  body('productos').isArray({ min: 1 }).withMessage('Debe incluir al menos un producto.'),
  body('productos.*.producto_id').isInt({ min: 1 }).withMessage('producto_id inválido.'),
  body('productos.*.cantidad').isInt({ min: 1 }).withMessage('Cantidad mínima: 1.'),
  body('productos.*.nota').optional().isString().isLength({ max: 200 }),
  body('tipo').optional().isIn(['aqui','llevar']).withMessage('Tipo de extra inválido.'),
];

router.patch('/:id/agregar',
  authMiddleware,
  requireRole('admin', 'mesero'),
  agregarProductosRules,
  validate,
  ctrl.agregar
);

/** Editar items de un pedido (quitar o cambiar cantidad, cambiar mesa/tipo/comensal) */
const editarPedidoRules = [
  param('id').isInt({ min: 1 }).withMessage('ID inválido.'),
  body('items').optional().isArray({ min: 1 }).withMessage('Debe enviar al menos un item.'),
  body('items.*.detalle_id').optional().isInt({ min: 1 }).withMessage('detalle_id inválido.'),
  body('items.*.cantidad').optional().isInt({ min: 0 }).withMessage('Cantidad debe ser 0 o mayor.'),
  body('items.*.nota').optional({ nullable: true }).isString().isLength({ max: 200 }),
  body('mesa').optional().isInt({ min: 1 }).withMessage('Mesa debe ser un número positivo.'),
  body('tipo').optional().isIn(['aqui','llevar']).withMessage('Tipo de pedido inválido.'),
  body('comensal').optional({ nullable: true }).isString().isLength({ max: 50 }).withMessage('Nombre de comensal inválido.'),
];

router.patch('/:id/editar',
  authMiddleware,
  requireRole('admin', 'mesero'),
  editarPedidoRules,
  validate,
  ctrl.editar
);

/** Eliminar pedido (admin only) */
router.delete('/:id',
  authMiddleware,
  isAdmin,
  param('id').isInt({ min: 1 }),
  validate,
  ctrl.eliminar
);

module.exports = router;