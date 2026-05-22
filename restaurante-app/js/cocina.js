/**
 * cocina.js — Panel de cocina: FIFO + checkboxes por item + ver detalle
 */

// Estado local de checkboxes: { pedidoId: Set<productoDetalleIndex> }
const _itemsListos = {};

/* ── Persistencia de extras en localStorage ────────────────── */
function _saveExtras() {
  try {
    localStorage.setItem('cocina_extras', JSON.stringify(State.extras || []));
  } catch(e) { /* localStorage lleno o privado */ }
}

function _loadExtras() {
  try {
    const raw = localStorage.getItem('cocina_extras');
    return raw ? JSON.parse(raw) : [];
  } catch(e) { return []; }
}

async function loadCocinaData() {
  loading(true);
  try {
    const res = await api.pedidos.listar();
    State.pedidos = res.pedidos || [];
    // Restaurar extras desde localStorage si no hay nada en memoria
    if (!State.extras || State.extras.length === 0) {
      State.extras = _loadExtras();
    }
    renderCocina();
    renderCocinaExtras();
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

  const enCola    = State.pedidos.filter(p => p.estado === 'pendiente' || p.estado === 'preparando');
  const paraCobrar = State.pedidos.filter(p => p.estado === 'listo');

  if (!enCola.length && !paraCobrar.length) {
    grid.innerHTML = `
      <div style="grid-column:1/-1;display:flex;flex-direction:column;align-items:center;gap:16px;padding:60px;color:var(--muted)">
        <i class="fa-solid fa-utensils" style="font-size:3rem;color:var(--muted)"></i>
        <p style="font-size:1.1rem">Sin pedidos pendientes en cocina</p>
      </div>`;
    return;
  }

  /* ── Agrupar cola por mesa ─────────────────────────── */
  // Cada "grupo" es una tarjeta que puede tener 1..N comensales
  const grupos = {};
  enCola.forEach(p => {
    if (!grupos[p.mesa]) grupos[p.mesa] = [];
    grupos[p.mesa].push(p);
  });

  // Turno global (por orden de llegada del primer pedido de cada mesa)
  const mesasOrdenadas = Object.keys(grupos).sort((a, b) => {
    const tA = Math.min(...grupos[a].map(p => new Date(p.creado_en).getTime()));
    const tB = Math.min(...grupos[b].map(p => new Date(p.creado_en).getTime()));
    return tA - tB;
  });

  const colaHtml = mesasOrdenadas.map((mesa, turnoIdx) => {
    const pedidos   = grupos[mesa];
    const turno     = turnoIdx + 1;
    const isPrimero = turno === 1;

    // La mesa es urgente si algún pedido tiene +15 min pendiente
    const urgente = pedidos.some(p => {
      const mins = Math.floor((Date.now() - new Date(p.creado_en).getTime()) / 60000);
      return mins >= 15 && p.estado === 'pendiente';
    });

    // ¿Todos los pedidos de esta mesa están en preparando?
    const todoPreparando = pedidos.every(p => p.estado === 'preparando');
    const algunoPendiente = pedidos.some(p => p.estado === 'pendiente');

    // Sección de cada comensal dentro de la tarjeta
    const comensalesHtml = pedidos.map((p, ci) => {
      const totalItemsP = (p.productos || []).length;
      const marcadosP   = _itemsListos[p.id]?.size || 0;
      const todoListoP  = marcadosP >= totalItemsP && totalItemsP > 0;

      const labelComensal = p.comensal
        ? `<span class="badge-comensal" style="font-size:.75rem"><i class="fa-solid fa-user"></i> ${p.comensal}</span>`
        : `<span class="muted text-xs">#${p.id}</span>`;

      const prodsHtml = (p.productos || []).map((i, iIdx) => {
        const done = _itemsListos[p.id]?.has(iIdx) || false;
        return `
          <div class="pedido-item${done ? ' item-done' : ''}" id="item-row-${p.id}-${iIdx}">
            <input type="checkbox" class="item-cb" id="cb-${p.id}-${iIdx}"
              ${done ? 'checked' : ''}
              onclick="toggleItemListo(${p.id}, ${iIdx}, ${totalItemsP})">
            <span class="pedido-item-qty">${i.cantidad}×</span>
            <div style="flex:1">
              <span class="pedido-item-nom">${i.nombre}</span>
              ${i.nota ? `<div class="pedido-item-nota"><i class="fa-solid fa-note-sticky"></i> ${i.nota}</div>` : ''}
            </div>
          </div>`;
      }).join('');

      // Separador entre comensales (no antes del primero)
      const separador = ci > 0
        ? `<div class="cocina-comensal-sep"></div>`
        : '';

      return `${separador}
        <div class="cocina-comensal-bloque">
          <div class="cocina-comensal-label">
            ${labelComensal}
            <span class="items-counter-inline" id="items-count-${p.id}">${marcadosP}/${totalItemsP} listos</span>
          </div>
          <div class="pedido-body cocina-body" style="padding:0 0 4px">${prodsHtml}</div>
        </div>`;
    }).join('');

    // Botones de acción unificados por mesa
    // Si hay alguno pendiente → Preparar todos
    // Si todos están preparando → Listo todos
    const totalItemsMesa  = pedidos.reduce((s, p) => s + (p.productos || []).length, 0);
    const marcadosMesa    = pedidos.reduce((s, p) => s + (_itemsListos[p.id]?.size || 0), 0);
    const todosMarcados   = marcadosMesa >= totalItemsMesa && totalItemsMesa > 0;

    const botonesHtml = algunoPendiente
      ? `<button class="btn btn-outline cocina-btn" style="flex:1"
            onclick="avanzarTodosMesa(${mesa},'preparando')">
            <i class="fa-solid fa-fire"></i> Preparar todos
          </button>
          <button class="btn btn-danger cocina-btn" onclick="cocina_cancelar(${pedidos[0].id})">
            <i class="fa-solid fa-xmark"></i>
          </button>`
      : `<button class="btn ${todosMarcados ? 'btn-success' : 'btn-outline'} cocina-btn" style="flex:1"
            onclick="avanzarTodosMesa(${mesa},'listo')">
            <i class="fa-solid fa-${todosMarcados ? 'check-double' : 'check'}"></i>
            ${todosMarcados ? 'Todo Listo' : 'Marcar Listos'}
          </button>`;

    const mins0 = Math.floor((Date.now() - new Date(pedidos[0].creado_en).getTime()) / 60000);

    return `
      <div class="pedido-card${urgente ? ' urgente' : ''}">
        <div class="pedido-header">
          <div>
            <div class="cocina-turno${isPrimero ? ' turno-primero' : ''}">#${turno} en cola</div>
            <div class="cocina-mesa">Mesa ${mesa}</div>
            ${pedidos.length > 1 ? `<div class="cocina-pedido-id" style="color:var(--blue)">${pedidos.length} comensales</div>` : `<div class="cocina-pedido-id">#${pedidos[0].id}</div>`}
          </div>
          <div style="display:flex;flex-direction:column;align-items:flex-end;gap:5px">
            ${badgeHtml(pedidos[0].estado)}
            <div class="pedido-time">
              <span class="dot-live"></span>
              ${fmt.relTime(pedidos[0].creado_en)}
              ${urgente ? '<span class="text-danger" style="margin-left:6px"><i class="fa-solid fa-triangle-exclamation"></i></span>' : ''}
            </div>
          </div>
        </div>
        <div class="pedido-body cocina-body" style="flex-direction:column;gap:0;padding:0">
          ${comensalesHtml}
        </div>
        <div class="items-counter" id="items-count-mesa-${mesa}">${marcadosMesa}/${totalItemsMesa} listos en total</div>
        <div class="pedido-footer">${botonesHtml}</div>
      </div>`;
  }).join('');

  /* ── Pedidos listos para cobrar (también agrupados por mesa) ─ */
  const mesasListas = {};
  paraCobrar.forEach(p => {
    if (!mesasListas[p.mesa]) mesasListas[p.mesa] = [];
    mesasListas[p.mesa].push(p);
  });

  const cobrarHtml = Object.keys(mesasListas).map(mesa => {
    const pedidos = mesasListas[mesa];
    const totalMesa = pedidos.reduce((s, p) => s + parseFloat(p.total || 0), 0);

    const comensalesHtml = pedidos.map((p, ci) => {
      const labelComensal = p.comensal
        ? `<span class="badge-comensal" style="font-size:.75rem"><i class="fa-solid fa-user"></i> ${p.comensal}</span>`
        : `<span class="muted text-xs">#${p.id}</span>`;

      const prodsHtml = (p.productos || []).map(i => `
        <div class="pedido-item item-done">
          <span class="pedido-item-qty">${i.cantidad}×</span>
          <div style="flex:1">
            <span class="pedido-item-nom">${i.nombre}</span>
            ${i.nota ? `<div class="pedido-item-nota"><i class="fa-solid fa-note-sticky"></i> ${i.nota}</div>` : ''}
          </div>
          <span style="font-size:.82rem;color:var(--gold)">${fmt.currency(parseFloat(i.precio)*i.cantidad)}</span>
        </div>`).join('');

      const separador = ci > 0 ? `<div class="cocina-comensal-sep"></div>` : '';
      return `${separador}
        <div class="cocina-comensal-bloque">
          <div class="cocina-comensal-label">
            ${labelComensal}
            <span style="font-size:.78rem;color:var(--gold)">${fmt.currency(p.total)}</span>
          </div>
          <div class="pedido-body cocina-body" style="padding:0 0 4px">${prodsHtml}</div>
        </div>`;
    }).join('');

    return `
      <div class="pedido-card cobrar-card">
        <div class="pedido-header">
          <div>
            <div class="cocina-turno" style="color:#22c55e;font-size:.85rem">LISTO PARA COBRAR</div>
            <div class="cocina-mesa">Mesa ${mesa}</div>
            ${pedidos.length > 1 ? `<div class="cocina-pedido-id" style="color:var(--blue)">${pedidos.length} cuentas</div>` : ''}
          </div>
          <div style="display:flex;flex-direction:column;align-items:flex-end;gap:5px">
            ${badgeHtml('listo')}
          </div>
        </div>
        <div class="pedido-body cocina-body" style="flex-direction:column;gap:0;padding:0">
          ${comensalesHtml}
        </div>
        <div class="cobrar-total-row">
          <span>Total mesa</span>
          <span class="cobrar-total-val">${fmt.currency(totalMesa)}</span>
        </div>
      </div>`;
  }).join('');

  grid.innerHTML = colaHtml + cobrarHtml;

  const el = document.getElementById('cocina-count');
  if (el) el.textContent = enCola.length;
}

