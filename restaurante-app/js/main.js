/**
 * main.js — Núcleo de la aplicación POS 3 Pisos
 * Gestión de pantallas, login, logout, socket y utilidades UI globales.
 */

/* ── Estado global ──────────────────────────── */
const State = {
  productos:  [],
  pedidos:    [],
  usuarios:   [],
  carrito:    [],
  mesaActual: 1,
  socket:     null,
  editId:     null,
};

/* ── UI Helpers ─────────────────────────────── */
function show(id)  { document.querySelectorAll('.screen').forEach(s=>s.classList.remove('active')); document.getElementById(id)?.classList.add('active'); }
function go(id)    { 
  if (id === 'screen-menu' && typeof updateMenuRoles === 'function') updateMenuRoles();
  show(id); 
}

function toast(msg, type='info', icon='') {
  const c = document.getElementById('toast-container');
  if (!c) return;
  const t = document.createElement('div');
  t.className = `toast toast-${type}`;
  t.innerHTML = `<span class="toast-icon">${icon}</span><span>${msg}</span>`;
  c.appendChild(t);
  setTimeout(() => { t.classList.add('out'); setTimeout(()=>t.remove(), 250); }, 3500);
}
const toastOk  = (m) => toast(m, 'success', '<i class="fa-solid fa-circle-check"></i>');
const toastErr = (m) => toast(m, 'error',  '<i class="fa-solid fa-circle-xmark"></i>');
const toastInfo= (m) => toast(m, 'info',   '<i class="fa-solid fa-circle-info"></i>');

function loading(show) {
  document.getElementById('loading-overlay').classList.toggle('show', show);
}

function clearModalState() { State.editId = null; }

function showTab(id) {
  document.querySelectorAll('.tab-btn').forEach(b=>b.classList.remove('active'));
  document.querySelectorAll('.tab-pane').forEach(p=>p.classList.remove('active'));
  document.getElementById(id)?.classList.add('active');
  document.querySelector(`[onclick="showTab('${id}')"]`)?.classList.add('active');
}

function stateColor(estado) {
  const m = { pendiente:'--warning', preparando:'--accent', listo:'--success', pagado:'--blue', cancelado:'--danger'};
  return m[estado] || '--muted';
}

function badgeHtml(estado) {
  return `<span class="badge badge-${estado}">${estado}</span>`;
}

function chipRole(role) {
  return `<span class="chip chip-${role}">${role}</span>`;
}

/* ── Topbar ─────────────────────────────────── */
function updateTopbar() {
  const u = Auth.user;
  if (!u) return;
  const username = u.username || u.usuario || 'Usuario';
  const role = u.role || u.rol || 'admin';
  document.getElementById('tb-username').textContent = username;
  document.getElementById('tb-role').textContent     = role;
  document.getElementById('tb-avatar').textContent   = username.charAt(0).toUpperCase();
  document.getElementById('topbar').style.display    = 'flex';
}

function hideTopbar() {
  document.getElementById('topbar').style.display = 'none';
}

/* ── Login ──────────────────────────────────── */
async function doLogin() {
  const username = document.getElementById('login-user').value.trim();
  const password = document.getElementById('login-pass').value;
  const errEl    = document.getElementById('login-error');
  const btn      = document.getElementById('login-btn');

  if (!username || !password) { showLoginError('Completa todos los campos.'); return; }

  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Ingresando...';
  errEl.classList.remove('show');

  try {
    const res = await api.auth.login(username, password);
    Auth.set(res);
    btn.disabled = false;
    btn.textContent = 'INGRESAR';
    updateTopbar();
    goToRolePanel();
  } catch(e) {
    showLoginError(e.message);
    btn.disabled = false;
    btn.textContent = 'INGRESAR';
  }
}

function showLoginError(msg) {
  const el = document.getElementById('login-error');
  el.textContent = msg;
  el.classList.add('show');
}

function doLogout() {
  Auth.clear();
  State.carrito = [];
  if (State.socket) { State.socket.disconnect(); State.socket = null; }
  hideTopbar();
  go('screen-login');
}

