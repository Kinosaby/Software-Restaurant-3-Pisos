/**
 * validate.middleware.js — Middleware de validación con express-validator.
 * Uso: poner validationRules(), validate en el array de middlewares de la ruta.
 */
const { validationResult } = require('express-validator');

/**
 * Ejecuta la validación y responde 400 con los errores si hay alguno.
 */
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    const err = new Error('Error de validación');
    err.statusCode = 400;
    err.code       = 'VALIDATION_ERROR';
    err.errors     = errors.array().map((e) => ({
      campo:   e.path,
      mensaje: e.msg,
      valor:   e.value,
    }));
    return next(err);
  }
  next();
};

module.exports = { validate };
