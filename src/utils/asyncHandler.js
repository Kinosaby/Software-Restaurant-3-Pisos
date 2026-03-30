/**
 * asyncHandler.js — Wrapper para rutas async.
 * Elimina la necesidad de try/catch en cada controlador.
 *
 * Uso:
 *   router.get('/ruta', asyncHandler(async (req, res) => { ... }));
 */
const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};

module.exports = asyncHandler;
