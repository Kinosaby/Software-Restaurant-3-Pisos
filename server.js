/**
 * server.js — Punto de entrada del servidor.
 * Crea el servidor HTTP, adjunta Socket.IO, y escucha en el puerto configurado.
 */
require('./src/config/env');   // validar env vars antes de todo

const http   = require('http');
const app    = require('./src/app');
const env    = require('./src/config/env');
const logger = require('./src/utils/logger');
const { initSocket } = require('./src/sockets');

// Crear servidor HTTP (necesario para Socket.IO)
const httpServer = http.createServer(app);

// Inicializar Socket.IO y adjuntar io a la app (accesible desde controllers)
const io = initSocket(httpServer);
app.set('io', io);

// Iniciar servidor
httpServer.listen(env.PORT, () => {
  logger.info(`🚀 Servidor corriendo en http://localhost:${env.PORT}`, {
    env:  env.NODE_ENV,
    port: env.PORT,
  });
});

// Manejo limpio de errores de proceso (producción)
process.on('unhandledRejection', (reason) => {
  logger.error('Promesa no manejada — cerrando servidor', { reason: String(reason) });
  httpServer.close(() => process.exit(1));
});

process.on('uncaughtException', (err) => {
  logger.error('Excepción no capturada — cerrando servidor', { error: err.message });
  process.exit(1);
});