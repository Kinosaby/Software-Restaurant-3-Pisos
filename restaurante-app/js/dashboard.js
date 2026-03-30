/**
 * dashboard.js - Lógica para el selector de perfil
 */

function initDashboard() {
  window.auth.checkAuth();
  const user = window.auth.getUser();
  
  if (!user) {
    window.location.href = '/pages/login.html';
    return;
  }

  const welcomeText = document.getElementById('username-display');
  if (welcomeText) welcomeText.textContent = user.username;

  const roleContainers = {
    admin: document.getElementById('admin-only'),
    mesero: document.getElementById('mesero-only'),
    cocina: document.getElementById('cocina-only')
  };

  // Mostrar opciones según rol
  if (user.role === 'admin') {
    Object.values(roleContainers).forEach(el => { if (el) el.style.display = 'block'; });
  } else if (roleContainers[user.role]) {
    roleContainers[user.role].style.display = 'block';
  }

  // Renderizar iconos
  renderIcons();
}

function renderIcons() {
  const iconMappings = {
    'icon-cocina': window.icons.cocina,
    'icon-mesero': window.icons.mesero,
    'icon-admin': window.icons.admin,
    'icon-logout': window.icons.logout
  };

  Object.entries(iconMappings).forEach(([id, svg]) => {
    const el = document.getElementById(id);
    if (el) el.innerHTML = svg;
  });
}

document.addEventListener('DOMContentLoaded', initDashboard);
