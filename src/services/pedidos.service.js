/**
 * pedidos.service.js — CRUD de pedidos con transacciones.
 * Columnas reales:
 *   pedidos:        id, mesa, estado, total, usuario_id, creado_en
 *   pedido_detalle: id, pedido_id, producto_id, cantidad, nota
 *   productos:      id, nombre, precio, activo, creado_en
 *   ventas:         id, pedido_id, total, fecha
 *
 * Estados válidos (CHECK en BD): pendiente | preparando | listo | cancelado
 */
const pool    = require('../config/db');
const AppError = require('../utils/AppError');
const logger  = require('../utils/logger');

const ESTADOS_VALIDOS = ['pendiente', 'preparando', 'listo', 'cancelado', 'pagado'];

/** Construye un pedido completo con su detalle mediante JSON aggregation */
const QUERY_DETALLE = `
  SELECT p.*,
         COALESCE(
           json_agg(
             json_build_object(
               'id',          pd.id,
               'producto_id', pd.producto_id,
               'nombre',      pr.nombre,
               'cantidad',    pd.cantidad,
               'nota',        pd.nota,
               'precio',      pr.precio
             )
           ) FILTER (WHERE pd.id IS NOT NULL),
           '[]'::json
         ) AS productos
  FROM pedidos p
  LEFT JOIN pedido_detalle pd ON pd.pedido_id = p.id
  LEFT JOIN productos pr      ON pr.id = pd.producto_id
`;

/** Devuelve todos los pedidos con su detalle, opcionalmente filtrados por estado */
async function listar({ estado } = {}) {
  let query  = QUERY_DETALLE;
  const params = [];

  if (estado && ESTADOS_VALIDOS.includes(estado)) {
    query += ' WHERE p.estado = $1';
    params.push(estado);
  }

  query += ' GROUP BY p.id ORDER BY p.id DESC';
  const { rows } = await pool.query(query, params);
  return rows;
}

/** Devuelve un pedido por id con su detalle */
async function obtenerPorId(id) {
  const { rows } = await pool.query(
    QUERY_DETALLE + ' WHERE p.id = $1 GROUP BY p.id',
    [id]
  );
  if (rows.length === 0) {
    throw new AppError('Pedido no encontrado.', 404, 'ORDER_NOT_FOUND');
  }
  return rows[0];
}

/**
 * Crea un nuevo pedido en una transacción atómica.
 * También registra en la tabla ventas al finalizar.
 */
async function crear({ mesa, productos, usuario_id = null }, io = null) {
  if (!productos || productos.length === 0) {
    throw new AppError('El pedido debe tener al menos un producto.', 400, 'EMPTY_ORDER');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Verificar productos y calcular total
    let total = 0;
    for (const item of productos) {
      const { rows } = await client.query(
        'SELECT precio FROM productos WHERE id = $1 AND activo = true',
        [item.producto_id]
      );
      if (rows.length === 0) {
        throw new AppError(`Producto ${item.producto_id} no existe o está inactivo.`, 400, 'PRODUCT_NOT_FOUND');
      }
      total += parseFloat(rows[0].precio) * item.cantidad;
    }

    // Insertar pedido
    const { rows: [pedido] } = await client.query(
      `INSERT INTO pedidos (mesa, estado, total, usuario_id, creado_en)
       VALUES ($1, 'pendiente', $2, $3, NOW())
       RETURNING *`,
      [mesa, total, usuario_id]
    );

    // Insertar detalle
    for (const item of productos) {
      await client.query(
        `INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, nota)
         VALUES ($1, $2, $3, $4)`,
        [pedido.id, item.producto_id, item.cantidad, item.nota || null]
      );
    }

    await client.query('COMMIT');
    logger.info('Pedido creado', { pedidoId: pedido.id, mesa, total });

    const completo = await obtenerPorId(pedido.id);
    if (io) io.emit('nuevo_pedido', completo);
    return completo;

  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/** Cambia el estado del pedido. Si pasa a 'listo', registra en ventas. */
async function cambiarEstado(id, estado, io = null) {
  if (!ESTADOS_VALIDOS.includes(estado)) {
    throw new AppError(
      `Estado inválido. Valores permitidos: ${ESTADOS_VALIDOS.join(', ')}.`,
      400, 'INVALID_STATUS'
    );
  }

  const { rows } = await pool.query(
    'UPDATE pedidos SET estado = $1 WHERE id = $2 RETURNING *',
    [estado, id]
  );
  if (rows.length === 0) {
    throw new AppError('Pedido no encontrado.', 404, 'ORDER_NOT_FOUND');
  }

  logger.info('Estado actualizado', { pedidoId: id, estado });

  // Si pasó a 'listo', registrar en tabla ventas
  if (estado === 'listo') {
    await pool.query(
      `INSERT INTO ventas (pedido_id, total, fecha)
       VALUES ($1, $2, NOW())
       ON CONFLICT (pedido_id) DO NOTHING`,
      [id, rows[0].total]
    );
  }

  const actualizado = await obtenerPorId(id);
  if (io) io.emit('pedido_actualizado', actualizado);
  return actualizado;
}

/** Cancela el pedido */
async function cancelar(id, io = null) {
  return cambiarEstado(id, 'cancelado', io);
}

/** Elimina un pedido (admin). Usa CASCADE en BD (pedido_detalle se borra automáticamente). */
async function eliminar(id) {
  const { rows } = await pool.query(
    'DELETE FROM pedidos WHERE id = $1 RETURNING *',
    [id]
  );
  if (rows.length === 0) {
    throw new AppError('Pedido no encontrado.', 404, 'ORDER_NOT_FOUND');
  }
  return rows[0];
}

module.exports = { listar, obtenerPorId, crear, cambiarEstado, cancelar, eliminar, ESTADOS_VALIDOS };