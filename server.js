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
const { migrate } = require('./src/config/migrate');
const pool = require('./src/config/db');

// Crear servidor HTTP (necesario para Socket.IO)
const httpServer = http.createServer(app);

// Inicializar Socket.IO y adjuntar io a la app (accesible desde controllers)
const io = initSocket(httpServer);
app.set('io', io);

async function start() {
  // Railway puede levantar un PostgreSQL vacío. El servidor solo acepta tráfico
  // después de que el esquema esté listo.
  await migrate();

  httpServer.listen(env.PORT, () => {
    logger.info(`Servidor corriendo en el puerto ${env.PORT}`, {
      env: env.NODE_ENV,
      port: env.PORT,
    });
  });
}

start().catch((error) => {
  logger.error('No se pudo iniciar el servidor', { error: error.message });
  process.exit(1);
});

async function shutdown(signal) {
  logger.info(`Cerrando servidor (${signal})`);
  httpServer.close(async () => {
    await pool.end();
    process.exit(0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Manejo limpio de errores de proceso (producción)
process.on('unhandledRejection', (reason) => {
  logger.error('Promesa no manejada — cerrando servidor', { reason: String(reason) });
  shutdown('unhandledRejection');
});

process.on('uncaughtException', (err) => {
  logger.error('Excepción no capturada — cerrando servidor', { error: err.message });
  process.exit(1);
});
