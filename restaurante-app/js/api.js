/**
 * api.js — Cliente HTTP para el backend 3 Pisos POS
 * Incluye: autenticación JWT, interceptor de errores, helpers tipados.
 */

const API_BASE = '';   // mismo origen (express sirve el frontend)

/* ── Token storage ─────────────────────────── */
const Auth = {
  get token()    { return localStorage.getItem('pos_token'); },
  get user()     { const u = localStorage.getItem('pos_user'); return u ? JSON.parse(u) : null; },
  set({ token, user }) {
    localStorage.setItem('pos_token', token);
    localStorage.setItem('pos_user', JSON.stringify(user));
  },
  clear() {
    localStorage.removeItem('pos_token');
    localStorage.removeItem('pos_user');
  },
  isLogged() { return !!this.token; },
};

/* ── Core fetch wrapper ─────────────────────── */
async function request(method, path, body = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (Auth.token) headers['Authorization'] = 'Bearer ' + Auth.token;

  const opts = { method, headers };
  if (body) opts.body = JSON.stringify(body);

  const res = await fetch(API_BASE + path, opts);
  const data = await res.json().catch(() => ({ error: 'Respuesta inválida del servidor' }));

  if (!res.ok) {
    // Parsear mensaje según estructura del backend
    const msg = data.errors?.[0]?.mensaje
      || data.error
      || `Error ${res.status}`;
    const err = new Error(msg);
    err.status = res.status;
    err.data   = data;
    throw err;
  }
  return data;
}

const get    = (path)       => request('GET',    path);
const post   = (path, body) => request('POST',   path, body);
const put    = (path, body) => request('PUT',    path, body);
const patch  = (path, body) => request('PATCH',  path, body);
const del    = (path)       => request('DELETE', path);

/* ── Auth endpoints ─────────────────────────── */
const api = {
  auth: {
    login:         (username, password) => post('/api/auth/login', { username, password }),
    me:            ()                   => get('/api/auth/me'),
    listarUsuarios:()                   => get('/api/auth/usuarios'),
    registrar:     (body)               => post('/api/auth/register', body),
    actualizar:    (id, body)           => put(`/api/auth/${id}`, body),
    eliminar:      (id)                 => del(`/api/auth/${id}`),
  },

  productos: {
    listar:    ()       => get('/api/productos'),
    crear:     (body)   => post('/api/productos', body),
    actualizar:(id, b)  => put(`/api/productos/${id}`, b),
    eliminar:  (id)     => del(`/api/productos/${id}`),
  },

  pedidos: {
    listar:        (estado='') => get('/api/pedidos' + (estado ? `?estado=${estado}` : '')),
    obtener:       (id)        => get(`/api/pedidos/${id}`),
    crear:         (body)      => post('/api/pedidos', body),
    cambiarEstado: (id, estado)=> put(`/api/pedidos/${id}/estado`, { estado }),
    cancelar:      (id)        => patch(`/api/pedidos/${id}/cancelar`),
    agregar:       (id, body)  => patch(`/api/pedidos/${id}/agregar`, body),
    eliminar:      (id)        => del(`/api/pedidos/${id}`),
  },

  metricas: {
    resumen:        ()     => get('/api/metricas/resumen'),
    dia:            ()     => get('/api/metricas/dia'),
    estados:        ()     => get('/api/metricas/estados'),
    ventas:         (d=7)  => get(`/api/metricas/ventas?dias=${d}`),
    productosTop:   (n=5)  => get(`/api/metricas/productos-top?limit=${n}`),
  },
};

/* ── Formatters ─────────────────────────────── */
const fmt = {
  currency: (n) => `$${parseFloat(n||0).toFixed(2)}`,
  date:     (s) => new Date(s).toLocaleString('es-MX', { day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' }),
  relTime:  (s) => {
    const d = Date.now() - new Date(s).getTime();
    const m = Math.floor(d / 60000);
    if (m < 1) return 'Ahora';
    if (m < 60) return `${m}m`;
    return `${Math.floor(m/60)}h ${m%60}m`;
  },
};