/* ── Role Router ─────────────────────────────── */
function updateMenuRoles() {
  const role = Auth.user?.role || Auth.user?.rol;
  const adminPanel = document.getElementById('role-admin');
  const cocinaPanel = document.getElementById('role-cocina');
  const meseroPanel = document.getElementById('role-mesero');
  
  if (adminPanel) adminPanel.style.display   = (role === 'admin') ? 'flex' : 'none';
  if (cocinaPanel) cocinaPanel.style.display = (role === 'admin' || role === 'cocina') ? 'flex' : 'none';
  if (meseroPanel) meseroPanel.style.display = (role === 'admin' || role === 'mesero') ? 'flex' : 'none';

  document.querySelectorAll('.admin-only').forEach(el => {
    el.style.display = role === 'admin' ? '' : 'none';
  });
}

function goToRolePanel() {
  updateMenuRoles();
  const role = Auth.user?.role || Auth.user?.rol;
  if (role === 'admin')  { go('screen-menu'); }
  else if (role === 'mesero') { enterMesero(); }
  else if (role === 'cocina') { enterCocina(); }
  else { go('screen-menu'); }
}

function getRole() {
  return Auth.user?.role || Auth.user?.rol || '';
}

function enterAdmin() {
  if (getRole() !== 'admin') { toastErr('Acceso denegado. Solo admin.'); return; }
  show('screen-admin');
  loadAdminData();
}

function enterMesero() {
  if (getRole() === 'cocina') { toastErr('Acceso denegado.'); return; }
  show('screen-mesero');
  loadMeseroData();
}

function enterCocina() {
  show('screen-cocina');
  loadCocinaData();
}

/* ── Socket.IO ──────────────────────────────── */
function initSocket() {
  if (State.socket) return;
  // socket.io se carga desde CDN en el HTML
  const s = io({ transports: ['websocket','polling'] });
  State.socket = s;

  s.on('connect', () => {
    document.getElementById('socket-dot').className = 'socket-dot connected';
    toastInfo('Conexión en tiempo real activa');
  });

  s.on('disconnect', () => {
    document.getElementById('socket-dot').className = 'socket-dot disconnected';
  });

  s.on('nuevo_pedido', (pedido) => {
    // FIFO: nuevo pedido al FINAL de la cola
    State.pedidos = [...State.pedidos, pedido];
    if (getRole() === 'mesero' || getRole() === 'admin') {
      toastInfo(`Pedido #${pedido.id} registrado — Mesa ${pedido.mesa}`);
    }
    renderCocina();
    renderMeseroPedidos();
    renderAdminPedidos();
  });

  s.on('pedido_actualizado', (pedido) => {
    const i = State.pedidos.findIndex(p => p.id === pedido.id);
    if (i >= 0) State.pedidos[i] = pedido; else State.pedidos.push(pedido);

    // Avisos inteligentes por rol
    const role = getRole();
    if (pedido.estado === 'listo' && role === 'mesero') {
      toastOk(`Mesa ${pedido.mesa} lista para cobrar — ${fmt.currency(pedido.total)}`);
    } else if (pedido.estado === 'listo' && role === 'admin') {
      toastInfo(`Pedido #${pedido.id} listo — Mesa ${pedido.mesa}`);
    } else if (pedido._accion === 'productos_agregados' && role === 'cocina') {
      toastInfo(`Pedido #${pedido.id} actualizado — nuevos items en Mesa ${pedido.mesa}`);
    }

    renderCocina();
    renderMeseroPedidos();
    renderAdminPedidos();
  });
}

/* ── Sesión activa al recargar ──────────────── */
function checkSession() {
  if (Auth.isLogged()) {
    updateTopbar();
    initSocket();
    goToRolePanel();
  } else {
    go('screen-login');
  }
}

/* ── Init ───────────────────────────────────── */
document.addEventListener('DOMContentLoaded', () => {
  // Login form
  document.getElementById('login-form').addEventListener('submit', e => { e.preventDefault(); doLogin(); });
  // Modal user form
  document.getElementById('form-user').addEventListener('submit', e => { e.preventDefault(); submitUser(); });
  // Modal product form
  document.getElementById('form-product').addEventListener('submit', e => { e.preventDefault(); submitProduct(); });
  // Order form
  document.getElementById('form-pedido').addEventListener('submit', e => { e.preventDefault(); submitPedido(); });

  checkSession();
  initSocket();
});
