/**
 * auth.middleware.js — Autenticación JWT y autorización por roles.
 * Exporta: authMiddleware, requireRole(...roles), isAdmin, isCocina
 */
const jwt = require('jsonwebtoken');
const env = require('../config/env');
const AppError = require('../utils/AppError');

/**
 * Verifica el token JWT del header Authorization.
 * Adjunta req.user = { id, username, role, iat, exp }
 */
const authMiddleware = (req, res, next) => {
  const authHeader = req.headers['authorization'];

  if (!authHeader) {
    return next(new AppError('Acceso denegado. No hay token de autenticación.', 401, 'NO_TOKEN'));
  }

  const token = authHeader.startsWith('Bearer ')
    ? authHeader.slice(7).trim()
    : authHeader.trim();

  try {
    const decoded = jwt.verify(token, env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return next(new AppError('El token ha expirado. Por favor inicia sesión nuevamente.', 401, 'TOKEN_EXPIRED'));
    }
    return next(new AppError('Token inválido.', 401, 'INVALID_TOKEN'));
  }
};

/**
 * Genera middleware que permite solo los roles indicados.
 * Debe usarse DESPUÉS de authMiddleware.
 *
 * Ejemplo: router.get('/ruta', authMiddleware, requireRole('admin', 'mesero'), handler)
 */
const requireRole = (...roles) => (req, res, next) => {
  if (!req.user) {
    return next(new AppError('No autenticado.', 401, 'NOT_AUTHENTICATED'));
  }
  if (!roles.includes(req.user.role)) {
    return next(
      new AppError(
        `Acceso denegado. Se requiere rol: ${roles.join(' o ')}.`,
        403,
        'FORBIDDEN'
      )
    );
  }
  next();
};

/** Alias comunes */
const isAdmin  = requireRole('admin');
const isCocina = requireRole('admin', 'cocina');
const isMesero = requireRole('admin', 'mesero');

module.exports = { authMiddleware, requireRole, isAdmin, isCocina, isMesero };
