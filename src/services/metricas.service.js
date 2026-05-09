/**
 * metricas.service.js — Consultas de métricas.
 * Usa tabla ventas para totales y pedidos para conteos.
 * Columnas reales:
 *   pedidos: id, mesa, estado, total, usuario_id, creado_en
 *   ventas:  id, pedido_id, total, fecha
 *
 * NOTA DE ZONA HORARIA:
 *   Railway/Postgres corre en UTC. El restaurante está en Mexico City (UTC-6 / UTC-5 DST).
 *   Usamos (NOW() AT TIME ZONE 'America/Mexico_City')::date para obtener la fecha local correcta.
 */
const pool = require('../config/db');

/** Fecha de hoy en México (PostgreSQL expression) */
const HOY_MX  = `(NOW() AT TIME ZONE 'America/Mexico_City')::date`;
/** Convierte un timestamp UTC a fecha local México */
const FECHA_MX = (col) => `(${col} AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date`;

/** Ventas totales del día (de la tabla ventas) + conteo de pedidos no cancelados */
async function ventasDia() {
  const [v, p] = await Promise.all([
    pool.query(`
      SELECT COALESCE(SUM(total), 0)::numeric AS total_ventas
      FROM ventas
      WHERE ${FECHA_MX('fecha')} = ${HOY_MX}
    `),
    pool.query(`
      SELECT COUNT(*)::int AS total_pedidos
      FROM pedidos
      WHERE estado != 'cancelado'
        AND ${FECHA_MX('creado_en')} = ${HOY_MX}
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
      ${FECHA_MX('fecha')}    AS fecha,
      COUNT(*)::int            AS pedidos,
      SUM(total)::numeric      AS total
    FROM ventas
    WHERE ${FECHA_MX('fecha')} >= ${HOY_MX} - INTERVAL '${parseInt(dias, 10)} days'
    GROUP BY ${FECHA_MX('fecha')}
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

/** Ventas de la semana actual (lunes a hoy, en hora México) */
async function ventasSemana() {
  const { rows } = await pool.query(`
    SELECT COALESCE(SUM(total), 0)::numeric AS total_semana
    FROM ventas
    WHERE ${FECHA_MX('fecha')} >= date_trunc('week', NOW() AT TIME ZONE 'America/Mexico_City')::date
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