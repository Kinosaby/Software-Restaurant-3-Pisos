const pool = require('./src/config/db');
const bcrypt = require('bcryptjs');

async function updateSchema() {
  try {
    console.log('--- Actualizando Esquema de Base de Datos ---');

    // 1. Eliminar tabla usuarios si existe para recrearla correctamente
    // Solo si estamos seguros de que no tiene datos importantes o si la estructura está rota
    console.log('Revisando tabla usuarios...');
    
    await pool.query(`DROP TABLE IF EXISTS usuarios CASCADE`);

    await pool.query(`
      CREATE TABLE usuarios (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        role VARCHAR(20) NOT NULL DEFAULT 'mesero'
      )
    `);
    console.log('✅ Tabla usuarios creada correctamente.');

    // 2. Crear admin inicial
    const hashedPassAdmin = await bcrypt.hash('admin123', 10);
    await pool.query(
      'INSERT INTO usuarios (username, password, role) VALUES ($1, $2, $3)',
      ['admin', hashedPassAdmin, 'admin']
    );
    console.log('✅ Usuario admin inicial creado (admin / admin123).');

    // 3. Crear mesero de prueba
    const hashedPassMesero = await bcrypt.hash('mesero123', 10);
    await pool.query(
      'INSERT INTO usuarios (username, password, role) VALUES ($1, $2, $3)',
      ['mesero1', hashedPassMesero, 'mesero']
    );
    console.log('✅ Usuario mesero inicial creado (mesero1 / mesero123).');

    // 4. Crear usuario de cocina
    const hashedPassCocina = await bcrypt.hash('cocina123', 10);
    await pool.query(
      'INSERT INTO usuarios (username, password, role) VALUES ($1, $2, $3)',
      ['cocina', hashedPassCocina, 'cocina']
    );
    console.log('✅ Usuario cocina inicial creado (cocina / cocina123).');

    console.log('--- Esquema actualizado con éxito ---');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error actualizando esquema:', error);
    process.exit(1);
  }
}

updateSchema();
