/**
 * mesero.js — Panel del mesero: catálogo por secciones + carrito + pedidos + agregar a pedido
 */

const CATEGORIAS = [
  'Tortas','Guajolotes','Pambazos','Quesadillas','Enchiladas',
  'Tostadas','Volcanes','Tacos','Asada Fries','Burritos',
  'Gringas','Bebidas','Postres','General'
];

// ── Configuración de mesas ─────────────────────────────────────
const TOTAL_MESAS = 13;   // <── Cambia este número si el restaurante tiene más/menos mesas

// Tipo de pedido: 'aqui' o 'llevar'
let _tipoPedido = 'aqui';

function setTipoPedido(tipo) {
  _tipoPedido = tipo;
  document.getElementById('btn-tipo-aqui')?.classList.toggle('active', tipo === 'aqui');
  document.getElementById('btn-tipo-llevar')?.classList.toggle('active', tipo === 'llevar');

  if (tipo === 'llevar') {
    if (_mesaSeleccionada === null) {
      _mesaSeleccionada = 99;
      const numInput = document.getElementById('mesa-num');
      if (numInput) numInput.value = 99;
      const badge = document.getElementById('mesa-badge');
      const badgeText = document.getElementById('mesa-badge-text');
      if (badge) badge.classList.add('mesa-badge-activa');
      if (badgeText) badgeText.textContent = "Para Llevar";
    }
  } else if (tipo === 'aqui') {
    if (_mesaSeleccionada === 99) {
      limpiarMesaSeleccionada();
    }
  }
}

/* ── Selector de Mesa ─────────────────────────────────────────── */
let _mesaSeleccionada = null;

function abrirSelectorMesa() {
  renderMesaSelector();
  document.getElementById('overlay-mesa-selector')?.classList.add('open');
}

function cerrarSelectorMesa() {
  document.getElementById('overlay-mesa-selector')?.classList.remove('open');
}

function seleccionarMesa(num) {
  if (num !== 99) {
    // Verificar si la mesa tiene pedidos activos de OTRO mesero/sesión
    // (pedidos en estado pendiente, preparando o listo)
    const activos = (State.pedidos || []).filter(p =>
      p.mesa === num &&
      !['pagado','cancelado'].includes(p.estado)
    );

    if (activos.length > 0 && _mesaSeleccionada !== num) {
      // Mesa ocupada — mostrar confirmación en vez de bloquear
      const confirmed = confirm(`La Mesa ${num} ya tiene pedidos activos. ¿Deseas agregar más comensales o pedidos a esta mesa?`);
      if (!confirmed) {
        return;
      }
    }
  }

  // Permitir re-seleccionar la misma mesa (para agregar más pedidos)
  _mesaSeleccionada = num;
  document.getElementById('mesa-num').value = num;

  // Actualizar badge
  const badge = document.getElementById('mesa-badge');
  const badgeText = document.getElementById('mesa-badge-text');
  if (badge) badge.classList.add('mesa-badge-activa');
  if (badgeText) badgeText.textContent = num === 99 ? 'Para Llevar' : `Mesa ${num}`;

  cerrarSelectorMesa();
  toastOk(num === 99 ? 'Para Llevar seleccionado' : `Mesa ${num} seleccionada`);
}

function limpiarMesaSeleccionada() {
  _mesaSeleccionada = null;
  document.getElementById('mesa-num').value = '';
  const badge = document.getElementById('mesa-badge');
  const badgeText = document.getElementById('mesa-badge-text');
  if (badge) badge.classList.remove('mesa-badge-activa');
  if (badgeText) badgeText.textContent = 'Seleccionar mesa';
}

