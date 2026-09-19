// Compatibilidad con el comando usado en versiones antiguas.
// La migración actual es idempotente y nunca elimina tablas ni usuarios.
const pool = require('./src/config/db');
const { migrate } = require('./src/config/migrate');

migrate()
  .then(() => pool.end())
  .catch((error) => {
    console.error('Error actualizando esquema:', error.message);
    return pool.end().finally(() => process.exit(1));
  });
