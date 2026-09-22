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

async function adjuntarDetalles(pedidos) {
  if (pedidos.length === 0) return pedidos;

  const ids = pedidos.map((pedido) => pedido.id);
  const placeholders = ids.map((_, index) => `$${index + 1}`).join(', ');
  const { rows: detalles } = await pool.query(
    `SELECT pd.id,
            pd.pedido_id,
            pd.producto_id,
            pr.nombre,
            pd.cantidad,
            pd.nota,
            COALESCE(pd.precio_unitario, pr.precio) AS precio
     FROM pedido_detalle pd
     JOIN productos pr ON pr.id = pd.producto_id
     WHERE pd.pedido_id IN (${placeholders})
     ORDER BY pd.id ASC`,
    ids
  );

  const porPedido = new Map();
  for (const detalle of detalles) {
    const lista = porPedido.get(detalle.pedido_id) || [];
    lista.push(detalle);
    porPedido.set(detalle.pedido_id, lista);
  }

  return pedidos.map((pedido) => ({
    ...pedido,
    productos: porPedido.get(pedido.id) || [],
  }));
}

/** Devuelve todos los pedidos con su detalle, orden FIFO (más antiguo primero) */
async function listar({ estado } = {}) {
  let query  = 'SELECT * FROM pedidos';
  const params = [];

  if (estado && ESTADOS_VALIDOS.includes(estado)) {
    query += ' WHERE estado = $1';
    params.push(estado);
  }

  // FIFO: el pedido más antiguo aparece primero en cocina
  query += ' ORDER BY creado_en ASC, id ASC';
  const { rows } = await pool.query(query, params);
  return adjuntarDetalles(rows);
}

/** Devuelve un pedido por id con su detalle */
async function obtenerPorId(id) {
  const { rows } = await pool.query(
    'SELECT * FROM pedidos WHERE id = $1',
    [id]
  );
  if (rows.length === 0) {
    throw new AppError('Pedido no encontrado.', 404, 'ORDER_NOT_FOUND');
  }
  const [pedido] = await adjuntarDetalles(rows);
  return pedido;
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
    const precios = new Map();
    for (const item of productos) {
      const { rows } = await client.query(
        'SELECT id, precio FROM productos WHERE id = $1 AND activo = true',
        [item.producto_id]
      );
      if (rows.length === 0) {
        throw new AppError(`Producto ${item.producto_id} no existe o está inactivo.`, 400, 'PRODUCT_NOT_FOUND');
      }
      total += parseFloat(rows[0].precio) * item.cantidad;
      precios.set(item.producto_id, rows[0].precio);
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
        `INSERT INTO pedido_detalle
           (pedido_id, producto_id, cantidad, precio_unitario, nota)
         VALUES ($1, $2, $3, $4, $5)`,
        [
          pedido.id,
          item.producto_id,
          item.cantidad,
          precios.get(item.producto_id),
          item.nota || null,
        ]
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
  if (['pagado', 'cancelado'].includes(pedido.estado)) {
    throw new AppError(
      'No se puede modificar un pedido pagado o cancelado.',
      400,
      'INVALID_STATUS'
    );
  }

  const esExtra = pedido.estado === 'listo';

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

      const nota = item.nota || null;
      const { rows: existing } = await client.query(
        `SELECT id, cantidad
         FROM pedido_detalle
         WHERE pedido_id = $1
           AND producto_id = $2
           AND COALESCE(nota, '') = COALESCE($3, '')`,
        [id, item.producto_id, nota]
      );

      if (existing.length > 0) {
        await client.query(
          'UPDATE pedido_detalle SET cantidad = cantidad + $1 WHERE id = $2',
          [item.cantidad, existing[0].id]
        );
      } else {
        await client.query(
          `INSERT INTO pedido_detalle
             (pedido_id, producto_id, cantidad, precio_unitario, nota)
           VALUES ($1, $2, $3, $4, $5)`,
          [id, item.producto_id, item.cantidad, prod.precio, nota]
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
          comensal:  pedido.comensal,
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

const TRANSICIONES = {
  pendiente:  ['preparando', 'cancelado'],
  preparando: ['pendiente', 'listo', 'cancelado'],
  listo:      ['preparando', 'pagado', 'cancelado'],
  pagado:     [],
  cancelado:  [],
};

const TRANSICIONES_POR_ROL = {
  cocina: {
    pendiente: ['preparando'],
    preparando: ['listo'],
  },
  mesero: {
    pendiente: ['cancelado'],
    preparando: ['cancelado'],
    listo: ['pagado', 'cancelado'],
  },
};

function puedeCambiarEstado(actual, siguiente, actorRole) {
  if (actual === siguiente) return true;
  const permitidas = actorRole === 'admin'
    ? (TRANSICIONES[actual] || [])
    : (TRANSICIONES_POR_ROL[actorRole]?.[actual] || []);
  return permitidas.includes(siguiente);
}

/** Cambia el estado del pedido y registra la venta de forma atómica al cobrar. */
async function cambiarEstado(id, estado, io = null, actorRole = 'admin') {
  if (!ESTADOS_VALIDOS.includes(estado)) {
    throw new AppError(
      `Estado inválido. Valores permitidos: ${ESTADOS_VALIDOS.join(', ')}.`,
      400, 'INVALID_STATUS'
    );
  }

  const client = await pool.connect();
  let pedido;
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      'SELECT * FROM pedidos WHERE id = $1 FOR UPDATE',
      [id]
    );
    if (rows.length === 0) {
      throw new AppError('Pedido no encontrado.', 404, 'ORDER_NOT_FOUND');
    }

    pedido = rows[0];
    if (pedido.estado === estado) {
      await client.query('COMMIT');
      return obtenerPorId(id);
    }

    if (!puedeCambiarEstado(pedido.estado, estado, actorRole)) {
      throw new AppError(
        `El rol ${actorRole} no puede cambiar un pedido de ${pedido.estado} a ${estado}.`,
        403,
        'INVALID_STATUS_TRANSITION'
      );
    }

    const { rows: [actualizadoBase] } = await client.query(
      'UPDATE pedidos SET estado = $1 WHERE id = $2 RETURNING *',
      [estado, id]
    );

    if (estado === 'pagado') {
      await client.query(
        `INSERT INTO ventas (pedido_id, total, fecha)
         VALUES ($1, $2, NOW())
         ON CONFLICT (pedido_id)
         DO UPDATE SET total = EXCLUDED.total, fecha = EXCLUDED.fecha`,
        [id, actualizadoBase.total]
      );
    }

    if (estado === 'cancelado') {
      await client.query('DELETE FROM ventas WHERE pedido_id = $1', [id]);
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  logger.info('Estado actualizado', {
    pedidoId: id,
    anterior: pedido.estado,
    estado,
    actorRole,
  });

  const actualizado = await obtenerPorId(id);
  if (io) io.emit('pedido_actualizado', actualizado);

  return actualizado;
}

/** Cancela el pedido */
async function cancelar(id, io = null, actorRole = 'mesero') {
  return cambiarEstado(id, 'cancelado', io, actorRole);
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
      `SELECT pd.cantidad, COALESCE(pd.precio_unitario, pr.precio) AS precio
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

module.exports = {
  listar,
  obtenerPorId,
  crear,
  agregarProductos,
  editarPedido,
  cambiarEstado,
  cancelar,
  eliminar,
  puedeCambiarEstado,
  ESTADOS_VALIDOS,
};
