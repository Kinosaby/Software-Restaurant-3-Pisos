const pool = require('./src/config/db');

async function verify() {
  try {
    console.log('--- Verificando Base de Datos ---');
    
    // 1. Verificar tablas
    const tables = await pool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public'
    `);
    
    const tableNames = tables.rows.map(r => r.table_name);
    console.log('Tablas encontradas:', tableNames);

    const requiredTables = ['productos', 'pedidos', 'pedido_detalle'];
    for (const table of requiredTables) {
      if (!tableNames.includes(table)) {
        console.error(`❌ Falta la tabla: ${table}`);
        process.exit(1);
      }
    }

    // 2. Verificar si hay productos, si no, agregar algunos
    const productos = await pool.query('SELECT COUNT(*) FROM productos');
    if (parseInt(productos.rows[0].count) === 0) {
      console.log('No hay productos. Insertando semillas...');
      await pool.query(`
        INSERT INTO productos (nombre, precio) VALUES 
        ('Pizza Pepperoni', 12.50),
        ('Hamburguesa Clásica', 8.00),
        ('Ensalada César', 7.50),
        ('Refresco 500ml', 2.00),
        ('Cerveza Artesanal', 4.50)
      `);
      console.log('✅ Semillas insertadas.');
    } else {
      console.log(`✅ Hay ${productos.rows[0].count} productos en la base de datos.`);
    }

    console.log('--- Verificación completada con éxito ---');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error verificando DB:', error);
    process.exit(1);
  }
}

verify();