function renderMesaSelector() {
  const grid = document.getElementById('mesa-selector-grid');
  if (!grid) return;

  // Mesas con pedidos activos (pendiente, preparando o listo) = ocupadas
  const mesasOcupadas = new Set(
    (State.pedidos || [])
      .filter(p => !['pagado','cancelado'].includes(p.estado))
      .map(p => p.mesa)
  );

  let html = '';
  for (let i = 1; i <= TOTAL_MESAS; i++) {
    const ocupada  = mesasOcupadas.has(i);
    const activa   = _mesaSeleccionada === i;
    const cls = activa ? 'mesa-btn activa' : ocupada ? 'mesa-btn ocupada' : 'mesa-btn libre';
    html += `
      <button class="${cls}" onclick="seleccionarMesa(${i})">
        <span class="mesa-num-big">${i}</span>
        ${ocupada ? '<span class="mesa-estado-label">Ocupada</span>' : '<span class="mesa-estado-label">Libre</span>'}
      </button>`;
  }
  grid.innerHTML = html;
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
    if (typeof renderMesaSelector === 'function') renderMesaSelector();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

/* ── Catálogo ───────────────────────────────── */
let _filtroCategoria = 'Todas';
let _busqueda = '';

function renderCatalogo() {
  const grid   = document.getElementById('catalogo-grid');
  const tabsEl = document.getElementById('catalogo-tabs');
  const searchEl = document.getElementById('catalogo-search');
  if (!grid) return;

  const activos = State.productos.filter(p => p.activo !== false);

  // Categorías que tienen productos
  const catsConProductos = ['Todas', ...CATEGORIAS.filter(c =>
    activos.some(p => (p.categoria || 'General') === c)
  )];

  // Tabs de categorías
  if (tabsEl) {
    tabsEl.innerHTML = catsConProductos.map(c => {
      const count = c === 'Todas' ? activos.length
        : activos.filter(p => (p.categoria || 'General') === c).length;
      return `<button class="cat-tab${c === _filtroCategoria ? ' active' : ''}"
        onclick="filtrarCategoria('${c}')">
        ${c} <span class="cat-tab-count">${count}</span>
      </button>`;
    }).join('');
  }

  // Filtrar por categoría y búsqueda
  let filtrados = _filtroCategoria === 'Todas'
    ? activos
    : activos.filter(p => (p.categoria || 'General') === _filtroCategoria);

  if (_busqueda.trim()) {
    const q = _busqueda.trim().toLowerCase();
    filtrados = filtrados.filter(p => p.nombre.toLowerCase().includes(q));
  }

  if (!filtrados.length) {
    grid.innerHTML = '<p class="muted text-sm" style="padding:24px;text-align:center">Sin productos encontrados</p>';
    return;
  }

  // Grid plano — siempre, sin agrupar en secciones
  grid.innerHTML = filtrados.map(p => renderProductoCard(p)).join('');
}

// Colores de acento por categoría
const CAT_COLORS = {
  'Tortas':'#e05500','Guajolotes':'#d4a843','Pambazos':'#c084fc',
  'Quesadillas':'#fb923c','Enchiladas':'#f87171','Tostadas':'#facc15',
  'Volcanes':'#a78bfa','Tacos':'#ff9500','Asada Fries':'#f59e0b',
  'Burritos':'#34d399','Gringas':'#60a5fa','Bebidas':'#38bdf8',
  'Postres':'#f472b6','General':'#8a7060',
};

function renderProductoCard(p) {
  const color = CAT_COLORS[p.categoria] || CAT_COLORS['General'];
  return `
    <div class="producto-card" onclick="addToCarrito(${p.id})" id="pcard-${p.id}">
      <div class="prod-color-bar" style="background:${color}"></div>
      <div class="prod-body">
        <span class="prod-cat">${p.categoria || 'General'}</span>
        <span class="prod-nom">${p.nombre}</span>
        <span class="prod-precio">${fmt.currency(p.precio)}</span>
      </div>
      <div class="prod-add-btn"><i class="fa-solid fa-plus"></i></div>
    </div>`;
}

function filtrarCategoria(cat) {
  _filtroCategoria = cat;
  renderCatalogo();
}

function buscarProducto(val) {
  _busqueda = val;
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
  else { items.push({ producto_id: productoId, nombre: prod.nombre, precio: parseFloat(prod.precio), cantidad: 1, nota: '', esLlevar: false }); }
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

function toggleCartItemLlevar(productoId) {
  const items = _carritoActivo();
  const item = items.find(i => i.producto_id === productoId);
  if (item) item.esLlevar = !item.esLlevar;
  renderCarrito();
}

function clearCarrito() {
  _comensales     = [{ nombre: 'C1', items: [] }];
  _comensalActivo = 0;
  renderCarrito();
}

function agregarComensal() {
  const n = _comensales.length + 1;
  let nombre = prompt("Nombre o etiqueta del comensal:");
  if (nombre === null || nombre.trim() === "") {
    nombre = `C${n}`;
  } else {
    nombre = nombre.trim();
  }
  _comensales.push({ nombre: nombre, items: [] });
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
            <button type="button" class="qty-btn ${item.esLlevar ? 'active' : ''}" style="margin-left:8px; background:${item.esLlevar ? 'var(--accent)' : 'none'}; border:1px solid var(--border); color:${item.esLlevar ? '#000' : 'var(--muted)'}" onclick="toggleCartItemLlevar(${item.producto_id})" title="Llevar"><i class="fa-solid fa-bag-shopping"></i></button>
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
  if (!mesa || mesa < 1) {
    toastErr('Selecciona una mesa primero');
    abrirSelectorMesa();
    return;
  }

  // Doble verificación en el momento de enviar
  const activosAhora = (State.pedidos || []).filter(p =>
    p.mesa === mesa && !['pagado','cancelado'].includes(p.estado)
  );
  if (activosAhora.length > 0 && _mesaSeleccionada !== mesa) {
    toastErr(`⚠️ Mesa ${mesa} ya está siendo atendida por otro mesero`);
    limpiarMesaSeleccionada();
    return;
  }

  const conItems = _comensales.filter(c => c.items.length > 0);
  if (!conItems.length) { toastErr('Agrega al menos un producto'); return; }

  const confirmed = confirm("El pedido es correcto, ¿enviar?");
  if (!confirmed) return;

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
          nota:        i.esLlevar ? '[LLEVAR] ' + (i.nota || '').trim() : (i.nota || ''),
        })),
      });
    }
    const totalEnviado = conItems.reduce((s, c) => s + c.items.reduce((sc, it) => sc + it.precio * it.cantidad, 0), 0);
    toastOk(`${conItems.length > 1 ? conItems.length + ' pedidos' : 'Pedido'} enviado(s) — Mesa ${mesa} (${fmt.currency(totalEnviado)})`);
    clearCarrito();
    limpiarMesaSeleccionada();
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
    const descProductos = (p.productos || []).map(i => `${i.cantidad}x ${i.nombre}`).join(', ');
    return `
    <div class="pedido-row pedido-row-sub" onclick="verDetallePedido(${p.id})">
      <div class="pedido-row-info">
        <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-bottom:4px">
          ${labelC}${badgeHtml(p.estado)}
        </div>
        <div class="text-xs muted">#${p.id} &middot; ${fmt.relTime(p.creado_en)}</div>
        ${descProductos ? `<div style="font-size:0.75rem; font-style:italic; color:var(--muted); margin-top:2px;">${descProductos}</div>` : ''}
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

/** Cobrar todos los comensales de una mesa en UN solo modal con total combinado */
async function cobrarTodoMesa(mesa) {
  const listos = State.pedidos.filter(p => p.mesa === mesa && p.estado === 'listo');
  if (!listos.length) return;
  if (listos.length === 1) { abrirCobro(listos[0].id); return; }

  // Cobro unificado: guardar todos los ids
  _cobroPendientesMesa = listos.map(p => p.id);
  const totalCombinado = listos.reduce((s, p) => s + parseFloat(p.total || 0), 0);

  // Usar primer pedido como referencia de mesa
  const refPedido = listos[0];
  _pedidoCobrarId    = null;  // null indica cobro múltiple
  _pedidoCobrarTotal = totalCombinado;

  const content = document.getElementById('cobro-content');
  if (!content) return;

  const desglose = listos.map(p => {
    const label = p.comensal ? `<span class="badge-comensal"><i class="fa-solid fa-user"></i> ${p.comensal}</span>` : `#${p.id}`;
    return `<div class="cobro-row" style="font-size:.84rem">
      <span>${label}</span>
      <span>${fmt.currency(p.total)}</span>
    </div>`;
  }).join('');

  content.innerHTML = `
    <div class="cobro-resumen">
      <div class="cobro-mesa">Mesa ${refPedido.mesa} &nbsp;&nbsp; <span class="text-xs muted">${listos.length} cuentas</span></div>
      ${desglose}
      <div class="divider" style="margin:10px 0"></div>
      <div class="cobro-row">
        <span style="font-weight:700">Total a pagar</span>
        <span class="cobro-total">${fmt.currency(totalCombinado)}</span>
      </div>
    </div>
    <div class="field" style="margin-top:16px">
      <label style="font-size:1rem">Con cu\u00e1nto paga</label>
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
    const pago   = parseFloat(document.getElementById('cobro-pago')?.value) || 0;
    const cambio = pago - _pedidoCobrarTotal;

    if (_pedidoCobrarId !== null) {
      // Cobro individual
      await api.pedidos.cambiarEstado(_pedidoCobrarId, 'pagado');
    } else {
      // Cobro múltiple: marcar todos como pagado en paralelo
      await Promise.all(_cobroPendientesMesa.map(id => api.pedidos.cambiarEstado(id, 'pagado')));
      _cobroPendientesMesa = [];
    }

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
      <span class="brand-sm" style="font-family:var(--font-h)">Mesa ${p.mesa === 99 ? 'Para Llevar' : p.mesa}</span>
      ${badgeHtml(p.estado)}
    </div>
    <ul style="list-style:none;display:flex;flex-direction:column;gap:6px;font-size:.88rem">${prods}</ul>
    <div class="divider" style="margin:14px 0"></div>
    <div class="total-row">
      <span class="total-label">Total</span>
      <span class="total-value">${fmt.currency(p.total)}</span>
    </div>
    <div class="text-xs muted" style="margin-top:8px">${fmt.date(p.creado_en)}</div>`;

  const btnCambiarMesa = document.getElementById('btn-cambiar-mesa');
  if (btnCambiarMesa) {
    btnCambiarMesa.style.display = 'inline-block';
    btnCambiarMesa.onclick = async () => {
      const resp = prompt("Ingrese el nuevo número de mesa (1-13, o 99 para Llevar):");
      if (resp === null) return;
      const nuevaMesa = parseInt(resp.trim(), 10);
      if (isNaN(nuevaMesa) || !((nuevaMesa >= 1 && nuevaMesa <= 13) || nuevaMesa === 99)) {
        toastErr("Mesa inválida. Debe ser de 1 a 13, o 99 para Llevar.");
        return;
      }
      try {
        loading(true);
        await api.pedidos.editar(id, { mesa: nuevaMesa });
        toastOk(`Mesa cambiada exitosamente a ${nuevaMesa === 99 ? 'Para Llevar' : nuevaMesa}`);
        closeModal();
        await loadMeseroData();
      } catch(e) {
        toastErr(e.message);
      } finally {
        loading(false);
      }
    };
  }

  openModal('modal-detalle');
}

