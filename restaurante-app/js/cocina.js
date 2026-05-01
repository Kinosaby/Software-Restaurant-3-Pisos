/**
 * cocina.js — Panel de cocina: pedidos en tiempo real con cola FIFO
 */

const CATS_ORDER = [
  'Tortas','Guajolotes','Quesadillas','Enchiladas','Pambazos',
  'Tostadas','Volcanes','Asada Fries','Tacos','Burritos',
  'Bebidas','Gringas','Postres','General'
];

async function loadCocinaData() {
  loading(true);
  try {
    const res = await api.pedidos.listar();
    State.pedidos = res.pedidos || [];
    renderCocina();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

function renderCocina() {
  const grid = document.getElementById('cocina-grid');
  if (!grid) return;

  // Solo pendiente y preparando, ya vienen ordenados FIFO del backend
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
    const prods = (p.productos||[]).map(i => `
      <div class="pedido-item">
        <span class="pedido-item-qty">${i.cantidad}×</span>
        <span class="pedido-item-nom">${i.nombre}</span>
        ${i.nota ? `<span class="pedido-item-nota">(${i.nota})</span>` : ''}
      </div>`).join('');

    const isPendiente = p.estado === 'pendiente';
    const nextEstado  = isPendiente ? 'preparando' : 'listo';
    const nextLabel   = isPendiente
      ? '<i class="fa-solid fa-fire"></i> Preparar'
      : '<i class="fa-solid fa-check"></i> Listo';
    const btnClass    = isPendiente ? 'btn-outline' : 'btn-success';
    const mins        = Math.floor((Date.now() - new Date(p.creado_en).getTime()) / 60000);
    const urgente     = mins >= 15 && p.estado === 'pendiente';

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
              ${urgente ? '<span class="text-danger" style="margin-left:6px" title="Pedido retrasado"><i class="fa-solid fa-triangle-exclamation"></i></span>' : ''}
            </div>
          </div>
        </div>
        <div class="pedido-body cocina-body">${prods}</div>
        <div class="pedido-footer">
          <button class="btn ${btnClass} cocina-btn" style="flex:1" onclick="avanzarEstado(${p.id},'${nextEstado}')">
            ${nextLabel}
          </button>
          ${p.estado === 'pendiente' ? `<button class="btn btn-danger cocina-btn" onclick="cocina_cancelar(${p.id})"><i class="fa-solid fa-xmark"></i></button>` : ''}
        </div>
      </div>`;
  }).join('');

  // Contador
  const el = document.getElementById('cocina-count');
  if (el) el.textContent = activos.length;
}

async function avanzarEstado(id, estado) {
  try {
    await api.pedidos.cambiarEstado(id, estado);
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
    const res = await api.pedidos.listar();
    State.pedidos = res.pedidos || [];
    renderCocina();
  } catch(e) { toastErr(e.message); }
}
