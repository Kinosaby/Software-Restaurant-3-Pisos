# 🍽️ Restaurante POS - Frontend

Sistema web moderno para la gestión de pedidos en restaurantes, diseñado para tablets y pantallas táctiles.

## 🚀 Características
- **Panel de Mesero:** Selección de productos, gestión de carrito por mesa y envío de pedidos.
- **Panel de Cocina:** Visualización de pedidos en tiempo real con auto-refresh cada 3 segundos y cambio de estados.
- **Diseño Moderno:** Tema oscuro, botones grandes y animaciones suaves.
- **Sin Dependencias:** Construido únicamente con HTML5, CSS3 y JavaScript Vanilla.

## 📂 Estructura del Proyecto
```text
/restaurante-app
│
├── /pages
│   ├── index.html   <- Punto de entrada (Selector de perfil)
│   ├── cocina.html  <- Vista para el personal de cocina
│   └── mesero.html  <- Vista para los meseros
│
├── /css
│   └── estilos.css  <- Estilos globales y variables
│
├── /js
│   ├── api.js       <- Comunicación con el Backend
│   ├── cocina.js    <- Lógica de la cocina
│   ├── mesero.js    <- Lógica del mesero
│   └── ui.js        <- Componentes de interfaz (toasts, loaders)
│
└── README.md
```

## 🛠️ Requisitos
- Tener el **Backend** corriendo en `http://localhost:3000`.
- Navegador moderno (Chrome, Edge, Safari).

## 🖥️ Cómo usar
1. Asegúrate de que el servidor backend esté encendido.
2. Abre el archivo `restaurante-app/pages/index.html` en tu navegador.
3. Elige el perfil que deseas usar (**Cocina** o **Mesero**).

---
Desarrollado con ❤️ para una experiencia gastronómica eficiente.