/* ── Agregar productos a pedido activo ──────── */
let _pedidoAgregarId   = null;
let _carritoAgregar    = [];
let _agrCat            = 'Todas';
let _agrBusqueda       = '';

let _agregarTabActiva = 'productos';
function setAgregarTab(tab) {
  _agregarTabActiva = tab;
  
  const btnProds = document.getElementById('btn-tab-agregar-prods');
  const btnCart = document.getElementById('btn-tab-agregar-cart');
  const paneLeft = document.getElementById('agregar-left-pane');
  const paneRight = document.getElementById('agregar-right-pane');
  
  if (btnProds) btnProds.classList.toggle('active', tab === 'productos');
  if (btnCart) btnCart.classList.toggle('active', tab === 'carrito');
  
  if (paneLeft) paneLeft.classList.toggle('show-mobile', tab === 'productos');
  if (paneRight) paneRight.classList.toggle('show-mobile', tab === 'carrito');
}

function abrirAgregarProductos(pedidoId) {
  _pedidoAgregarId = pedidoId;
  _carritoAgregar  = [];
  _agrCat          = 'Todas';
  _agrBusqueda     = '';
  const p = State.pedidos.find(x => x.id === pedidoId);
  if (!p) return;

  const headerInfo = document.getElementById('agregar-pedido-info-header');
  if (headerInfo) {
    const labelC = p.comensal
      ? `<span class="badge-comensal" style="margin:0"><i class="fa-solid fa-user"></i> ${p.comensal}</span>`
      : '';
    headerInfo.innerHTML = `
      <span class="fw600" style="font-family:var(--font-h);color:var(--gold);font-size:.9rem">Mesa ${p.mesa}</span>
      ${labelC}
      <span class="muted text-xs">#${p.id}</span>
    `;
  }

  // Limpiar buscador
  const searchInput = document.getElementById('agr-search');
  if (searchInput) searchInput.value = '';

  // Inicializar tab en móvil
  setAgregarTab('productos');

  _renderAgrTabs();
  renderAgregarGrid();
  renderAgregarCarrito();
  openModal('modal-agregar');
}

