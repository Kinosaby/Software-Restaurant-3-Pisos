const pool = require('./src/config/db');

(async () => {
  try {
    await pool.query("ALTER TABLE pedidos DROP CONSTRAINT IF EXISTS pedidos_estado_check");
    await pool.query("ALTER TABLE pedidos ADD CONSTRAINT pedidos_estado_check CHECK (estado IN ('pendiente', 'preparando', 'listo', 'cancelado', 'pagado'))");
    console.log("Constraint update OK");
  } catch(e) {
    if (e.code === '42704') console.log("La constraint ya no existe o cambió de nombre.");
    console.error(e);
  } finally {
    process.exit(0);
  }
})();
