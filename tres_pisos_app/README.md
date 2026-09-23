# Tres Pisos — App Android

Cliente Flutter del POS del Restaurante 3 Pisos. Habla con el mismo backend Node que la web (`/api/*` + Socket.IO).

## Qué hace cada rol

| Rol | Pantalla | Puede |
|-----|----------|-------|
| `mesero` | Pedidos | Ver pedidos activos; crear pedidos (mesa, para aquí/llevar, varios comensales, notas); agregar productos; editar cantidades, notas, mesa, tipo o comensal mientras cocina no termina; cobrar pedidos listos y cancelar pedidos pendientes o en preparación |
| `cocina` | Cocina | Ver pedidos pendientes y en preparación en orden de llegada, pasarlos a "preparando" y "listo", y ver los extras que llegan para pedidos ya terminados |
| `admin` | Pedidos · Cocina · Caja · Gestión | Todo lo anterior; en Caja, los pedidos listos por cobrar; en Gestión, métricas de ventas, productos (precios, categorías, disponibilidad) y usuarios |

**Varios comensales:** en un pedido nuevo, "+ Comensal" añade pestañas C1, C2… y cada una lleva sus productos. Al enviar se crea un pedido por comensal, como en la web. Tocar la pestaña activa permite ponerle nombre (por ejemplo, el cliente de un pedido para llevar). Si falla el envío a medias, los comensales ya enviados se vacían para que el reintento no los duplique.

**Productos y usuarios con historial:** el backend no deja borrar un producto o usuario que ya aparece en pedidos (clave foránea). En ese caso la app lo explica: el producto se desactiva y al usuario se le cambia la contraseña.

Los cambios llegan en tiempo real (`nuevo_pedido`, `pedido_actualizado`, `extra_pedido`). El punto de la barra superior indica si hay conexión en tiempo real. Al reconectar, la lista se recarga para no perder eventos.

## Ejecutar

```bash
cd tres_pisos_app
flutter pub get
flutter run
```

El servidor se configura en la pantalla de login (sección **Servidor**) y se recuerda entre sesiones. El valor inicial es `http://10.0.2.2:3000`: así ve el emulador de Android el `localhost` del PC. Para una tablet en la red del restaurante, usa la IP del equipo que corre el backend (p. ej. `http://192.168.1.50:3000`). También se puede fijar al compilar:

```bash
flutter run --dart-define=API_URL=http://192.168.1.50:3000
flutter build apk --release --dart-define=API_URL=https://tu-app.up.railway.app
```

## Estructura

```
lib/
  main.dart            Carga la sesión guardada y arranca la app
  app.dart             Router (GoRouter) con redirección por sesión y rol
  core/                Cliente HTTP, configuración, tema, formato y widgets comunes
  features/
    auth/              Login, sesión (JWT) y su almacenamiento
    pedidos/           Modelos, repositorio REST, Socket.IO y estado de pedidos activos
    mesero/            Lista de pedidos, detalle, captura (nuevo / agregar) y edición
    cocina/            Tablero de cocina
    caja/              Cobro de pedidos listos
    admin/             Métricas, productos y usuarios
    inicio/            Pantalla principal según el rol
```

Estado con Riverpod 3, HTTP con Dio, navegación con GoRouter y tiempo real con `socket_io_client`.

## Pruebas

```bash
flutter analyze
flutter test
```

## APK en GitHub Actions

`.github/workflows/app-android.yml` analiza, prueba y compila el APK release en cada push a `main` que toque `tres_pisos_app/`, o a mano desde **Actions → App Android → Run workflow**. El APK queda como artefacto `tres-pisos-apk`. En los PR solo se analiza y se prueba.

Configuración en **Settings → Secrets and variables → Actions**:

| Nombre | Tipo | Para qué |
|--------|------|----------|
| `ANDROID_KEYSTORE_BASE64` | secreto | Keystore `.jks` en base64 |
| `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | secretos | Datos de la clave |
| `API_URL` | variable (opcional) | Servidor que aparece de entrada en el login |

Sin los secretos el APK se firma con una clave de debug temporal, así que cada APK nuevo exige desinstalar el anterior. En local, la firma permanente se activa con las variables de entorno `POS_KEYSTORE_PATH`, `POS_KEY_ALIAS`, `POS_STORE_PASSWORD` y `POS_KEY_PASSWORD`.

## Notas

- La sesión se guarda con `shared_preferences`. No se usa `flutter_secure_storage` porque su cadena de dependencias (`path_provider` → `objective_c`) ejecuta un hook de compilación que falla en Windows cuando la ruta del SDK de Flutter tiene espacios.
- El manifiesto permite HTTP sin cifrar (`usesCleartextTraffic`) porque el backend suele estar en la red local. Si solo se usa un servidor HTTPS, se puede quitar.