function _renderAgrTabs() {
  const tabsEl = document.getElementById('agr-tabs');
  if (!tabsEl) return;
  const activos = State.productos.filter(x => x.activo !== false);
  const cats = ['Todas', ...CATEGORIAS.filter(c => activos.some(p => (p.categoria||'General') === c))];
  tabsEl.innerHTML = cats.map(c => {
    const count = c === 'Todas' ? activos.length
      : activos.filter(p => (p.categoria||'General') === c).length;
    return `<button class="cat-tab${c === _agrCat ? ' active' : ''}"
      onclick="_agrCat='${c}';this.parentNode.querySelectorAll('.cat-tab').forEach(b=>b.classList.remove('active'));this.classList.add('active');renderAgregarGrid()">
      ${c} <span class="cat-tab-count">${count}</span>
    </button>`;
  }).join('');
}

function renderAgregarGrid() {
  const grid = document.getElementById('agregar-grid');
  if (!grid) return;
  let prods = State.productos.filter(x => x.activo !== false);
  if (_agrCat !== 'Todas') prods = prods.filter(p => (p.categoria||'General') === _agrCat);
  if (_agrBusqueda.trim()) {
    const q = _agrBusqueda.trim().toLowerCase();
    prods = prods.filter(p => p.nombre.toLowerCase().includes(q));
  }
  if (!prods.length) {
    grid.innerHTML = '<p class="muted text-sm" style="padding:16px;text-align:center">Sin productos</p>';
    return;
  }
  grid.innerHTML = prods.map(prod => {
    const color = CAT_COLORS[prod.categoria] || CAT_COLORS['General'];
    const enCarrito = _carritoAgregar.find(i => i.producto_id === prod.id);
    return `
    <div class="producto-card${enCarrito ? ' agr-selected' : ''}" onclick="addToAgregar(${prod.id})" id="agcard-${prod.id}">
      <div class="prod-color-bar" style="background:${color}"></div>
      <div class="prod-body">
        <span class="prod-cat">${prod.categoria||'General'}</span>
        <span class="prod-nom">${prod.nombre}</span>
        <span class="prod-precio">${fmt.currency(prod.precio)}</span>
      </div>
      ${enCarrito ? `<div class="prod-add-btn" style="background:var(--accent);color:#fff">${enCarrito.cantidad}</div>` : '<div class="prod-add-btn"><i class="fa-solid fa-plus"></i></div>'}
    </div>`;
  }).join('');
}

