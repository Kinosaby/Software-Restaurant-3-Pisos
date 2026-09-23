# Tres Pisos — App Android

App del POS del Restaurante 3 Pisos. Funciona **sin internet**: la tablet de cocina es la central del restaurante y las demás se conectan a ella por el Wi-Fi local. No usa Railway ni ningún servidor externo.

## Dos formas de conectarse

La primera vez que se abre, la app pregunta cómo trabajará esa tablet (se puede cambiar en Gestión → Conexión, o desde el login):

| Modo | Para qué |
|------|----------|
| **Central de cocina** | La tablet de cocina guarda usuarios, menú, pedidos y ventas, y atiende a las demás por el Wi-Fi (puerto 8787). Arranca con el menú del restaurante (54 productos). |
| **Conectada a la central** | Tablets de meseros o caja. Se enlazan **escaneando el QR** de la central. |

El router Wi-Fi solo tiene que dar red local: no necesita internet.

### Enlazar una tablet

1. En la tablet de cocina: **Gestión → Central de cocina** muestra un **QR** con la IP, el puerto y el código de enlace.
2. En la tablet del mesero: **Conectada a la central → Escanear QR de la central**, confirmar y iniciar sesión.

El escáner es el de Google Play Services: no pide permiso de cámara y se descarga al instalar la app (esa primera vez la tablet debe tener internet). Si no está disponible, sirve la **cámara normal** de la tablet o Google Lens: el QR es un enlace `trespisos://enlace?...` que abre la app directamente. Sin cámara, en "Sin cámara: escribir IP y código" se busca la central en el Wi-Fi o se escribe su IP y el código.

Antes de cambiar de central la app siempre pide confirmación, así un QR ajeno no puede redirigir la tablet sin que nadie lo note.

El código de enlace y la IP se ven en la tablet central, en **Gestión → Central de cocina**. Si se pierde una tablet, ahí mismo se renueva el código: se cierran todas las sesiones y cada tablet vuelve a enlazarse.

### Qué pasa si se pierde la conexión

| Situación | Resultado |
|-----------|-----------|
| Normal (sin internet, con Wi-Fi) | Todo funciona con la central de cocina. |
| La tablet del mesero pierde el Wi-Fi o la central se apaga | Se ven el menú y los pedidos guardados. Los pedidos nuevos (y los productos agregados) quedan en **Pendientes de enviar** y se envían solos al volver la conexión, sin duplicarse. |
| La central rechaza un envío (p. ej. producto desactivado mientras tanto) | Queda marcado en rojo con el motivo; se reintenta o se descarta a mano. |
| Cobros, cambios de estado y ediciones sin conexión | No se hacen: necesitan confirmación de la central en el momento. |
| Se reinicia la tablet central | Recupera todo: cada operación se escribe a disco antes de responder. |

Limitaciones: la central debe tener la app **abierta** y estar conectada a la corriente (la pantalla se mantiene encendida sola). Tablets que no comparten Wi-Fi no pueden pasarse pedidos. Todos los datos viven en la tablet central: no hay copia en la nube, por eso los respaldos son imprescindibles.

## Respaldos

En la tablet central, **Gestión → Respaldos**:

- **Guardar en…** abre el selector de Android (Descargas, Drive, memoria USB). **Enviar por…** lo manda por WhatsApp, correo o Drive.
- El archivo `.3pisos` contiene usuarios, menú, pedidos, ventas y el código de enlace, comprimido y cifrado con AES-256-GCM. La clave se deriva de la contraseña que elijas (mínimo 8 caracteres) con PBKDF2-HMAC-SHA256 y 200 000 iteraciones. **Sin la contraseña no se puede abrir**: no hay forma de recuperarla.
- Gestión marca en rojo la opción si nunca se ha respaldado o si pasaron 7 días o más.

Para **restaurar** en una tablet nueva: instala la app → **Central de cocina** → **Restaurar desde un respaldo** → elige el archivo y escribe la contraseña. Nunca sobrescribe una central que ya tiene datos. Las sesiones se cierran (secreto nuevo), pero el código de enlace se conserva: en cada tablet de mesero solo hay que buscar de nuevo la central (su IP cambia) e iniciar sesión.

## Qué hace cada rol

