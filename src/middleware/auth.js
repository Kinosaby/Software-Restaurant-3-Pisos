const jwt = require('jsonwebtoken');

const SECRET_KEY = 'tu_clave_secreta_pos_3_pisos'; // En producción usar variables de entorno

const authMiddleware = (req, res, next) => {
  const token = req.headers['authorization'];

  if (!token) {
    return res.status(401).json({ error: 'Acceso denegado. No hay token.' });
  }

  try {
    // El token suele venir como "Bearer <token>"
    const tokenClean = token.startsWith('Bearer ') ? token.slice(7) : token;
    const decoded = jwt.verify(tokenClean, SECRET_KEY);
    req.user = decoded;
    next();
  } catch (error) {
    res.status(401).json({ error: 'Token inválido o expirado.' });
  }
};

const isAdmin = (req, res, next) => {
  if (req.user && req.user.role === 'admin') {
    next();
  } else {
    res.status(403).json({ error: 'Acceso denegado. Se requieren permisos de administrador.' });
  }
};

module.exports = { authMiddleware, isAdmin, SECRET_KEY };
