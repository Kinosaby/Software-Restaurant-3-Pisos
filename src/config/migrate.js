/** Aplica el esquema idempotente y crea el primer administrador si hace falta. */
const fs = require('fs/promises');
const path = require('path');
const bcrypt = require('bcryptjs');
const pool = require('./db');
const env = require('./env');
const logger = require('../utils/logger');

async function migrate() {
  const schemaPath = path.join(__dirname, 'schema.sql');
  const schema = await fs.readFile(schemaPath, 'utf8');
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    await client.query(schema);

    const { rows: [{ count }] } = await client.query(
      'SELECT COUNT(*)::int AS count FROM usuarios'
    );

    if (count === 0) {
      if (!env.ADMIN_PASSWORD || env.ADMIN_PASSWORD.length < 8) {
        throw new Error(
          'La base no tiene usuarios. Configura ADMIN_PASSWORD con al menos 8 caracteres en Railway.'
        );
      }

      const password = await bcrypt.hash(env.ADMIN_PASSWORD, 12);
      await client.query(
        `INSERT INTO usuarios (username, password, role)
         VALUES ($1, $2, 'admin')`,
        [env.ADMIN_USERNAME, password]
      );
      logger.info('Administrador inicial creado', { username: env.ADMIN_USERNAME });
    }

    const { rows: [health] } = await client.query('SELECT NOW() AS now');
    await client.query('COMMIT');
    logger.info('Base de datos lista', { tiempo: health.now });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate()
    .then(() => pool.end())
    .catch((error) => {
      logger.error('Falló la migración', { error: error.message });
      return pool.end().finally(() => process.exit(1));
    });
}

module.exports = { migrate };
