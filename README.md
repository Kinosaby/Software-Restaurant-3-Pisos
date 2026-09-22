# Sistema Restaurante 3 Pisos — Backend, Web y Android

Este es el backend profesional y la aplicación Single Page Application (SPA) para el sistema Punto de Venta (POS) del "Restaurante 3 Pisos".

## Características Principales

*   **Autenticación y Autorización:** Implementado con JWT (JSON Web Tokens) y contraseñas encriptadas usando `bcryptjs`.
*   **Roles de Usuario:**
    *   **Mesero:** Puede tomar pedidos, agregar notas y visualizar un flujo de cobro.
    *   **Cocina:** Visualiza los pedidos entrantes y actualiza su estado (En preparación, Listo).
    *   **Caja:** Gestiona los cobros finales de los pedidos procesados.
*   **Comunicación en Tiempo Real:** Uso de `socket.io` para actualizar el estado de las órdenes entre Meseros, Cocina y Caja instantáneamente.
*   **Base de Datos PostgreSQL:** Almacenamiento seguro, conectado mediante el driver `pg`.
*   **Interfaz de Usuario (SPA):** Ubicada dentro de la carpeta `restaurante-app/`. Interfaz fluida sin recargas, utilizando Vanilla JS, HTML y CSS.
*   **Aplicación Android:** Cliente Flutter por roles dentro de `tres_pisos_app/`.

## Estructura del Proyecto

*   `src/`: Contiene toda la lógica del backend (Controladores, Rutas, Middlewares, Sockets, Configuración).
    *   `src/controllers/`: Lógica de negocio (auth, orders, products).
    *   `src/routes/`: Definición de endpoints de la API.
    *   `src/middlewares/`: Middlewares como autenticación (`auth.middleware.js`) y manejo de errores.
    *   `src/sockets/`: Gestión de WebSockets.
*   `restaurante-app/`: Aplicación frontend SPA (HTML, CSS, JS).
*   `server.js`: Punto de entrada principal del servidor Express.

## Requisitos

*   Node.js (v18+)
*   PostgreSQL

## Instalación y Ejecución

1.  **Clonar el repositorio:**
    ```bash
    git clone https://github.com/Kinosaby/Software-Restaurant-3-Pisos.git
    cd Software-Restaurant-3-Pisos
    ```

2.  **Instalar dependencias:**
    ```bash
    npm install
    ```

3.  **Configurar Variables de Entorno:**
    Copia `.env.example` como `.env`. En Railway, `DATABASE_URL` aparece automáticamente cuando PostgreSQL está enlazado al servicio. Variables principales:
    ```env
    PORT=3000
    DATABASE_URL=postgresql://usuario:contraseña@host:5432/base
    DB_SSL=true
    JWT_SECRET=tu_secreto_super_seguro
    ADMIN_USERNAME=admin
    ADMIN_PASSWORD=una_contraseña_inicial_segura
    ```

    `ADMIN_PASSWORD` solo se usa si la tabla de usuarios está vacía. El esquema y las migraciones se aplican automáticamente al iniciar.

4.  **Iniciar el servidor:**
    *   Modo desarrollo:
        ```bash
        npm run dev
        ```
    *   Modo producción:
        ```bash
        npm start
        ```

5.  **Acceder a la Aplicación:**
    Abre tu navegador web en `http://localhost:3000` (o el puerto configurado).

## Tecnologías Utilizadas

*   **Backend:** Node.js, Express, Socket.io, PostgreSQL, JWT, Bcrypt.js, Helmet, Express-validator.
*   **Frontend:** HTML5, CSS3, JavaScript Vanilla.
*   **Android:** Flutter, Riverpod, Dio, GoRouter y Socket.IO Client.

## Pruebas

```bash
npm run check
npm test
npm audit --omit=dev
```

Consulta `tres_pisos_app/README.md` para ejecutar Flutter o generar el APK con GitHub Actions.
