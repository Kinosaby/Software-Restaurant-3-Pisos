/**
 * AppError.js — Error operacional con código HTTP y código interno.
 * Distingue errores esperados (validación, 404) de los inesperados (500).
 */
class AppError extends Error {
  /**
   * @param {string} message  Mensaje legible
   * @param {number} statusCode  Código HTTP (400, 401, 403, 404, 500...)
   * @param {string} [code]   Código interno opcional (ej: 'DUPLICATE_USER')
   */
  constructor(message, statusCode = 500, code = 'INTERNAL_ERROR') {
    super(message);
    this.statusCode  = statusCode;
    this.code        = code;
    this.isOperational = true;  // vs errores de programación
    Error.captureStackTrace(this, this.constructor);
  }
}

module.exports = AppError;
