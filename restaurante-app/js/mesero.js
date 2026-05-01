/**
 * mesero.js — Panel del mesero: catálogo por secciones + carrito + pedidos + agregar a pedido
 */

const CATEGORIAS = [
  'Tortas','Guajolotes','Pambazos','Quesadillas','Enchiladas',
  'Tostadas','Volcanes','Tacos','Asada Fries','Burritos',
  'Gringas','Bebidas','Postres','General'
];

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

/* ── Carrito ────────────────────────────────── */
function addToCarrito(productoId) {
  const prod = State.productos.find(p => p.id === productoId);
  if (!prod) return;
  const existing = State.carrito.find(i => i.producto_id === productoId);
  if (existing) { existing.cantidad++; }
  else { State.carrito.push({ producto_id: productoId, nombre: prod.nombre, precio: parseFloat(prod.precio), cantidad: 1, nota: '' }); }
  renderCarrito();
}

function changeQty(productoId, delta) {
  const item = State.carrito.find(i => i.producto_id === productoId);
  if (!item) return;
  item.cantidad += delta;
  if (item.cantidad <= 0) State.carrito = State.carrito.filter(i => i.producto_id !== productoId);
  renderCarrito();
}

function setNota(productoId, nota) {
  const item = State.carrito.find(i => i.producto_id === productoId);
  if (item) item.nota = nota;
}

function clearCarrito() {
  State.carrito = [];
  renderCarrito();
}

function renderCarrito() {
  const body   = document.getElementById('carrito-body');
  const totEl  = document.getElementById('carrito-total');
  const cntEl  = document.getElementById('carrito-count');
  if (!body) return;

  if (!State.carrito.length) {
    body.innerHTML = '<p class="muted text-sm" style="text-align:center;padding:24px 0">El carrito está vacío</p>';
    if (totEl) totEl.textContent = '$0.00';
    if (cntEl) cntEl.textContent = '0';
    return;
  }

  let total = 0;
  body.innerHTML = State.carrito.map(item => {
    const subtotal = item.precio * item.cantidad;
    total += subtotal;
    return `
      <div class="carrito-item">
        <div style="flex:1">
          <div style="font-size:.84rem;font-weight:600">${item.nombre}</div>
          <div style="font-size:.73rem;color:var(--muted)">${fmt.currency(item.precio)} c/u</div>
          <input class="nota-input" placeholder="Nota..." value="${item.nota||''}"
            onchange="setNota(${item.producto_id}, this.value)" style="margin-top:5px">
        </div>
        <div class="carrito-qty">
          <button class="qty-btn" onclick="changeQty(${item.producto_id},-1)">−</button>
          <span style="min-width:22px;text-align:center;font-weight:600">${item.cantidad}</span>
          <button class="qty-btn" onclick="changeQty(${item.producto_id},1)">+</button>
        </div>
      </div>`;
  }).join('');

  if (totEl) totEl.textContent = fmt.currency(total);
  if (cntEl) cntEl.textContent = State.carrito.reduce((a,i)=>a+i.cantidad, 0);
}

/* ── Enviar pedido ──────────────────────────── */
async function submitPedido() {
  if (!State.carrito.length) { toastErr('El carrito está vacío'); return; }
  const mesa = parseInt(document.getElementById('mesa-num').value, 10);
  if (!mesa || mesa < 1) { toastErr('Ingresa un número de mesa válido'); return; }

  const body = {
    mesa,
    productos: State.carrito.map(i => ({
      producto_id: i.producto_id,
      cantidad:    i.cantidad,
      nota:        i.nota || '',
    })),
  };

  const btn = document.getElementById('btn-enviar-pedido');
  btn.disabled = true;
  try {
    loading(true);
    await api.pedidos.crear(body);
    toastOk(`Pedido enviado — Mesa ${mesa}`);
    clearCarrito();
    document.getElementById('mesa-num').value = '';
    await loadMeseroData();
  } catch(e) { toastErr(e.message); }
  finally { btn.disabled = false; loading(false); }
}

/* ── Lista de pedidos del mesero ────────────── */
function renderMeseroPedidos() {
  const list = document.getElementById('mesero-pedidos-list');
  if (!list) return;
  const activos = State.pedidos.filter(p => p.estado !== 'pagado' && p.estado !== 'cancelado');
  if (!activos.length) { list.innerHTML = '<p class="muted text-sm" style="padding:16px">Sin pedidos activos</p>'; return; }
  list.innerHTML = activos.map(p => {
    const editable = ['pendiente','preparando'].includes(p.estado);
    return `
    <div class="pedido-row" onclick="verDetallePedido(${p.id})">
      <div class="pedido-row-info">
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px">
          <span class="fw600">Mesa ${p.mesa}</span>
          ${badgeHtml(p.estado)}
        </div>
        <div class="text-xs muted">#${p.id} · ${fmt.relTime(p.creado_en)}</div>
      </div>
      <div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;justify-content:flex-end">
        ${editable ? `<button class="btn btn-outline btn-sm" onclick="event.stopPropagation();abrirAgregarProductos(${p.id})"><i class="fa-solid fa-plus"></i> Agregar</button>` : ''}
        ${p.estado === 'listo' ? `<button class="btn btn-primary btn-sm" onclick="event.stopPropagation();cobrarPedido(${p.id})"><i class="fa-solid fa-credit-card"></i> Cobrar</button>` : ''}
        <span class="text-gold fw600">${fmt.currency(p.total)}</span>
        <button class="btn btn-danger btn-sm" onclick="event.stopPropagation();cancelarPedido(${p.id})"><i class="fa-solid fa-xmark"></i></button>
      </div>
    </div>`;
  }).join('');
}

async function cobrarPedido(id) {
  try {
    loading(true);
    await api.pedidos.cambiarEstado(id, 'pagado');
    toastOk('Pedido cobrado exitosamente');
    await loadMeseroData();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
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

function renderAgregarCarrito() {
  const el = document.getElementById('agregar-carrito');
  if (!el) return;
  if (!_carritoAgregar.length) { el.innerHTML = ''; return; }
  const total = _carritoAgregar.reduce((s,i) => s + i.precio * i.cantidad, 0);
  el.innerHTML = `
    <div class="divider" style="margin:8px 0"></div>
    <div class="fw600 text-sm" style="margin-bottom:6px">A agregar:</div>
    ${_carritoAgregar.map(item => `
      <div class="carrito-item">
        <div style="flex:1;font-size:.83rem;font-weight:600">${item.nombre}</div>
        <div class="carrito-qty">
          <button class="qty-btn" onclick="changeQtyAgregar(${item.producto_id},-1)">−</button>
          <span style="min-width:20px;text-align:center;font-weight:600">${item.cantidad}</span>
          <button class="qty-btn" onclick="changeQtyAgregar(${item.producto_id},1)">+</button>
        </div>
        <span class="text-gold" style="font-size:.83rem;margin-left:8px">${fmt.currency(item.precio * item.cantidad)}</span>
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
