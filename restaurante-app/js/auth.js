/**
 * auth.js - Manejo de sesión en el frontend
 */

const auth = {
  /**
   * Guardar datos de sesión
   */
  saveSession(token, user) {
    localStorage.setItem('pos_token', token);
    localStorage.setItem('pos_user', JSON.stringify(user));
  },

  /**
   * Obtener token actual
   */
  getToken() {
    return localStorage.getItem('pos_token');
  },

  /**
   * Obtener datos del usuario
   */
  getUser() {
    const user = localStorage.getItem('pos_user');
    return user ? JSON.parse(user) : null;
  },

  /**
   * Cerrar sesión
   */
  logout() {
    localStorage.removeItem('pos_token');
    localStorage.removeItem('pos_user');
    window.location.href = '/pages/login.html';
  },

  /**
   * Verificar si está autenticado
   */
  isAuthenticated() {
    return !!this.getToken();
  },

  /**
   * Redirigir si no está autenticado
   */
  checkAuth() {
    if (!this.isAuthenticated()) {
      window.location.href = '/pages/login.html';
    }
  }
};

window.auth = auth;
