/**
 * sockets/index.js — Configuración de Socket.IO.
 * Exporta una función que recibe el servidor HTTP y devuelve io.
 */
const { Server } = require('socket.io');
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

  io.on('connection', (socket) => {
    logger.info('Socket conectado', { socketId: socket.id });

    // El cliente puede suscribirse a una sala por rol
    socket.on('join_room', (room) => {
      socket.join(room);
      logger.debug('Socket entró a sala', { socketId: socket.id, room });
    });

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
