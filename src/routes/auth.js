/**
 * auth.routes.js — Rutas de autenticación y gestión de usuarios.
 */
const express = require('express');
const { body, param } = require('express-validator');

const router         = express.Router();
const ctrl           = require('../controllers/auth.controller');
const { authMiddleware, isAdmin } = require('../middlewares/auth.middleware');
const { validate }   = require('../middlewares/validate.middleware');

// ===== Validaciones =====
const loginRules = [
  body('username').trim().notEmpty().withMessage('El nombre de usuario es requerido.'),
  body('password').notEmpty().withMessage('La contraseña es requerida.'),
];

const registerRules = [
  body('username')
    .trim().notEmpty().withMessage('El nombre de usuario es requerido.')
    .isLength({ min: 3, max: 30 }).withMessage('El nombre debe tener entre 3 y 30 caracteres.'),
  body('password')
    .notEmpty().withMessage('La contraseña es requerida.')
    .isLength({ min: 6 }).withMessage('La contraseña debe tener al menos 6 caracteres.'),
  body('role')
    .optional()
    .isIn(['admin', 'mesero', 'cocina']).withMessage('Rol inválido. Valores: admin, mesero, cocina.'),
];

const updateUserRules = [
  param('id').isInt({ min: 1 }).withMessage('ID inválido.'),
  body('username').trim().notEmpty().withMessage('El nombre de usuario es requerido.'),
  body('role').isIn(['admin', 'mesero', 'cocina']).withMessage('Rol inválido.'),
  body('password').optional().isLength({ min: 6 }).withMessage('La contraseña debe tener al menos 6 caracteres.'),
];

// ===== Endpoints =====
// Públicos
router.post('/login', loginRules, validate, ctrl.login);

// Autenticados
router.get('/me', authMiddleware, ctrl.me);

// Solo Admin
router.post('/register',    authMiddleware, isAdmin, registerRules, validate, ctrl.register);
router.get('/usuarios',     authMiddleware, isAdmin, ctrl.listarUsuarios);
router.put('/:id',          authMiddleware, isAdmin, updateUserRules, validate, ctrl.actualizarUsuario);
router.delete('/:id',       authMiddleware, isAdmin, ctrl.eliminarUsuario);

module.exports = router;