/** Avanza todos los pedidos de una mesa al mismo estado */
async function avanzarTodosMesa(mesa, estado) {
  const pedidos = State.pedidos.filter(p =>
    p.mesa === Number(mesa) && (p.estado === 'pendiente' || p.estado === 'preparando')
  );
  if (!pedidos.length) return;
  try {
    loading(true);
    await Promise.all(pedidos.map(p => api.pedidos.cambiarEstado(p.id, estado)));
    await loadCocinaData();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

/* ── Seción de EXTRAS (pedidos sobre pedidos completados) ──── */
function renderCocinaExtras() {
  const container = document.getElementById('cocina-extras');
  if (!container) return;

  const extras = State.extras || [];
  if (!extras.length) {
    container.style.display = 'none';
    container.innerHTML = '';
    return;
  }

  container.style.display = 'block';
  container.innerHTML = `
    <div class="extras-header">
      <i class="fa-solid fa-bolt"></i>
      Extras (piden más) — <span class="text-accent">${extras.length}</span>
    </div>
    <div class="extras-grid">
      ${extras.map(ex => {
        const prods = ex.items.map((i, idx) => `
          <div class="pedido-item${ex._done?.[idx] ? ' item-done' : ''}" id="xitem-${ex._id}-${idx}">
            <input type="checkbox" class="item-cb" id="xcb-${ex._id}-${idx}"
              ${ex._done?.[idx] ? 'checked' : ''}
              onclick="toggleExtraItem(${ex._id}, ${idx}, ${ex.items.length})">
            <span class="pedido-item-qty">${i.cantidad}×</span>
            <div style="flex:1">
              <span class="pedido-item-nom">${i.nombre}</span>
              ${i.nota ? `<div class="pedido-item-nota"><i class="fa-solid fa-note-sticky"></i> ${i.nota}</div>` : ''}
            </div>
          </div>`).join('');

        const doneCnt  = Object.values(ex._done || {}).filter(Boolean).length;
        const allDone  = doneCnt >= ex.items.length;

        const tipoBadge = ex.tipo === 'llevar'
          ? `<span class="badge badge-llevar" style="font-size:.78rem"><i class="fa-solid fa-bag-shopping"></i> LLEVAR</span>`
          : '';

        return `
          <div class="extra-card">
            <div class="extra-card-header">
              <div>
                <div class="extra-label"><i class="fa-solid fa-bolt"></i> EXTRA</div>
                <div class="cocina-mesa" style="font-size:1.4rem">Mesa ${ex.mesa}</div>
                <div class="cocina-pedido-id">Pedido #${ex.pedido_id}</div>
              </div>
              <div style="display:flex;flex-direction:column;align-items:flex-end;gap:4px">
                ${tipoBadge}
                <div class="extra-time"><span class="dot-live"></span> Ahora</div>
              </div>
            </div>
            <div class="pedido-body cocina-body">${prods}</div>
            <div class="items-counter" id="xcount-${ex._id}">${doneCnt}/${ex.items.length} listos</div>
            <div class="pedido-footer">
              <button class="btn ${allDone ? 'btn-success' : 'btn-outline'} cocina-btn" style="flex:1"
                id="xbtn-${ex._id}" onclick="terminarExtra(${ex._id})">
                <i class="fa-solid fa-${allDone ? 'check-double' : 'check'}"></i>
                ${allDone ? 'Extra Listo' : 'Listo'}
              </button>
            </div>
          </div>`;
      }).join('')}
    </div>`;
}

function toggleExtraItem(extraId, idx, total) {
  const ex = (State.extras || []).find(e => e._id === extraId);
  if (!ex) return;
  if (!ex._done) ex._done = {};
  ex._done[idx] = !ex._done[idx];

  const cb  = document.getElementById(`xcb-${extraId}-${idx}`);
  const row = document.getElementById(`xitem-${extraId}-${idx}`);
  const cnt = document.getElementById(`xcount-${extraId}`);
  const btn = document.getElementById(`xbtn-${extraId}`);

  if (cb)  cb.checked = ex._done[idx];
  if (row) row.classList.toggle('item-done', ex._done[idx]);

  const doneCnt = Object.values(ex._done).filter(Boolean).length;
  const allDone = doneCnt >= total;
  if (cnt) cnt.textContent = `${doneCnt}/${total} listos`;
  if (btn) {
    btn.className = `btn ${allDone ? 'btn-success' : 'btn-outline'} cocina-btn`;
    btn.innerHTML = `<i class="fa-solid fa-${allDone ? 'check-double' : 'check'}"></i> ${allDone ? 'Extra Listo' : 'Listo'}`;
  }
  _saveExtras();   // Persistir estado de checkboxes
}

function terminarExtra(extraId) {
  State.extras = (State.extras || []).filter(e => e._id !== extraId);
  _saveExtras();   // Persistir el cambio
  toastOk('Extra marcado como listo');
  renderCocinaExtras();
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
