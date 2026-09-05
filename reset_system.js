const pool = require('./src/config/db');
const bcrypt = require('bcryptjs');

async function cleanAndReset() {
  try {
    if (process.env.CONFIRM_RESET !== 'RESET_3_PISOS') {
      throw new Error('Operación cancelada. Define CONFIRM_RESET=RESET_3_PISOS para confirmar.');
    }
    if (!process.env.ADMIN_PASSWORD || process.env.ADMIN_PASSWORD.length < 8) {
      throw new Error('Configura ADMIN_PASSWORD con al menos 8 caracteres.');
    }
    console.log('--- 🧹 Limpiando Sistema para Cliente Nuevo ---');

    // 1. Limpiar pedidos y detalles (Primero detalles por FK)
    await pool.query('DELETE FROM pedido_detalle');
    await pool.query('DELETE FROM pedidos');
    console.log('✅ Historial de pedidos borrado.');

    // 2. Limpiar productos
    await pool.query('DELETE FROM productos');
    console.log('✅ Carta de productos borrada.');

    // 3. Resetear usuarios (Mantener solo admin inicial)
    await pool.query('DELETE FROM usuarios WHERE username != $1', ['admin']);
    
    // Asegurar que admin tenga la contraseña por defecto si fue borrado
    const adminCheck = await pool.query('SELECT * FROM usuarios WHERE username = $1', ['admin']);
    if (adminCheck.rows.length === 0) {
        const hashedPass = await bcrypt.hash(process.env.ADMIN_PASSWORD, 12);
        await pool.query(
            'INSERT INTO usuarios (username, password, role) VALUES ($1, $2, $3)',
            ['admin', hashedPass, 'admin']
        );
        console.log('✅ Usuario administrador recreado.');
    } else {
        console.log('✅ Usuario administrador conservado.');
    }

    // 4. Reiniciar secuencias de ID (opcional pero estético para el cliente)
    await pool.query('ALTER SEQUENCE IF EXISTS productos_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE IF EXISTS pedidos_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE IF EXISTS pedido_detalle_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE IF EXISTS usuarios_id_seq RESTART WITH 2');
    
    console.log('\n--- ✨ Sistema listo para entrega ---');
    console.log('Acceso inicial:');
    console.log('Usuario: admin');
    console.log('Password: valor configurado en ADMIN_PASSWORD');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error limpiando DB:', error);
    process.exit(1);
  }
}

cleanAndReset();
