/**
 * sockets/index.js — Configuración de Socket.IO.
 * Exporta una función que recibe el servidor HTTP y devuelve io.
 */
const { Server } = require('socket.io');
const jwt        = require('jsonwebtoken');
const logger     = require('../utils/logger');
const env        = require('../config/env');

function initSocket(httpServer) {
  const io = new Server(httpServer, {
    cors: {
      origin:  env.CORS_ORIGINS,
      methods: ['GET', 'POST'],
    },
    // Transports: prioriza WebSocket, fallback a polling
    transports: ['websocket', 'polling'],
  });

  io.use((socket, next) => {
    const authToken = socket.handshake.auth?.token;
    const header = socket.handshake.headers?.authorization;
    const headerToken = header?.startsWith('Bearer ') ? header.slice(7).trim() : header;
    const token = authToken || headerToken;

    if (!token) {
      return next(new Error('NO_TOKEN'));
    }

    try {
      socket.data.user = jwt.verify(token, env.JWT_SECRET);
      return next();
    } catch (_) {
      return next(new Error('INVALID_TOKEN'));
    }
  });

  io.on('connection', (socket) => {
    const { id: userId, role } = socket.data.user;
    socket.join(`role:${role}`);
    socket.join(`user:${userId}`);
    logger.info('Socket conectado', { socketId: socket.id, userId, role });

    socket.on('disconnect', (reason) => {
      logger.debug('Socket desconectado', { socketId: socket.id, reason });
    });
  });

  logger.info('Socket.IO inicializado');

  return io;
}

/**
 * Eventos emitidos desde el servidor (usados en los servicios):
 *
 *  - 'nuevo_pedido'      { pedido completo }
 *  - 'pedido_actualizado' { pedido completo actualizado }
 *
 * El cliente escucha con:
 *   socket.on('nuevo_pedido', handler)
 *   socket.on('pedido_actualizado', handler)
 */

module.exports = { initSocket };
