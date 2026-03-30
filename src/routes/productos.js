/**
 * productos.routes.js — Rutas de productos.
 */
const express = require('express');
const { body, param } = require('express-validator');

const router = express.Router();
const ctrl   = require('../controllers/productos.controller');
const { authMiddleware, isAdmin } = require('../middlewares/auth.middleware');
const { validate } = require('../middlewares/validate.middleware');

// ===== Validaciones =====
const productoRules = [
  body('nombre')
    .trim().notEmpty().withMessage('El nombre del producto es requerido.')
    .isLength({ max: 100 }).withMessage('El nombre no puede superar 100 caracteres.'),
  body('precio')
    .isFloat({ min: 0.01 }).withMessage('El precio debe ser un número positivo.'),
  body('activo')
    .optional().isBoolean().withMessage('activo debe ser true o false.'),
];

// ===== Endpoints =====
/** Todos los autenticados pueden ver productos */
router.get('/', authMiddleware, ctrl.listar);

/** Solo admin gestiona productos */
router.post('/',    authMiddleware, isAdmin, productoRules, validate, ctrl.crear);
router.put('/:id',  authMiddleware, isAdmin, productoRules, validate, ctrl.actualizar);
router.delete('/:id',
  authMiddleware,
  isAdmin,
  param('id').isInt({ min: 1 }).withMessage('ID inválido.'),
  validate,
  ctrl.eliminar
);

module.exports = router;