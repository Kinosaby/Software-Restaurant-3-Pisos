/**
 * pedidos.service.js — CRUD de pedidos con transacciones.
 * Columnas reales:
 *   pedidos:        id, mesa, estado, total, tipo, comensal, usuario_id, creado_en
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
 * @param {string|null} comensal  Etiqueta del comensal, ej. "C1", "Ana" (opcional)
 */
async function crear({ mesa, productos, tipo = 'aqui', comensal = null, usuario_id = null }, io = null) {
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
      `INSERT INTO pedidos (mesa, estado, total, tipo, comensal, usuario_id, creado_en)
       VALUES ($1, 'pendiente', $2, $3, $4, $5, NOW())
       RETURNING *`,
      [mesa, total, tipo || 'aqui', comensal || null, usuario_id]
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
 * Agrega productos a un pedido existente (cualquier estado activo).
 * Si el pedido está en listo/pagado, emite 'extra_pedido' con SOLO los items nuevos.
 * Si está en pendiente/preparando, emite 'pedido_actualizado' normal.
 */
async function agregarProductos(id, { productos, tipo }, io = null) {
  if (!productos || productos.length === 0) {
    throw new AppError('Debe incluir al menos un producto.', 400, 'EMPTY_ORDER');
  }

  const pedido = await obtenerPorId(id);
  // Permitir agregar a cualquier estado excepto cancelado
  if (pedido.estado === 'cancelado') {
    throw new AppError('No se puede modificar un pedido cancelado.', 400, 'INVALID_STATUS');
  }

  const esExtra = ['listo', 'pagado'].includes(pedido.estado);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    let totalExtra = 0;
    // Guardar los items nuevos con nombre para el evento extra
    const itemsNuevos = [];

    for (const item of productos) {
      const { rows: [prod] } = await client.query(
        'SELECT id, nombre, precio FROM productos WHERE id = $1 AND activo = true',
        [item.producto_id]
      );
      if (!prod) {
        throw new AppError(`Producto ${item.producto_id} no existe o está inactivo.`, 400, 'PRODUCT_NOT_FOUND');
      }

      totalExtra += parseFloat(prod.precio) * item.cantidad;
      itemsNuevos.push({
        nombre:   prod.nombre,
        cantidad: item.cantidad,
        nota:     item.nota || null,
        precio:   prod.precio,
      });

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

    // Actualizar total
    await client.query(
      'UPDATE pedidos SET total = total + $1 WHERE id = $2',
      [totalExtra, id]
    );

    await client.query('COMMIT');
    logger.info('Productos agregados al pedido', { pedidoId: id, totalExtra, esExtra });

    const actualizado = await obtenerPorId(id);

    if (io) {
      if (esExtra) {
        // Emitir SOLO los items nuevos — cocina no ve el pedido completo
        io.emit('extra_pedido', {
          pedido_id: id,
          mesa:      pedido.mesa,
          tipo:      tipo || pedido.tipo || 'aqui',
          items:     itemsNuevos,
          total_extra: totalExtra,
        });
      } else {
        // Pedido activo — emitir pedido completo actualizado
        io.emit('pedido_actualizado', { ...actualizado, _accion: 'productos_agregados' });
      }
    }

    return { ...actualizado, _items_nuevos: itemsNuevos, _es_extra: esExtra };

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
  // Se registra en listo Y en pagado para cubrir todos los flujos.
  // DO UPDATE garantiza que el total final siempre sea correcto.
  if (estado === 'listo' || estado === 'pagado') {
    try {
      await pool.query(
        `INSERT INTO ventas (pedido_id, total, fecha)
         VALUES ($1, $2, NOW())
         ON CONFLICT (pedido_id) DO UPDATE SET total = EXCLUDED.total`,
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

/**
 * Edita los items de un pedido existente (pendiente o preparando).
 * items: [{ detalle_id, cantidad, nota }]
 *   cantidad = 0 → elimina ese item
 *   cantidad > 0 → actualiza cantidad y nota
 * Recalcula el total y emite pedido_actualizado via socket.
 */
async function editarPedido(id, { items, mesa, tipo, comensal }, io = null) {
  if ((!items || items.length === 0) && mesa === undefined && tipo === undefined && comensal === undefined) {
    throw new AppError('Debe enviar al menos un campo a editar.', 400, 'EMPTY_FIELDS');
  }

  const pedido = await obtenerPorId(id);
  if (!['pendiente', 'preparando'].includes(pedido.estado)) {
    throw new AppError(
      `Solo se pueden editar pedidos pendientes o en preparación.`,
      400, 'INVALID_STATUS'
    );
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1. Actualizar metadatos si vienen
    if (mesa !== undefined || tipo !== undefined || comensal !== undefined) {
      const updates = [];
      const params = [];
      let idx = 1;
      if (mesa !== undefined) {
        updates.push(`mesa = $${idx++}`);
        params.push(mesa);
      }
      if (tipo !== undefined) {
        updates.push(`tipo = $${idx++}`);
        params.push(tipo);
      }
      if (comensal !== undefined) {
        updates.push(`comensal = $${idx++}`);
        params.push(comensal);
      }
      params.push(id);
      await client.query(
        `UPDATE pedidos SET ${updates.join(', ')} WHERE id = $${idx}`,
        params
      );
    }

    // 2. Actualizar items si vienen
    if (items && items.length > 0) {
      for (const item of items) {
        if (item.cantidad <= 0) {
          // Eliminar el item del detalle
          await client.query(
            'DELETE FROM pedido_detalle WHERE id = $1 AND pedido_id = $2',
            [item.detalle_id, id]
          );
        } else {
          // Actualizar cantidad y nota
          await client.query(
            'UPDATE pedido_detalle SET cantidad = $1, nota = $2 WHERE id = $3 AND pedido_id = $4',
            [item.cantidad, item.nota ?? null, item.detalle_id, id]
          );
        }
      }
    }

    // 3. Recalcular total desde cero sumando precio * cantidad del detalle actual
    const { rows: detalles } = await client.query(
      `SELECT pd.cantidad, pr.precio
       FROM pedido_detalle pd
       JOIN productos pr ON pr.id = pd.producto_id
       WHERE pd.pedido_id = $1`,
      [id]
    );

    if (detalles.length === 0) {
      await client.query('ROLLBACK');
      throw new AppError('El pedido no puede quedar sin productos.', 400, 'EMPTY_ORDER');
    }

    const nuevoTotal = detalles.reduce(
      (acc, r) => acc + parseFloat(r.precio) * r.cantidad, 0
    );

    await client.query(
      'UPDATE pedidos SET total = $1 WHERE id = $2',
      [nuevoTotal, id]
    );

    await client.query('COMMIT');
    logger.info('Pedido editado', { pedidoId: id, nuevoTotal });

    const actualizado = await obtenerPorId(id);
    if (io) io.emit('pedido_actualizado', { ...actualizado, _accion: 'pedido_editado' });
    return actualizado;

  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { listar, obtenerPorId, crear, agregarProductos, editarPedido, cambiarEstado, cancelar, eliminar, ESTADOS_VALIDOS };