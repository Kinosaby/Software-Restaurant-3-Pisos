/**
 * admin.js — Panel de administración
 */

/* ── Carga de datos ─────────────────────────────────── */
let _soloHoyAdmin   = true;   // Por defecto muestra solo pedidos de hoy
let _adminRefreshTimer = null; // Timer de auto-refresh
let _metricasDebounce  = null; // Debounce para el refresh de métricas

/** Recarga SOLO las métricas (sin recargar todo). Llamada desde socket en main.js */
async function loadAdminMetrics() {
  try {
    const m = await api.metricas.resumen();
    renderAdminStats(m);
  } catch(e) { /* silencioso, no crítico */ }
}

/**
 * Programa un refresh de métricas con debounce de 2s.
 * Se llama desde los socket handlers cuando el rol es admin.
 */
function scheduleMetricasRefresh() {
  if (getRole() !== 'admin') return;
  clearTimeout(_metricasDebounce);
  _metricasDebounce = setTimeout(loadAdminMetrics, 2000);
}

async function loadAdminData() {
  loading(true);
  try {
    const [metricas, productos, usuarios, pedidos] = await Promise.all([
      api.metricas.resumen(),
      api.productos.listar(),
      api.auth.listarUsuarios(),
      api.pedidos.listar(),
    ]);
    State.productos = productos.productos || [];
    State.usuarios  = usuarios.usuarios  || [];
    State.pedidos   = pedidos.pedidos    || [];
    renderAdminStats(metricas);
    renderAdminUsers();
    renderAdminProducts();
    renderAdminPedidos();
    // Auto-refresh de métricas cada 60s mientras el panel está abierto
    clearInterval(_adminRefreshTimer);
    _adminRefreshTimer = setInterval(loadAdminMetrics, 60_000);
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

function renderAdminStats(m) {
  const dia = m.dia || {};
  document.getElementById('stat-pedidos').textContent  = dia.total_pedidos || 0;
  document.getElementById('stat-ventas').textContent   = fmt.currency(dia.total_ventas || 0);
  document.getElementById('stat-semana').textContent   = fmt.currency(m.semana || 0);
  document.getElementById('stat-productos').textContent = State.productos.length;
  document.getElementById('stat-usuarios').textContent  = State.usuarios.length;
}

/** Devuelve true si el pedido es de hoy (en hora local del navegador) */
function _esPedidoDeHoy(p) {
  const d = new Date(p.creado_en);
  const hoy = new Date();
  return d.getFullYear() === hoy.getFullYear()
      && d.getMonth()    === hoy.getMonth()
      && d.getDate()     === hoy.getDate();
}

/* ── Usuarios ───────────────────────────────── */
function renderAdminUsers() {
  const tbody = document.querySelector('#table-users tbody');
  if (!tbody) return;
  if (!State.usuarios.length) { tbody.innerHTML = '<tr class="empty-row"><td colspan="4">Sin usuarios</td></tr>'; return; }
  tbody.innerHTML = State.usuarios.map(u => `
    <tr>
      <td data-label="ID">${u.id}</td>
      <td data-label="Usuario"><strong>${u.username}</strong></td>
      <td data-label="Rol">${chipRole(u.role)}</td>
      <td data-label="Acciones" style="display:flex;gap:6px">
        <button class="btn btn-ghost btn-sm" onclick="editUser(${u.id})"><i class="fa-solid fa-pen"></i></button>
        <button class="btn btn-danger btn-sm" onclick="deleteUser(${u.id},'${u.username}')"><i class="fa-solid fa-trash"></i></button>
      </td>
    </tr>`).join('');
}

function openNewUser()  { State.editId=null; document.getElementById('modal-user-title').textContent='Nuevo Usuario'; document.getElementById('form-user').reset(); openModal('modal-user'); }
function editUser(id) {
  const u = State.usuarios.find(x=>x.id===id);
  if (!u) return;
  State.editId = id;
  document.getElementById('modal-user-title').textContent = 'Editar Usuario';
  document.getElementById('u-id').value   = u.id;
  document.getElementById('u-name').value = u.username;
  document.getElementById('u-role').value = u.role;
  document.getElementById('u-pass').value = '';
  openModal('modal-user');
}

async function submitUser() {
  const body = {
    username: document.getElementById('u-name').value.trim(),
    role:     document.getElementById('u-role').value,
    password: document.getElementById('u-pass').value,
  };
  if (!body.username) { toastErr('El nombre es requerido'); return; }
  try {
    loading(true);
    if (State.editId) {
      await api.auth.actualizar(State.editId, body);
      toastOk('Usuario actualizado');
    } else {
      if (!body.password) { toastErr('La contraseña es requerida'); loading(false); return; }
      await api.auth.registrar(body);
      toastOk('Usuario creado');
    }
    closeModal();
    await loadAdminData();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

async function deleteUser(id, name) {
  if (!confirm(`¿Eliminar usuario "${name}"?`)) return;
  try {
    loading(true);
    await api.auth.eliminar(id);
    toastOk('Usuario eliminado');
    await loadAdminData();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

/* ── Productos ──────────────────────────────── */
function renderAdminProducts() {
  const tbody = document.querySelector('#table-products tbody');
  if (!tbody) return;
  if (!State.productos.length) { tbody.innerHTML = '<tr class="empty-row"><td colspan="6">Sin productos</td></tr>'; return; }
  tbody.innerHTML = State.productos.map(p => `
    <tr>
      <td data-label="ID">${p.id}</td>
      <td data-label="Nombre"><strong>${p.nombre}</strong></td>
      <td data-label="Precio" class="text-gold fw600">${fmt.currency(p.precio)}</td>
      <td data-label="Categoria" class="text-xs muted">${p.categoria || '—'}</td>
      <td data-label="Activo" style="text-align:center">${p.activo ? '<i class="fa-solid fa-check" style="color:var(--success)"></i>' : '<i class="fa-solid fa-xmark" style="color:var(--danger)"></i>'}</td>
      <td data-label="Acciones" style="display:flex;gap:6px">
        <button class="btn btn-ghost btn-sm" onclick="editProduct(${p.id})"><i class="fa-solid fa-pen"></i></button>
        <button class="btn btn-danger btn-sm" onclick="deleteProduct(${p.id},'${p.nombre}')"><i class="fa-solid fa-trash"></i></button>
      </td>
    </tr>`).join('');
}

function openNewProduct() { State.editId=null; document.getElementById('modal-prod-title').textContent='Nuevo Producto'; document.getElementById('form-product').reset(); openModal('modal-product'); }
function editProduct(id) {
  const p = State.productos.find(x=>x.id===id);
  if (!p) return;
  State.editId = id;
  document.getElementById('modal-prod-title').textContent='Editar Producto';
  document.getElementById('p-id').value       = p.id;
  document.getElementById('p-name').value     = p.nombre;
  document.getElementById('p-price').value    = p.precio;
  document.getElementById('p-cat').value      = p.categoria || '';
  document.getElementById('p-disp').checked   = !!p.activo;
  openModal('modal-product');
}

async function submitProduct() {
  const body = {
    nombre:    document.getElementById('p-name').value.trim(),
    precio:    parseFloat(document.getElementById('p-price').value),
    categoria: document.getElementById('p-cat').value || 'General',
    activo:    document.getElementById('p-disp').checked,
  };
  if (!body.nombre || isNaN(body.precio)) { toastErr('Nombre y precio son requeridos'); return; }
  try {
    loading(true);
    if (State.editId) {
      await api.productos.actualizar(State.editId, body);
      toastOk('Producto actualizado');
    } else {
      await api.productos.crear(body);
      toastOk('Producto creado');
    }
    closeModal();
    await loadAdminData();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

async function deleteProduct(id, name) {
  if (!confirm(`¿Eliminar producto "${name}"?`)) return;
  try {
    loading(true);
    await api.productos.eliminar(id);
    toastOk('Producto eliminado');
    await loadAdminData();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

/* ── Pedidos Admin ──────────────────────────── */
function renderAdminPedidos() {
  const tbody = document.querySelector('#table-orders tbody');
  if (!tbody) return;

  // Filtrar por hoy o mostrar todo según el toggle
  const pedidos = _soloHoyAdmin
    ? State.pedidos.filter(_esPedidoDeHoy)
    : State.pedidos;

  // Actualizar label del botón toggle
  const btnToggle = document.getElementById('btn-toggle-historial');
  if (btnToggle) {
    btnToggle.textContent = _soloHoyAdmin ? '📋 Ver historial' : '📅 Solo hoy';
  }

  if (!pedidos.length) {
    tbody.innerHTML = `<tr class="empty-row"><td colspan="6">${_soloHoyAdmin ? 'Sin pedidos hoy' : 'Sin pedidos'}</td></tr>`;
    return;
  }

  tbody.innerHTML = pedidos.map(p => `
    <tr>
      <td data-label="ID">#${p.id}</td>
      <td data-label="Mesa">Mesa ${p.mesa}</td>
      <td data-label="Estado">${badgeHtml(p.estado)}</td>
      <td data-label="Total" class="text-gold fw600">${fmt.currency(p.total)}</td>
      <td data-label="Hora">${fmt.date(p.creado_en)}</td>
      <td data-label="Acciones" style="display:flex;gap:6px">
        <button class="btn btn-danger btn-sm" onclick="adminDeletePedido(${p.id})"><i class="fa-solid fa-trash"></i></button>
      </td>
    </tr>`).join('');
}

function toggleHistorialPedidos() {
  _soloHoyAdmin = !_soloHoyAdmin;
  renderAdminPedidos();
}

async function adminDeletePedido(id) {
  if (!confirm(`¿Eliminar pedido #${id}? Esta acción no se puede deshacer.`)) return;
  try {
    loading(true);
    await api.pedidos.eliminar(id);
    toastOk(`Pedido #${id} eliminado`);
    await loadAdminData();
  } catch(e) { toastErr(e.message); }
  finally { loading(false); }
}

/* ── Ventas Semanales ──────────────────────────── */
async function showWeeklySales() {
  document.getElementById('overlay-ventas-semana').style.display = 'flex';
  const body = document.getElementById('ventas-semana-body');
  body.innerHTML = '<p>Cargando datos...</p>';
  try {
    const res = await api.metricas.ventas(7);
    const ventas = res.ventas || [];
    if (!ventas.length) {
      body.innerHTML = '<p>No hay ventas en los últimos 7 días.</p>';
      return;
    }
    
    let html = `
      <table style="width: 100%; text-align: left; border-collapse: collapse; margin-top: 10px;">
        <thead>
          <tr style="border-bottom: 1px solid var(--border);">
            <th style="padding: 10px 0;">Fecha</th>
            <th style="padding: 10px 0; text-align: center;">Pedidos</th>
            <th style="padding: 10px 0; text-align: right;">Total</th>
          </tr>
        </thead>
        <tbody>
    `;
    
    let totalAcumulado = 0;
    
    ventas.forEach(v => {
      // Usar 'T12:00:00' para evitar que la conversión de huso horario cambie el día
      const dateStrFormat = v.fecha.includes('T') ? v.fecha : v.fecha + 'T12:00:00';
      const date = new Date(dateStrFormat);
      const dateStr = date.toLocaleDateString('es-MX', { weekday: 'short', day: '2-digit', month: 'short' });
      const total = parseFloat(v.total || 0);
      totalAcumulado += total;
      html += `
        <tr style="border-bottom: 1px solid var(--border);">
          <td style="padding: 10px 0; text-transform: capitalize;">${dateStr}</td>
          <td style="padding: 10px 0; text-align: center; color: var(--text-secondary);">${v.pedidos}</td>
          <td style="padding: 10px 0; text-align: right; color: var(--success); font-weight: bold;">${fmt.currency(total)}</td>
        </tr>
      `;
    });
    
    html += `
        </tbody>
        <tfoot>
          <tr>
            <td style="padding: 15px 0; font-weight: bold; font-size: 1.1rem;">Total 7 Días</td>
            <td></td>
            <td style="padding: 15px 0; text-align: right; font-weight: bold; font-size: 1.2rem; color: var(--accent);">${fmt.currency(totalAcumulado)}</td>
          </tr>
        </tfoot>
      </table>
    `;
    
    body.innerHTML = html;
  } catch (error) {
    body.innerHTML = `<p style="color: var(--danger);">Error al cargar ventas: ${error.message}</p>`;
  }
}
