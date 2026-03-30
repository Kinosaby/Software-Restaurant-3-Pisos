/**
 * mesero.js — Panel del mesero: catálogo + carrito + pedidos
 */

/* ── Carga de datos ─────────────────────────── */
async function loadMeseroData() {
  loading(true);
  try {
    const [prods, peds] = await Promise.all([
      api.productos.listar(),
      api.pedidos.listar(),
    ]);
    State.productos = prods.productos || [];
    State.pedidos   = peds.pedidos   || [];
    renderCatalogo();
    renderMeseroPedidos();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

/* ── Catálogo de productos ──────────────────── */
function renderCatalogo() {
  const grid = document.getElementById('catalogo-grid');
  if (!grid) return;
  const activos = State.productos.filter(p => p.disponible !== false);
  if (!activos.length) { grid.innerHTML = '<p class="muted text-sm">Sin productos disponibles.</p>'; return; }
  grid.innerHTML = activos.map(p => `
    <div class="producto-card" onclick="addToCarrito(${p.id})" id="pcard-${p.id}">
      <span class="prod-cat">${p.categoria || 'General'}</span>
      <span class="prod-nom">${p.nombre}</span>
      <span class="prod-precio">${fmt.currency(p.precio)}</span>
    </div>`).join('');
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
  list.innerHTML = activos.map(p => `
    <div class="pedido-row" onclick="verDetallePedido(${p.id})">
      <div class="pedido-row-info">
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px">
          <span class="fw600">Mesa ${p.mesa}</span>
          ${badgeHtml(p.estado)}
        </div>
        <div class="text-xs muted">#${p.id} · ${fmt.relTime(p.creado_en)}</div>
      </div>
      <div class="text-gold fw600" style="display:flex;gap:8px;align-items:center;">
        ${p.estado === 'listo' ? `<button class="btn btn-primary btn-sm" onclick="event.stopPropagation();cobrarPedido(${p.id})"><i class="fa-solid fa-credit-card"></i> Cobrar</button>` : ''}
        ${fmt.currency(p.total)}
      </div>
      <button class="btn btn-danger btn-sm" style="margin-left:auto" onclick="event.stopPropagation();cancelarPedido(${p.id})"><i class="fa-solid fa-xmark"></i></button>
    </div>`).join('');
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
    <div class="text-xs muted" style="margin-top:8px">${fmt.date(p.created_at)}</div>`;
  openModal('modal-detalle');
}
