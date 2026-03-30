/**
 * metricas.service.js — Consultas de métricas.
 * Usa tabla ventas para totales y pedidos para conteos.
 * Columnas reales:
 *   pedidos: id, mesa, estado, total, usuario_id, creado_en
 *   ventas:  id, pedido_id, total, fecha
 */
const pool = require('../config/db');

/** Ventas totales del día (de la tabla ventas) + conteo de pedidos no cancelados */
async function ventasDia() {
  const [v, p] = await Promise.all([
    pool.query(`
      SELECT COALESCE(SUM(total), 0)::numeric AS total_ventas
      FROM ventas WHERE DATE(fecha) = CURRENT_DATE
    `),
    pool.query(`
      SELECT COUNT(*)::int AS total_pedidos
      FROM pedidos
      WHERE estado != 'cancelado'
        AND DATE(creado_en) = CURRENT_DATE
    `),
  ]);
  return {
    total_ventas:  v.rows[0].total_ventas,
    total_pedidos: p.rows[0].total_pedidos,
  };
}

/** Conteo de pedidos agrupados por estado */
async function pedidosPorEstado() {
  const { rows } = await pool.query(`
    SELECT estado, COUNT(*)::int AS cantidad
    FROM pedidos
    GROUP BY estado ORDER BY estado
  `);
  return rows;
}

/**
 * Ventas por fecha — últimos N días (desde tabla ventas).
 * @param {number} dias
 */
async function ventasPorFecha(dias = 7) {
  const { rows } = await pool.query(`
    SELECT
      DATE(fecha)       AS fecha,
      COUNT(*)::int     AS pedidos,
      SUM(total)::numeric AS total
    FROM ventas
    WHERE fecha >= CURRENT_DATE - INTERVAL '${parseInt(dias, 10)} days'
    GROUP BY DATE(fecha)
    ORDER BY fecha ASC
  `);
  return rows;
}

/** Productos más pedidos (de pedido_detalle x productos) */
async function productosTop(limit = 5) {
  const { rows } = await pool.query(`
    SELECT pr.nombre,
           SUM(pd.cantidad)::int AS total_pedido
    FROM pedido_detalle pd
    JOIN productos pr ON pr.id = pd.producto_id
    JOIN pedidos p    ON p.id  = pd.pedido_id
    WHERE p.estado != 'cancelado'
    GROUP BY pr.nombre
    ORDER BY total_pedido DESC
    LIMIT $1
  `, [limit]);
  return rows;
}

/** Ventas de la semana actual */
async function ventasSemana() {
  const { rows } = await pool.query(`
    SELECT COALESCE(SUM(total), 0)::numeric AS total_semana
    FROM ventas
    WHERE fecha >= date_trunc('week', CURRENT_DATE)
  `);
  return rows[0].total_semana;
}

/** Resumen completo */
async function resumen() {
  const [dia, semana, estados, top] = await Promise.all([
    ventasDia(),
    ventasSemana(),
    pedidosPorEstado(),
    productosTop(),
  ]);
  return { dia, semana, estados, productosTop: top };
}

module.exports = { ventasDia, pedidosPorEstado, ventasPorFecha, productosTop, resumen };