function addToAgregar(productoId) {
  const prod = State.productos.find(p => p.id === productoId);
  if (!prod) return;
  const existing = _carritoAgregar.find(i => i.producto_id === productoId);
  if (existing) { existing.cantidad++; }
  else { _carritoAgregar.push({ producto_id: productoId, nombre: prod.nombre, precio: parseFloat(prod.precio), cantidad: 1, nota: '', esLlevar: false }); }
  renderAgregarGrid();
  renderAgregarCarrito();
}

function changeQtyAgregar(productoId, delta) {
  const item = _carritoAgregar.find(i => i.producto_id === productoId);
  if (!item) return;
  item.cantidad += delta;
  if (item.cantidad <= 0) _carritoAgregar = _carritoAgregar.filter(i => i.producto_id !== productoId);
  renderAgregarGrid();
  renderAgregarCarrito();
}

function setNotaAgregar(productoId, nota) {
  const item = _carritoAgregar.find(i => i.producto_id === productoId);
  if (item) item.nota = nota;
}

function toggleAgregarItemLlevar(productoId) {
  const item = _carritoAgregar.find(i => i.producto_id === productoId);
  if (item) item.esLlevar = !item.esLlevar;
  renderAgregarCarrito();
}

function renderAgregarCarrito() {
  const el = document.getElementById('agregar-carrito');
  if (!el) return;

  // Actualizar contador de la pestaña móvil
  const badge = document.getElementById('agregar-badge-count');
  const totalItems = _carritoAgregar.reduce((sum, item) => sum + item.cantidad, 0);
  if (badge) {
    if (totalItems > 0) {
      badge.textContent = totalItems;
      badge.style.display = 'inline-flex';
    } else {
      badge.style.display = 'none';
    }
  }

  // Actualizar total en el footer
  const total = _carritoAgregar.reduce((s, i) => s + i.precio * i.cantidad, 0);
  const totalMontoEl = document.getElementById('agregar-total-monto');
  if (totalMontoEl) {
    totalMontoEl.textContent = fmt.currency(total);
  }

  if (!_carritoAgregar.length) {
    el.innerHTML = '<p class="muted text-sm" style="text-align:center;padding:24px 0">Selecciona productos del menú</p>';
    return;
  }

  el.innerHTML = `
    <div class="agr-carrito-wrap">
      <div class="agr-carrito-items-list">
        ${_carritoAgregar.map(item => `
          <div class="agr-carrito-item">
            <div style="flex:1;min-width:0">
              <div class="fw600" style="font-size:.85rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${item.nombre}</div>
              <input class="nota-input" placeholder="Indicaciones..."
                value="${item.nota || ''}"
                oninput="setNotaAgregar(${item.producto_id}, this.value)"
                style="margin-top:4px">
            </div>
            <div style="display:flex;align-items:center;gap:6px;flex-shrink:0">
              <button class="qty-btn" onclick="changeQtyAgregar(${item.producto_id},-1)">−</button>
              <span style="min-width:22px;text-align:center;font-weight:700">${item.cantidad}</span>
              <button class="qty-btn" onclick="changeQtyAgregar(${item.producto_id},1)">+</button>
              <button type="button" class="qty-btn ${item.esLlevar ? 'active' : ''}" style="margin-left:8px; background:${item.esLlevar ? 'var(--accent)' : 'none'}; border:1px solid var(--border); color:${item.esLlevar ? '#000' : 'var(--muted)'}" onclick="toggleAgregarItemLlevar(${item.producto_id})" title="Llevar"><i class="fa-solid fa-bag-shopping"></i></button>
              <span class="text-gold" style="font-size:.82rem;min-width:54px;text-align:right">${fmt.currency(item.precio * item.cantidad)}</span>
            </div>
          </div>`).join('')}
      </div>
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
        nota:        i.esLlevar ? '[LLEVAR] ' + (i.nota || '').trim() : (i.nota || ''),
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

