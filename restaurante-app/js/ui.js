/**
 * ui.js - Funciones reutilizables de UI
 * Toasts, loaders, y generadores de elementos comunes
 */

const ui = {
  /**
   * Muestra un toast (notificación) en pantalla
   * @param {string} mensaje 
   * @param {string} tipo 'success', 'error', 'warning'
   */
  showToast(mensaje, tipo = 'success') {
    let container = document.getElementById('toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'toast-container';
      document.body.appendChild(container);
    }

    const toast = document.createElement('div');
    toast.className = `toast btn-${tipo}`;
    toast.textContent = mensaje;

    container.appendChild(toast);

    // Eliminar después de 3 segundos
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(100%)';
      toast.style.transition = 'all 0.3s ease';
      setTimeout(() => toast.remove(), 300);
    }, 3000);
  },

  /**
   * Crea y retorna un loader HTML
   */
  createLoader() {
    const loader = document.createElement('div');
    loader.className = 'loader';
    return loader;
  },

  /**
   * Limpia un contenedor y muestra un mensaje de error
   * @param {HTMLElement} container 
   * @param {string} mensaje 
   */
  showError(container, mensaje) {
    container.innerHTML = `
      <div style="text-align: center; color: #ef4444; padding: 20px;">
        <p>⚠️ ${mensaje}</p>
        <button class="btn btn-primary" style="margin-top: 10px;" onclick="location.reload()">Reintentar</button>
      </div>
    `;
  },

  /**
   * Formatea el estado para mostrarlo con un badge
   * @param {string} estado 
   */
  renderEstadoBadge(estado) {
    const className = `badge badge-${estado.toLowerCase()}`;
    return `<span class="${className}">${estado.toUpperCase()}</span>`;
  }
};

window.ui = ui;
