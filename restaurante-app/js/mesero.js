/**
 * mesero.js — Panel del mesero: catálogo por secciones + carrito + pedidos + agregar a pedido
 */

const CATEGORIAS = [
  'Tortas','Guajolotes','Pambazos','Quesadillas','Enchiladas',
  'Tostadas','Volcanes','Tacos','Asada Fries','Burritos',
  'Gringas','Bebidas','Postres','General'
];

// Tipo de pedido: 'aqui' o 'llevar'
let _tipoPedido = 'aqui';

function setTipoPedido(tipo) {
  _tipoPedido = tipo;
  document.getElementById('btn-tipo-aqui')?.classList.toggle('active', tipo === 'aqui');
  document.getElementById('btn-tipo-llevar')?.classList.toggle('active', tipo === 'llevar');
}

/* ── Carga de datos ─────────────────────────── */
async function loadMeseroData() {
  loading(true);
  try {
    const [prods, peds] = await Promise.all([
      api.productos.listar(),
      api.pedidos.listar(),
    ]);
    State.productos = prods.productos || [];
    // Mesero ve pedidos más recientes primero
    State.pedidos   = (peds.pedidos || []).slice().reverse();
    renderCatalogo();
    renderMeseroPedidos();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

/* ── Catálogo con secciones y tabs ─────────── */
let _filtroCategoria = 'Todas';

function renderCatalogo() {
  const grid = document.getElementById('catalogo-grid');
  const tabsEl = document.getElementById('catalogo-tabs');
  if (!grid) return;

  const activos = State.productos.filter(p => p.activo !== false);

  // Construir tabs
  const catsConProductos = ['Todas', ...CATEGORIAS.filter(c =>
    activos.some(p => (p.categoria || 'General') === c)
  )];

  if (tabsEl) {
    tabsEl.innerHTML = catsConProductos.map(c => `
      <button class="cat-tab${c === _filtroCategoria ? ' active' : ''}"
              onclick="filtrarCategoria('${c}')">${c}</button>
    `).join('');
  }

  // Filtrar productos según tab activo
  const productosFiltrados = _filtroCategoria === 'Todas'
    ? activos
    : activos.filter(p => (p.categoria || 'General') === _filtroCategoria);

  if (!productosFiltrados.length) {
    grid.innerHTML = '<p class="muted text-sm" style="padding:16px">Sin productos en esta categoría.</p>';
    return;
  }

  if (_filtroCategoria !== 'Todas') {
    // Vista de una sola categoría — grid plano
    grid.innerHTML = productosFiltrados.map(p => renderProductoCard(p)).join('');
  } else {
    // Vista completa agrupada por sección
    const grupos = {};
    for (const p of productosFiltrados) {
      const cat = p.categoria || 'General';
      if (!grupos[cat]) grupos[cat] = [];
      grupos[cat].push(p);
    }

    // Renderizar en el orden definido de categorías
    let html = '';
    for (const cat of CATEGORIAS) {
      if (!grupos[cat]?.length) continue;
      html += `
        <div class="menu-seccion">
          <div class="menu-seccion-header">${cat}</div>
          <div class="productos-grid-inner">
            ${grupos[cat].map(p => renderProductoCard(p)).join('')}
          </div>
        </div>`;
    }
    grid.innerHTML = html;
  }
}

function renderProductoCard(p) {
  return `
    <div class="producto-card" onclick="addToCarrito(${p.id})" id="pcard-${p.id}">
      <span class="prod-cat">${p.categoria || 'General'}</span>
      <span class="prod-nom">${p.nombre}</span>
      <span class="prod-precio">${fmt.currency(p.precio)}</span>
    </div>`;
}

function filtrarCategoria(cat) {
  _filtroCategoria = cat;
  renderCatalogo();
}

/* ── Carrito multi-comensal ─────────────────────────────────── */
// _comensales: [{ nombre:'C1', items:[{producto_id,nombre,precio,cantidad,nota}] }, ...]
let _comensales     = [{ nombre: 'C1', items: [] }];
let _comensalActivo = 0;

function _carritoActivo() { return _comensales[_comensalActivo].items; }

function addToCarrito(productoId) {
  const prod = State.productos.find(p => p.id === productoId);
  if (!prod) return;
  const items    = _carritoActivo();
  const existing = items.find(i => i.producto_id === productoId);
  if (existing) { existing.cantidad++; }
  else { items.push({ producto_id: productoId, nombre: prod.nombre, precio: parseFloat(prod.precio), cantidad: 1, nota: '' }); }
  renderCarrito();
}

function changeQty(productoId, delta) {
  const items = _carritoActivo();
  const item  = items.find(i => i.producto_id === productoId);
  if (!item) return;
  item.cantidad += delta;
  if (item.cantidad <= 0) {
    _comensales[_comensalActivo].items = items.filter(i => i.producto_id !== productoId);
  }
  renderCarrito();
}

function setNota(productoId, nota) {
  const item = _carritoActivo().find(i => i.producto_id === productoId);
  if (item) item.nota = nota;
}

function clearCarrito() {
  _comensales     = [{ nombre: 'C1', items: [] }];
  _comensalActivo = 0;
  renderCarrito();
}

function agregarComensal() {
  const n = _comensales.length + 1;
  _comensales.push({ nombre: `C${n}`, items: [] });
  _comensalActivo = _comensales.length - 1;
  renderCarrito();
}

function cambiarComensal(idx) {
  _comensalActivo = idx;
  renderCarrito();
}

function quitarComensal(idx) {
  if (_comensales.length === 1) { clearCarrito(); return; }
  _comensales.splice(idx, 1);
  _comensales.forEach((c, i) => { if (/^C\d+$/.test(c.nombre)) c.nombre = `C${i + 1}`; });
  _comensalActivo = Math.min(_comensalActivo, _comensales.length - 1);
  renderCarrito();
}

function renderCarrito() {
  const body   = document.getElementById('carrito-body');
  const totEl  = document.getElementById('carrito-total');
  const cntEl  = document.getElementById('carrito-count');
  const tabsEl = document.getElementById('comensal-tabs');
  if (!body) return;

  // Tabs de comensales
  if (tabsEl) {
    tabsEl.innerHTML = _comensales.map((c, i) => {
      const totalC = c.items.reduce((s, it) => s + it.precio * it.cantidad, 0);
      const active = i === _comensalActivo ? 'active' : '';
      return `
        <div class="comensal-tab ${active}" onclick="cambiarComensal(${i})">
          <span>${c.nombre}</span>
          ${c.items.length ? `<span class="comensal-tab-total">${fmt.currency(totalC)}</span>` : ''}
          ${_comensales.length > 1 ? `<button class="comensal-tab-del" onclick="event.stopPropagation();quitarComensal(${i})" title="Quitar">&times;</button>` : ''}
        </div>`;
    }).join('') +
    `<button class="comensal-tab-add" onclick="agregarComensal()" title="Nuevo comensal">
       <i class="fa-solid fa-user-plus"></i>
     </button>`;
  }

  const items = _carritoActivo();

  if (!items.length) {
    body.innerHTML = '<p class="muted text-sm" style="text-align:center;padding:24px 0">Sin productos para este comensal</p>';
  } else {
    body.innerHTML = items.map(item => {
      const subtotal = item.precio * item.cantidad;
      return `
        <div class="carrito-item">
          <div style="flex:1">
            <div style="font-size:.84rem;font-weight:600">${item.nombre}</div>
            <div style="font-size:.73rem;color:var(--muted)">${fmt.currency(item.precio)} c/u &bull; <strong class="text-gold">${fmt.currency(subtotal)}</strong></div>
            <input class="nota-input" placeholder="Nota..." value="${item.nota || ''}"
              onchange="setNota(${item.producto_id}, this.value)" style="margin-top:5px">
          </div>
          <div class="carrito-qty">
            <button class="qty-btn" onclick="changeQty(${item.producto_id},-1)">−</button>
            <span style="min-width:22px;text-align:center;font-weight:600">${item.cantidad}</span>
            <button class="qty-btn" onclick="changeQty(${item.producto_id},1)">+</button>
          </div>
        </div>`;
    }).join('');
  }

  // Total global
  const totalGlobal = _comensales.reduce((s, c) => s + c.items.reduce((sc, it) => sc + it.precio * it.cantidad, 0), 0);
  const cntGlobal   = _comensales.reduce((s, c) => s + c.items.reduce((sc, it) => sc + it.cantidad, 0), 0);
  if (totEl) totEl.textContent = fmt.currency(totalGlobal);
  if (cntEl) cntEl.textContent = cntGlobal;
}

/* ── Enviar pedido(s) ───────────────────────────────────────── */
async function submitPedido() {
  const mesa = parseInt(document.getElementById('mesa-num').value, 10);
  if (!mesa || mesa < 1) { toastErr('Ingresa un número de mesa válido'); return; }

  const conItems = _comensales.filter(c => c.items.length > 0);
  if (!conItems.length) { toastErr('Agrega al menos un producto'); return; }

  const btn = document.getElementById('btn-enviar-pedido');
  btn.disabled = true;
  try {
    loading(true);
    for (const c of conItems) {
      await api.pedidos.crear({
        mesa,
        tipo:     _tipoPedido,
        comensal: _comensales.length > 1 ? c.nombre : null,
        productos: c.items.map(i => ({
          producto_id: i.producto_id,
          cantidad:    i.cantidad,
          nota:        i.nota || '',
        })),
      });
    }
    const totalEnviado = conItems.reduce((s, c) => s + c.items.reduce((sc, it) => sc + it.precio * it.cantidad, 0), 0);
    toastOk(`${conItems.length > 1 ? conItems.length + ' pedidos' : 'Pedido'} enviado(s) — Mesa ${mesa} (${fmt.currency(totalEnviado)})`);
    clearCarrito();
    document.getElementById('mesa-num').value = '';
    await loadMeseroData();
  } catch(e) { toastErr(e.message); }
  finally { btn.disabled = false; loading(false); }
}

/* ── Lista de pedidos agrupada por mesa ─────────────────────── */
function renderMeseroPedidos() {
  const list = document.getElementById('mesero-pedidos-list');
  if (!list) return;

  const activos = State.pedidos.filter(p => !['pagado','cancelado'].includes(p.estado));
  const pagados = State.pedidos.filter(p => p.estado === 'pagado');

  if (!activos.length && !pagados.length) {
    list.innerHTML = '<p class="muted text-sm" style="padding:16px">Sin pedidos activos</p>';
    return;
  }

  const grupos = {};
  [...activos, ...pagados].forEach(p => {
    if (!grupos[p.mesa]) grupos[p.mesa] = [];
    grupos[p.mesa].push(p);
  });

  const renderRow = (p) => {
    const puedeAgregar = p.estado !== 'cancelado';
    const puedeEditar  = ['pendiente','preparando'].includes(p.estado);
    const esCompletado = ['listo','pagado'].includes(p.estado);
    const labelC = p.comensal
      ? `<span class="badge-comensal"><i class="fa-solid fa-user"></i> ${p.comensal}</span>`
      : '';
    return `
    <div class="pedido-row pedido-row-sub" onclick="verDetallePedido(${p.id})">
      <div class="pedido-row-info">
        <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-bottom:4px">
          ${labelC}${badgeHtml(p.estado)}
        </div>
        <div class="text-xs muted">#${p.id} &middot; ${fmt.relTime(p.creado_en)}</div>
      </div>
      <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap;justify-content:flex-end">
        ${puedeEditar ? `<button class="btn btn-sm btn-edit" onclick="event.stopPropagation();abrirEditarPedido(${p.id})"><i class="fa-solid fa-pen-to-square"></i></button>` : ''}
        ${puedeAgregar ? `<button class="btn btn-sm ${esCompletado ? 'btn-amber' : 'btn-outline'}" onclick="event.stopPropagation();abrirAgregarProductos(${p.id})"><i class="fa-solid fa-plus"></i></button>` : ''}
        ${p.estado === 'listo' ? `<button class="btn btn-primary btn-sm" onclick="event.stopPropagation();abrirCobro(${p.id})"><i class="fa-solid fa-credit-card"></i> Cobrar</button>` : ''}
        <span class="text-gold fw600">${fmt.currency(p.total)}</span>
        ${p.estado !== 'pagado' ? `<button class="btn btn-danger btn-sm" onclick="event.stopPropagation();cancelarPedido(${p.id})"><i class="fa-solid fa-xmark"></i></button>` : ''}
      </div>
    </div>`;
  };

  let html = '';
  const mesasActivas = [...new Set(activos.map(p => p.mesa))];
  const mesasPagadas = [...new Set(pagados.map(p => p.mesa).filter(m => !mesasActivas.includes(m)))];

  mesasActivas.forEach(mesa => {
    const peds      = grupos[mesa].filter(p => !['pagado','cancelado'].includes(p.estado));
    const totalMesa = peds.reduce((s, p) => s + parseFloat(p.total || 0), 0);
    const listos    = peds.filter(p => p.estado === 'listo');
    const hayMulti  = peds.length > 1;
    html += `
    <div class="mesa-grupo">
      <div class="mesa-grupo-header">
        <span class="mesa-grupo-titulo"><i class="fa-solid fa-utensils"></i> Mesa ${mesa}${hayMulti ? ` <span class="muted text-xs">(${peds.length} cuentas)</span>` : ''}</span>
        <div style="display:flex;gap:6px;align-items:center">
          <span class="text-gold fw600 text-sm">${fmt.currency(totalMesa)}</span>
          ${listos.length > 1 ? `<button class="btn btn-primary btn-xs" onclick="cobrarTodoMesa(${mesa})"><i class="fa-solid fa-cash-register"></i> Cobrar todo</button>` : ''}
        </div>
      </div>
      ${peds.map(renderRow).join('')}
    </div>`;
  });

  if (pagados.length) {
    html += `<div class="seccion-pagados-header">Cobrados hoy <span class="muted text-xs">(piden mas?)</span></div>`;
    mesasPagadas.forEach(mesa => {
      const peds = grupos[mesa]?.filter(p => p.estado === 'pagado') || [];
      if (!peds.length) return;
      const totalMesa = peds.reduce((s, p) => s + parseFloat(p.total || 0), 0);
      html += `
      <div class="mesa-grupo">
        <div class="mesa-grupo-header">
          <span class="mesa-grupo-titulo"><i class="fa-solid fa-utensils"></i> Mesa ${mesa}</span>
          <span class="text-gold fw600 text-sm">${fmt.currency(totalMesa)}</span>
        </div>
        ${peds.map(renderRow).join('')}
      </div>`;
    });
  }

  list.innerHTML = html;
}

let _cobroPendientesMesa = [];

async function cobrarTodoMesa(mesa) {
  const listos = State.pedidos.filter(p => p.mesa === mesa && p.estado === 'listo');
  if (!listos.length) return;
  if (listos.length === 1) { abrirCobro(listos[0].id); return; }
  _cobroPendientesMesa = listos.slice(1).map(p => p.id);
  abrirCobro(listos[0].id);
}

/* ── Cobro con cambio ──────────────────────── */
let _pedidoCobrarId  = null;
let _pedidoCobrarTotal = 0;

function abrirCobro(pedidoId) {
  const p = State.pedidos.find(x => x.id === pedidoId);
  if (!p) return;
  _pedidoCobrarId    = pedidoId;
  _pedidoCobrarTotal = parseFloat(p.total);

  const content = document.getElementById('cobro-content');
  if (!content) return;

  content.innerHTML = `
    <div class="cobro-resumen">
      <div class="cobro-mesa">Mesa ${p.mesa} &nbsp;&nbsp; <span class="text-xs muted">#${p.id}</span></div>
      <div class="cobro-row">
        <span>Total a pagar</span>
        <span class="cobro-total">${fmt.currency(p.total)}</span>
      </div>
    </div>
    <div class="field" style="margin-top:16px">
      <label style="font-size:1rem">Con cu\u00e1nto paga el cliente</label>
      <input id="cobro-pago" type="number" step="0.50" min="0"
        placeholder="0.00"
        oninput="calcularCambio()"
        style="font-size:1.4rem;text-align:right;padding:12px 16px;letter-spacing:.05em">
    </div>
    <div class="cobro-cambio-wrap" id="cobro-cambio-wrap" style="display:none">
      <div class="cobro-row">
        <span>Cambio</span>
        <span id="cobro-cambio" class="cobro-cambio-val">$0.00</span>
      </div>
    </div>`;

  document.getElementById('btn-confirmar-cobro').disabled = true;
  openModal('modal-cobro');
  setTimeout(() => document.getElementById('cobro-pago')?.focus(), 120);
}

function calcularCambio() {
  const pago   = parseFloat(document.getElementById('cobro-pago')?.value) || 0;
  const cambio = pago - _pedidoCobrarTotal;
  const wrap   = document.getElementById('cobro-cambio-wrap');
  const val    = document.getElementById('cobro-cambio');
  const btn    = document.getElementById('btn-confirmar-cobro');

  if (!wrap || !val || !btn) return;

  if (pago <= 0) {
    wrap.style.display = 'none';
    btn.disabled = true;
    return;
  }

  wrap.style.display = 'block';
  val.textContent = fmt.currency(Math.max(0, cambio));
  val.className   = 'cobro-cambio-val ' + (cambio >= 0 ? 'cambio-ok' : 'cambio-err');
  btn.disabled    = cambio < 0;
}

async function confirmarCobro() {
  const btn = document.getElementById('btn-confirmar-cobro');
  if (btn) btn.disabled = true;
  try {
    loading(true);
    await api.pedidos.cambiarEstado(_pedidoCobrarId, 'pagado');
    const pago   = parseFloat(document.getElementById('cobro-pago')?.value) || 0;
    const cambio = pago - _pedidoCobrarTotal;
    toastOk(`Cobrado exitosamente. Cambio: ${fmt.currency(Math.max(0, cambio))}`);
    closeModal();
    await loadMeseroData();
  } catch(e) { toastErr(e.message); }
  finally { if (btn) btn.disabled = false; loading(false); }
}

async function cancelarPedido(id) {
  if (!confirm(`¿Cancelar pedido #${id}?`)) return;
  try {
    loading(true);
    await api.pedidos.cancelar(id);
    toastOk(`Pedido #${id} cancelado`);
    await loadMeseroData();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

function verDetallePedido(id) {
  const p = State.pedidos.find(x=>x.id===id);
  if (!p) return;
  const prods = (p.productos||[]).map(i=>`<li>${i.cantidad}× ${i.nombre}${i.nota?' <span class="muted">('+i.nota+')</span>':''}</li>`).join('');
  document.getElementById('detalle-content').innerHTML = `
    <div style="display:flex;gap:10px;align-items:center;margin-bottom:12px">
      <span class="brand-sm" style="font-family:var(--font-h)">Mesa ${p.mesa}</span>
      ${badgeHtml(p.estado)}
    </div>
    <ul style="list-style:none;display:flex;flex-direction:column;gap:6px;font-size:.88rem">${prods}</ul>
    <div class="divider" style="margin:14px 0"></div>
    <div class="total-row">
      <span class="total-label">Total</span>
      <span class="total-value">${fmt.currency(p.total)}</span>
    </div>
    <div class="text-xs muted" style="margin-top:8px">${fmt.date(p.creado_en)}</div>`;
  openModal('modal-detalle');
}

/* ── Agregar productos a pedido activo ──────── */
let _pedidoAgregarId = null;
let _carritoAgregar  = [];

function abrirAgregarProductos(pedidoId) {
  _pedidoAgregarId = pedidoId;
  _carritoAgregar  = [];
  const p = State.pedidos.find(x => x.id === pedidoId);
  if (!p) return;

  // Renderizar modal
  const content = document.getElementById('agregar-content');
  if (!content) return;

  const activos = State.productos.filter(x => x.activo !== false);
  content.innerHTML = `
    <div style="margin-bottom:12px;padding:10px;background:var(--surface2);border-radius:8px">
      <div class="fw600">Pedido #${p.id} — Mesa ${p.mesa}</div>
      <div class="text-xs muted">Ya tiene: ${(p.productos||[]).map(i=>i.cantidad+'× '+i.nombre).join(', ')}</div>
      <div class="fw600 text-gold" style="margin-top:4px">Total actual: ${fmt.currency(p.total)}</div>
    </div>
    <div class="text-sm muted" style="margin-bottom:8px">Selecciona los productos a agregar:</div>
    <div id="agregar-grid" class="productos-grid" style="max-height:280px;overflow-y:auto">
      ${activos.map(prod => `
        <div class="producto-card" onclick="addToAgregar(${prod.id})" id="agcard-${prod.id}">
          <span class="prod-cat">${prod.categoria||'General'}</span>
          <span class="prod-nom">${prod.nombre}</span>
          <span class="prod-precio">${fmt.currency(prod.precio)}</span>
        </div>`).join('')}
    </div>
    <div id="agregar-carrito" style="margin-top:12px"></div>`;

  openModal('modal-agregar');
}

function addToAgregar(productoId) {
  const prod = State.productos.find(p => p.id === productoId);
  if (!prod) return;
  const existing = _carritoAgregar.find(i => i.producto_id === productoId);
  if (existing) { existing.cantidad++; }
  else { _carritoAgregar.push({ producto_id: productoId, nombre: prod.nombre, precio: parseFloat(prod.precio), cantidad: 1, nota: '' }); }
  renderAgregarCarrito();
}

function changeQtyAgregar(productoId, delta) {
  const item = _carritoAgregar.find(i => i.producto_id === productoId);
  if (!item) return;
  item.cantidad += delta;
  if (item.cantidad <= 0) _carritoAgregar = _carritoAgregar.filter(i => i.producto_id !== productoId);
  renderAgregarCarrito();
}

function setNotaAgregar(productoId, nota) {
  const item = _carritoAgregar.find(i => i.producto_id === productoId);
  if (item) item.nota = nota;
}

function renderAgregarCarrito() {
  const el = document.getElementById('agregar-carrito');
  if (!el) return;
  if (!_carritoAgregar.length) { el.innerHTML = ''; return; }
  const total = _carritoAgregar.reduce((s,i) => s + i.precio * i.cantidad, 0);
  el.innerHTML = `
    <div class="divider" style="margin:8px 0"></div>
    <div class="fw600 text-sm" style="margin-bottom:6px">A agregar:</div>
    ${_carritoAgregar.map(item => `
      <div class="carrito-item" style="flex-direction:column;align-items:stretch;gap:6px">
        <div style="display:flex;align-items:center;gap:8px">
          <div style="flex:1;font-size:.83rem;font-weight:600">${item.nombre}</div>
          <div class="carrito-qty">
            <button class="qty-btn" onclick="changeQtyAgregar(${item.producto_id},-1)">−</button>
            <span style="min-width:20px;text-align:center;font-weight:600">${item.cantidad}</span>
            <button class="qty-btn" onclick="changeQtyAgregar(${item.producto_id},1)">+</button>
          </div>
          <span class="text-gold" style="font-size:.83rem;min-width:52px;text-align:right">${fmt.currency(item.precio * item.cantidad)}</span>
        </div>
        <input class="nota-input" placeholder="Indicaciones: sin cebolla, extra salsa..."
          value="${item.nota || ''}"
          oninput="setNotaAgregar(${item.producto_id}, this.value)">
      </div>`).join('')}
    <div class="total-row" style="margin-top:8px">
      <span class="total-label">Subtotal a agregar</span>
      <span class="total-value">${fmt.currency(total)}</span>
    </div>`;
}

async function confirmarAgregarProductos() {
  if (!_carritoAgregar.length) { toastErr('Selecciona al menos un producto'); return; }
  const btn = document.getElementById('btn-confirmar-agregar');
  if (btn) btn.disabled = true;
  try {
    loading(true);
    await api.pedidos.agregar(_pedidoAgregarId, {
      productos: _carritoAgregar.map(i => ({
        producto_id: i.producto_id,
        cantidad:    i.cantidad,
        nota:        i.nota || '',
      }))
    });
    toastOk(`Productos agregados al pedido #${_pedidoAgregarId}`);
    closeModal();
    _carritoAgregar = [];
    await loadMeseroData();
  } catch(e) { toastErr(e.message); }
  finally { if (btn) btn.disabled = false; loading(false); }
}

/* ── Editar pedido (quitar / cambiar cantidad) ──────────────── */
let _pedidoEditarId = null;
let _edicionItems   = [];   // [{ detalle_id, producto_id, nombre, precio, cantidad, nota }]

function abrirEditarPedido(pedidoId) {
  const p = State.pedidos.find(x => x.id === pedidoId);
  if (!p) return;
  _pedidoEditarId = pedidoId;
  // Clonar items actuales del pedido
  _edicionItems = (p.productos || []).map(i => ({
    detalle_id:  i.id,
    producto_id: i.producto_id,
    nombre:      i.nombre,
    precio:      parseFloat(i.precio),
    cantidad:    i.cantidad,
    nota:        i.nota || '',
  }));

  renderEdicionModal(p);
  openModal('modal-editar');
}

function renderEdicionModal(p) {
  const content = document.getElementById('editar-content');
  if (!content) return;

  const total = _edicionItems.reduce((s, i) => s + i.precio * i.cantidad, 0);
  const hayItems = _edicionItems.length > 0;

  content.innerHTML = `
    <div class="cobro-resumen" style="margin-bottom:14px">
      <div class="cobro-mesa">Mesa ${p.mesa} &nbsp;<span class="text-xs muted">#${p.id}</span></div>
    </div>
    ${!hayItems ? '<p class="muted text-sm" style="text-align:center;padding:16px">Sin productos — guarda para cancelar el pedido.</p>' : ''}
    <div style="display:flex;flex-direction:column;gap:10px">
      ${_edicionItems.map((item, idx) => `
        <div class="editar-item-row" id="edit-row-${idx}">
          <div class="editar-item-info">
            <span class="editar-item-nom">${item.nombre}</span>
            <span class="editar-item-precio muted text-xs">${fmt.currency(item.precio)} c/u</span>
          </div>
          <div class="editar-item-controls">
            <button class="qty-btn" onclick="editarCantidad(${idx},-1)">-</button>
            <span class="editar-qty" id="edit-qty-${idx}">${item.cantidad}</span>
            <button class="qty-btn" onclick="editarCantidad(${idx},1)">+</button>
            <button class="btn btn-danger btn-xs" onclick="quitarItemEdicion(${idx})" title="Quitar">
              <i class="fa-solid fa-trash"></i>
            </button>
          </div>
          <input class="nota-input" style="width:100%;margin-top:6px"
            placeholder="Nota: sin cebolla..."
            value="${item.nota}"
            oninput="editarNota(${idx}, this.value)">
          <div class="editar-item-subtotal text-gold text-xs" id="edit-sub-${idx}">${fmt.currency(item.precio * item.cantidad)}</div>
        </div>`).join('')}
    </div>
    <div class="divider" style="margin:14px 0"></div>
    <div class="total-row">
      <span class="total-label">Nuevo total</span>
      <span class="total-value" id="editar-total">${fmt.currency(total)}</span>
    </div>`;

  // Actualizar estado del botón guardar
  const btn = document.getElementById('btn-confirmar-editar');
  if (btn) btn.disabled = !hayItems;
}

function editarCantidad(idx, delta) {
  const item = _edicionItems[idx];
  if (!item) return;
  item.cantidad = Math.max(1, item.cantidad + delta);
  // Actualizar UI sin re-renderizar todo
  const qtyEl = document.getElementById(`edit-qty-${idx}`);
  const subEl = document.getElementById(`edit-sub-${idx}`);
  const totEl = document.getElementById('editar-total');
  if (qtyEl) qtyEl.textContent = item.cantidad;
  if (subEl) subEl.textContent = fmt.currency(item.precio * item.cantidad);
  if (totEl) totEl.textContent = fmt.currency(_edicionItems.reduce((s,i) => s + i.precio * i.cantidad, 0));
}

function quitarItemEdicion(idx) {
  _edicionItems.splice(idx, 1);
  const p = State.pedidos.find(x => x.id === _pedidoEditarId);
  renderEdicionModal(p || { mesa: '?', id: _pedidoEditarId });
}

function editarNota(idx, nota) {
  if (_edicionItems[idx]) _edicionItems[idx].nota = nota;
}

async function guardarEdicion() {
  if (!_edicionItems.length) { toastErr('El pedido debe tener al menos un producto'); return; }
  const btn = document.getElementById('btn-confirmar-editar');
  if (btn) btn.disabled = true;
  try {
    loading(true);

    // Items que quedaron activos (con cantidad/nota actualizados)
    const itemsActivos = _edicionItems.map(i => ({
      detalle_id: i.detalle_id,
      cantidad:   i.cantidad,
      nota:       i.nota,
    }));

    // Items que fueron quitados → enviar cantidad=0 para que el backend los elimine
    const pedidoOriginal  = State.pedidos.find(x => x.id === _pedidoEditarId);
    const idsActuales     = new Set(_edicionItems.map(i => i.detalle_id));
    const itemsEliminados = (pedidoOriginal?.productos || [])
      .filter(p => !idsActuales.has(p.id))
      .map(p => ({ detalle_id: p.id, cantidad: 0, nota: '' }));

    // Una sola llamada con todos los cambios
    await api.pedidos.editar(_pedidoEditarId, {
      items: [...itemsActivos, ...itemsEliminados],
    });

    toastOk(`Pedido #${_pedidoEditarId} actualizado`);
    closeModal();
    await loadMeseroData();
  } catch(e) { toastErr(e.message); }
  finally { if (btn) btn.disabled = false; loading(false); }
}

