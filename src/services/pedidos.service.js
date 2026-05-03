/**
 * pedidos.service.js — CRUD de pedidos con transacciones.
 * Columnas reales:
 *   pedidos:        id, mesa, estado, total, tipo, usuario_id, creado_en
 *   pedido_detalle: id, pedido_id, producto_id, cantidad, nota
 *   productos:      id, nombre, precio, activo
 *   ventas:         id, pedido_id, total, fecha
 *
 * Estados válidos: pendiente | preparando | listo | pagado | cancelado
 * Tipos:           aqui | llevar
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

/** Devuelve todos los pedidos con su detalle, orden FIFO (más antiguo primero) */
async function listar({ estado } = {}) {
  let query  = QUERY_DETALLE;
  const params = [];

  if (estado && ESTADOS_VALIDOS.includes(estado)) {
    query += ' WHERE p.estado = $1';
    params.push(estado);
  }

  // FIFO: el pedido más antiguo aparece primero en cocina
  query += ' GROUP BY p.id ORDER BY p.creado_en ASC, p.id ASC';
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
 */
async function crear({ mesa, productos, tipo = 'aqui', usuario_id = null }, io = null) {
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
      `INSERT INTO pedidos (mesa, estado, total, tipo, usuario_id, creado_en)
       VALUES ($1, 'pendiente', $2, $3, $4, NOW())
       RETURNING *`,
      [mesa, total, tipo || 'aqui', usuario_id]
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

/**
 * Agrega productos a un pedido existente (pendiente o preparando).
 * Cocina recibe notificación de pedido actualizado.
 */
async function agregarProductos(id, { productos }, io = null) {
  if (!productos || productos.length === 0) {
    throw new AppError('Debe incluir al menos un producto.', 400, 'EMPTY_ORDER');
  }

  const pedido = await obtenerPorId(id);
  if (!['pendiente', 'preparando'].includes(pedido.estado)) {
    throw new AppError(
      `No se puede modificar un pedido en estado "${pedido.estado}". Solo pendiente o preparando.`,
      400, 'INVALID_STATUS'
    );
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    let totalExtra = 0;

    for (const item of productos) {
      // Verificar que el producto existe y está activo
      const { rows: [prod] } = await client.query(
        'SELECT id, precio FROM productos WHERE id = $1 AND activo = true',
        [item.producto_id]
      );
      if (!prod) {
        throw new AppError(`Producto ${item.producto_id} no existe o está inactivo.`, 400, 'PRODUCT_NOT_FOUND');
      }

      totalExtra += parseFloat(prod.precio) * item.cantidad;

      // Si ya existe el producto en el detalle, aumentar cantidad; si no, insertar
      const { rows: existing } = await client.query(
        'SELECT id, cantidad FROM pedido_detalle WHERE pedido_id = $1 AND producto_id = $2',
        [id, item.producto_id]
      );

      if (existing.length > 0) {
        await client.query(
          'UPDATE pedido_detalle SET cantidad = cantidad + $1 WHERE id = $2',
          [item.cantidad, existing[0].id]
        );
      } else {
        await client.query(
          'INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, nota) VALUES ($1, $2, $3, $4)',
          [id, item.producto_id, item.cantidad, item.nota || null]
        );
      }
    }

    // Recalcular total del pedido
    await client.query(
      'UPDATE pedidos SET total = total + $1 WHERE id = $2',
      [totalExtra, id]
    );

    await client.query('COMMIT');
    logger.info('Productos agregados al pedido', { pedidoId: id, totalExtra });

    const actualizado = await obtenerPorId(id);
    if (io) io.emit('pedido_actualizado', { ...actualizado, _accion: 'productos_agregados' });
    return actualizado;

  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/** Cambia el estado del pedido. Socket se emite SIEMPRE; ventas en try/catch propio. */
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

  // Emitir socket PRIMERO — antes de intentar registrar la venta
  const actualizado = await obtenerPorId(id);
  if (io) io.emit('pedido_actualizado', actualizado);

  // Registrar en ventas en try/catch propio — no bloquea la respuesta
  if (estado === 'listo') {
    try {
      await pool.query(
        `INSERT INTO ventas (pedido_id, total, fecha)
         VALUES ($1, $2, NOW())
         ON CONFLICT (pedido_id) DO NOTHING`,
        [id, rows[0].total]
      );
    } catch (e) {
      logger.error('Error registrando venta (no critico)', { pedidoId: id, error: e.message });
    }
  }

  return actualizado;
}

/** Cancela el pedido */
async function cancelar(id, io = null) {
  return cambiarEstado(id, 'cancelado', io);
}

/** Elimina un pedido (admin). Usa CASCADE en BD. */
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

module.exports = { listar, obtenerPorId, crear, agregarProductos, cambiarEstado, cancelar, eliminar, ESTADOS_VALIDOS };