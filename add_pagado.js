// Compatibilidad con el script antiguo. El esquema completo se aplica de forma
// idempotente, incluyendo el estado pagado.
const pool = require('./src/config/db');
const { migrate } = require('./src/config/migrate');

migrate()
  .then(() => pool.end())
  .catch((error) => {
    console.error('Error aplicando migración:', error.message);
    return pool.end().finally(() => process.exit(1));
  });
