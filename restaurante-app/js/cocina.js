/**
 * cocina.js — Panel de cocina: FIFO + checkboxes por item + ver detalle
 */

// Estado local de checkboxes: { pedidoId: Set<productoDetalleIndex> }
const _itemsListos = {};

async function loadCocinaData() {
  loading(true);
  try {
    const res = await api.pedidos.listar();
    State.pedidos = res.pedidos || [];
    renderCocina();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

function toggleItemListo(pedidoId, idx, total) {
  if (!_itemsListos[pedidoId]) _itemsListos[pedidoId] = new Set();
  const s = _itemsListos[pedidoId];
  if (s.has(idx)) s.delete(idx); else s.add(idx);

  // Actualizar visualmente sin re-renderizar toda la lista
  const cb  = document.getElementById(`cb-${pedidoId}-${idx}`);
  const row = document.getElementById(`item-row-${pedidoId}-${idx}`);
  const cnt = document.getElementById(`items-count-${pedidoId}`);
  const btnListo = document.getElementById(`btn-listo-${pedidoId}`);

  if (cb)  cb.checked = s.has(idx);
  if (row) row.classList.toggle('item-done', s.has(idx));
  if (cnt) cnt.textContent = `${s.size}/${total} listos`;

  // Si todos están marcados → resaltar botón Listo
  if (btnListo) {
    const todosListos = s.size >= total;
    btnListo.classList.toggle('btn-success', todosListos);
    btnListo.classList.toggle('btn-outline',  !todosListos);
    if (todosListos) btnListo.innerHTML = '<i class="fa-solid fa-check-double"></i> Todo Listo';
  }
}

function verDetalleCocina(pedidoId) {
  const p = State.pedidos.find(x => x.id === pedidoId);
  if (!p) return;

  const prods = (p.productos || []).map(i => `
    <div class="detalle-cocina-item">
      <div class="detalle-cocina-qty">${i.cantidad}×</div>
      <div style="flex:1">
        <div class="detalle-cocina-nom">${i.nombre}</div>
        ${i.nota ? `<div class="detalle-cocina-nota"><i class="fa-solid fa-note-sticky"></i> ${i.nota}</div>` : ''}
      </div>
      <div class="detalle-cocina-precio">${fmt.currency(parseFloat(i.precio) * i.cantidad)}</div>
    </div>`).join('');

  const horaExacta = new Date(p.creado_en).toLocaleTimeString('es-MX', { hour: '2-digit', minute: '2-digit' });

  document.getElementById('detalle-cocina-content').innerHTML = `
    <div style="display:flex;align-items:center;gap:10px;margin-bottom:14px;flex-wrap:wrap">
      <div class="cocina-mesa" style="font-size:1.4rem">Mesa ${p.mesa}</div>
      ${badgeHtml(p.estado)}
      <span class="muted text-xs">Pedido #${p.id}</span>
    </div>
    <div class="detalle-cocina-time">
      <i class="fa-solid fa-clock"></i> Recibido a las ${horaExacta} · ${fmt.relTime(p.creado_en)}
    </div>
    <div class="divider" style="margin:12px 0"></div>
    <div style="display:flex;flex-direction:column;gap:8px">${prods}</div>
    <div class="divider" style="margin:12px 0"></div>
    <div class="total-row">
      <span class="total-label" style="font-size:1rem">Total del pedido</span>
      <span class="total-value" style="font-size:1.2rem">${fmt.currency(p.total)}</span>
    </div>`;

  openModal('modal-detalle-cocina');
}

function renderCocina() {
  const grid = document.getElementById('cocina-grid');
  if (!grid) return;

  const activos = State.pedidos.filter(p => p.estado === 'pendiente' || p.estado === 'preparando');

  if (!activos.length) {
    grid.innerHTML = `
      <div style="grid-column:1/-1;display:flex;flex-direction:column;align-items:center;gap:16px;padding:60px;color:var(--muted)">
        <i class="fa-solid fa-utensils" style="font-size:3rem;color:var(--muted)"></i>
        <p style="font-size:1.1rem">Sin pedidos pendientes en cocina</p>
      </div>`;
    return;
  }

  grid.innerHTML = activos.map((p, idx) => {
    const turno     = idx + 1;
    const isPrimero = turno === 1;
    const isPendiente = p.estado === 'pendiente';
    const nextEstado  = isPendiente ? 'preparando' : 'listo';
    const btnClass    = isPendiente ? 'btn-outline' : 'btn-outline';
    const mins        = Math.floor((Date.now() - new Date(p.creado_en).getTime()) / 60000);
    const urgente     = mins >= 15 && p.estado === 'pendiente';

    const marcados  = _itemsListos[p.id]?.size || 0;
    const totalItems = (p.productos || []).length;

    // Items con checkboxes
    const prods = (p.productos || []).map((i, iIdx) => {
      const done = _itemsListos[p.id]?.has(iIdx) || false;
      return `
        <div class="pedido-item${done ? ' item-done' : ''}" id="item-row-${p.id}-${iIdx}">
          <input type="checkbox" class="item-cb" id="cb-${p.id}-${iIdx}"
            ${done ? 'checked' : ''}
            onclick="toggleItemListo(${p.id}, ${iIdx}, ${totalItems})">
          <span class="pedido-item-qty">${i.cantidad}×</span>
          <div style="flex:1">
            <span class="pedido-item-nom">${i.nombre}</span>
            ${i.nota ? `<div class="pedido-item-nota"><i class="fa-solid fa-note-sticky"></i> ${i.nota}</div>` : ''}
          </div>
        </div>`;
    }).join('');

    const todosListos = marcados >= totalItems && totalItems > 0;

    return `
      <div class="pedido-card${urgente ? ' urgente' : ''}">
        <div class="pedido-header">
          <div>
            <div class="cocina-turno${isPrimero ? ' turno-primero' : ''}">#${turno} en cola</div>
            <div class="cocina-mesa">Mesa ${p.mesa}</div>
            <div class="cocina-pedido-id">#${p.id}</div>
          </div>
          <div style="display:flex;flex-direction:column;align-items:flex-end;gap:6px">
            ${badgeHtml(p.estado)}
            <div class="pedido-time">
              <span class="dot-live"></span>
              ${fmt.relTime(p.creado_en)}
              ${urgente ? '<span class="text-danger" style="margin-left:6px"><i class="fa-solid fa-triangle-exclamation"></i></span>' : ''}
            </div>
            <button class="btn btn-ghost btn-sm" style="font-size:.75rem;padding:3px 8px"
              onclick="verDetalleCocina(${p.id})">
              <i class="fa-solid fa-eye"></i> Ver
            </button>
          </div>
        </div>
        <div class="pedido-body cocina-body">${prods}</div>
        <div class="items-counter" id="items-count-${p.id}">${marcados}/${totalItems} listos</div>
        <div class="pedido-footer">
          ${p.estado === 'preparando'
            ? `<button class="btn ${todosListos ? 'btn-success' : 'btn-outline'} cocina-btn" style="flex:1"
                id="btn-listo-${p.id}" onclick="avanzarEstado(${p.id},'listo')">
                <i class="fa-solid fa-${todosListos ? 'check-double' : 'check'}"></i>
                ${todosListos ? 'Todo Listo' : 'Listo'}
              </button>`
            : `<button class="btn btn-outline cocina-btn" style="flex:1"
                onclick="avanzarEstado(${p.id},'preparando')">
                <i class="fa-solid fa-fire"></i> Preparar
              </button>`
          }
          ${p.estado === 'pendiente' ? `<button class="btn btn-danger cocina-btn" onclick="cocina_cancelar(${p.id})"><i class="fa-solid fa-xmark"></i></button>` : ''}
        </div>
      </div>`;
  }).join('');

  const el = document.getElementById('cocina-count');
  if (el) el.textContent = activos.length;
}

async function avanzarEstado(id, estado) {
  try {
    await api.pedidos.cambiarEstado(id, estado);
    // Limpiar checkboxes de ese pedido al marcar listo
    if (estado === 'listo') delete _itemsListos[id];
    const res = await api.pedidos.listar();
    State.pedidos = res.pedidos || [];
    renderCocina();
  } catch(e) { toastErr(e.message); }
}

async function cocina_cancelar(id) {
  if (!confirm(`¿Cancelar pedido #${id}?`)) return;
  try {
    await api.pedidos.cancelar(id);
    toastOk(`Pedido #${id} cancelado`);
    delete _itemsListos[id];
    const res = await api.pedidos.listar();
    State.pedidos = res.pedidos || [];
    renderCocina();
  } catch(e) { toastErr(e.message); }
}