| Rol | Pantalla | Puede |
|-----|----------|-------|
| `mesero` | Salón | Mapa de mesas en vivo, cuentas agrupadas por mesa, cobradas hoy; crear pedidos (mesa, aquí/llevar, varios comensales, notas, productos sueltos para llevar); agregar, editar, cambiar mesa; cobrar con efectivo y cambio o con tarjeta; cancelar; repetir pedidos; compartir la cuenta |
| `cocina` | Cocina | Pedidos agrupados por mesa (los de llevar aparte), del más antiguo al más nuevo; casillas por producto; preparar / listo por mesa; cancelar lo que aún no termina; extras de pedidos ya terminados |
| `admin` | Salón · Cocina · Caja · Gestión | Todo lo anterior; caja con cobro de mesa completa; métricas (hoy, semana, jueves a domingo, 7 y 30 días); historial de pedidos con borrado; productos; usuarios; datos de la central |

### Lo que el móvil hace mejor que la web

- **Alertas con sonido y vibración**: cocina suena al entrar un pedido o un extra; el mesero recibe aviso cuando *su* pedido está listo o si cocina lo cancela, esté en la pantalla que esté. Se silencian desde el menú del usuario.
- **Mapa de mesas en vivo**: color por estado (libre, esperando, en cocina, lista) y minutos ocupada; tocar una mesa libre empieza el pedido.
- **Frecuentes y repetir pedido**: lo más pedido desde esa tablet aparece primero en el catálogo; un pedido cobrado se repite en un toque (al precio actual).
- **Ticket para compartir**: la cuenta o el ticket de cobro como imagen, para WhatsApp o para imprimir.
- **Trabajo sin internet** con la central de cocina y cola de envíos.

## Ejecutar

```bash
cd tres_pisos_app
flutter pub get
flutter run
```

## Estructura

```
lib/
  main.dart            Carga la sesión y, en la tablet de cocina, arranca la central
  app.dart             Router con redirección por conexión, sesión y rol
  central/             La central: reglas de negocio, diario en disco, seguridad, respaldos y servidor HTTP/WebSocket
  core/                Cliente HTTP, almacenamiento local, canal nativo, tema y widgets comunes
  features/
    conexion/          Elegir modo, enlazar con la central y pantalla de la central
    auth/              Login y sesión
    pedidos/           Modelos, repositorio, tiempo real, caché y cola sin conexión
    mesas/             Mapa de mesas y cuentas por mesa
    mesero/            Salón, captura, detalle y edición de pedidos
    cocina/            Tablero de cocina
    caja/              Caja, cobro y tickets
    avisos/            Alertas con sonido y vibración
    admin/             Métricas, historial, productos y usuarios
android/app/src/main/kotlin/.../MainActivity.kt   Sonido, vibración, pantalla encendida, compartir y selector de archivos
```

### Cómo guarda los datos la central

En `central.jsonl` dentro del almacenamiento privado de la app: cada operación añade una línea y se fuerza a disco antes de responder. Una línea cortada por un apagón se descarta al arrancar; cada 3 000 líneas el archivo se compacta con un reemplazo atómico. Las contraseñas van con PBKDF2-HMAC-SHA256 y sal propia; las sesiones son JWT HS256 que se invalidan al cambiar contraseña o rol, o al renovar el código de enlace. Tras 5 intentos fallidos de login desde una IP, se bloquea 30 segundos.

La comunicación en el Wi-Fi es HTTP sin cifrar protegido por el código de enlace: usa la red del personal, no la de invitados, y no expongas el puerto 8787 a internet.

## Pruebas

```bash
flutter analyze
flutter test
```

Incluyen la central completa (reglas, permisos, persistencia tras reinicio y apagón, compactación, HTTP y WebSocket reales) y una prueba de punta a punta en la que la tablet pierde la conexión, guarda el pedido y lo envía una sola vez al volver.

## APK en GitHub Actions

`.github/workflows/app-android.yml` analiza, prueba y compila el APK release en cada push a `main` que toque `tres_pisos_app/`, o a mano desde **Actions → App Android → Run workflow**. El APK queda como artefacto `tres-pisos-apk`.

| Nombre | Tipo | Para qué |
|--------|------|----------|
| `ANDROID_KEYSTORE_BASE64` | secreto | Keystore `.jks` en base64 |
| `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | secretos | Datos de la clave |

Sin los secretos el APK se firma con una clave de debug temporal. En local, la firma permanente usa `POS_KEYSTORE_PATH`, `POS_KEY_ALIAS`, `POS_STORE_PASSWORD` y `POS_KEY_PASSWORD`.

## Notas técnicas

- No se usan plugins que dependan de `path_provider`/`objective_c` (`flutter_secure_storage`, `share_plus`, `audioplayers`, `sqflite_common_ffi`…): ejecutan un hook de compilación que falla en Windows cuando la ruta del SDK tiene espacios. Sonido, vibración, pantalla encendida y compartir van por un canal nativo propio.
- La sesión y la caché usan `shared_preferences` (almacenamiento privado de la app, sin cifrado adicional).
