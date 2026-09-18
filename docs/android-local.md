# Android local: web completa

La versión 2.3 empaqueta `restaurante-app/index.html`, sus pantallas y recursos dentro de Flutter. SQLite en la tablet de cocina atiende la misma API. No necesita Railway, Supabase, CDN ni computadora. El backend web existente se conserva por separado.

## Empezar

1. Instala el APK en las tres tablets, Android 7 / API 24 o superior. Mantén actualizado Android System WebView.
2. Conéctalas al mismo Wi-Fi. El router funciona sin Internet, pero no debe aislar dispositivos como una red de invitados. Conviene reservar la IP de cocina en el router.
3. En cocina selecciona **Central de cocina** y crea el administrador. No hay contraseña predeterminada. Inicia sesión como administrador, abre **Conexión** y copia el código `trespisos://…`.
4. En meseros selecciona **Vincular tablet** y pega el código. El enlace inicial y el inicio de sesión requieren comunicación con cocina.
5. El menú del propietario ya se carga en centrales nuevas: 54 productos, 53 disponibles y Birria de $100 desactivada. Desde Administración crea los usuarios de mesero y cocina. Después inicia sesión como cocina en la central.
6. Mantén la app abierta en cocina y la tablet conectada a corriente. La app mantiene activa la pantalla mientras se utiliza. No se promete operación en segundo plano, con Android suspendido, la app cerrada o la tablet apagada.
7. Prueba con tus tres tablets: dos comensales, extras, cancelación, cobro, reinicio y desconexión de Internet del router antes de atender clientes.

**Las instalaciones nuevas ya incluyen el menú transcrito de las tres capturas del propietario, sin ventas ni pedidos anteriores.** Se conservan nombres, precios, categorías y disponibilidad. Los IDs de las capturas solo documentan el origen. El menú integrado no sobrescribe un catálogo existente: para actualizarlo abre Productos → Cargar menú del restaurante y revisa los cambios. No se requiere migrar el historial de Railway. Los respaldos completos recuperan instalaciones de esta app y son independientes de la importación del menú.

## Accesos del restaurante

El APK público no contiene claves predeterminadas. Para instalar las cuentas preparadas del propietario, en una **central nueva** selecciona **Cargar accesos o respaldo**, abre el archivo privado `Inicio-3-Pisos.3pisos` e introduce su clave. Los usuarios y contraseñas se entregan por separado en `Accesos-3-Pisos.txt`; ese documento y el archivo privado no se guardan en GitHub. Luego pulsa **Iniciar central** sin crear otra cuenta.

| Cuenta | Rol y operaciones |
|---|---|
| admin | Menú, usuarios, reportes, respaldo y acceso a meseros/cocina |
| cocina | Preparación, productos listos, extras y cancelación antes de listo |
| mesero1 / mesero2 | Pedidos, comensales, notas, extras, cancelación y cobro |

Los meseros no pueden editar menú/usuarios, preparar pedidos ni abrir reportes o respaldos. Cocina no puede tomar pedidos ni cobrar. Cada tablet de mesero usa su propia cuenta. Iniciar sesión requiere comunicación con la central, pero **no Internet**. Una sesión ya iniciada permite consultar lo descargado y guardar pedidos pendientes si se pierde el Wi-Fi. Para comprobar permisos se rechazan también las llamadas directas a la API.

Las claves entregadas solo funcionan después de cargar el archivo privado en una central vacía. No reemplazan claves de instalaciones anteriores. Si la central ya contiene datos, conserva sus accesos y su respaldo; un administrador puede crear o modificar las cuentas desde Usuarios. La restauración no sobrescribe una central existente.

Desde 2.2, los comprobantes de reintento guardan una huella SHA-256 de la solicitud. Las actualizaciones de bases y la restauración de respaldos anteriores convierten esos comprobantes para no retener claves en texto claro. Las contraseñas de las cuentas se almacenan con PBKDF2 y sal individual.

## Cargar únicamente el menú

En la tablet central inicia sesión como administrador y abre **Productos → Importar menú**. Selecciona un archivo UTF-8 `.csv` o `.json`. La vista previa muestra cada producto, categoría, disponibilidad y precio en MXN; indica cuáles se crearán o actualizarán. Solo se guarda al pulsar **Guardar menú**. Cancelar no cambia nada.

CSV: encabezados `nombre,precio,categoria,activo`. Nombre y precio son obligatorios; categoría vacía usa General y disponibilidad vacía usa true. Usa precios sin símbolo de moneda ni separadores de miles, con un máximo de dos decimales. Se acepta coma decimal cuando las columnas están separadas por punto y coma. Disponibilidad: true/false, 1/0 o sí/no. JSON: lista de productos o un objeto con `productos`; precios numéricos o texto decimal con punto. Si se incluye `moneda`, debe ser MXN. Límite: 2000 productos y 2 MB.

Se identifican coincidencias por nombre y categoría, ignorando mayúsculas. Se conservan los IDs locales: los IDs externos no se importan. Los productos ausentes del archivo permanecen; las cuentas existentes conservan sus precios. No se importan usuarios, pedidos ni ventas. Duplicados ambiguos o precios inválidos bloquean el archivo entero. Si alguien cambia el catálogo durante la revisión, hay que revisarlo de nuevo.

**Guardar archivo del menú** permite compartir un JSON que contiene únicamente el catálogo y volver a importarlo. No sustituye al respaldo completo. La edición manual permite escribir categorías propias; todos los filtros incluyen las categorías activas del catálogo.

## Funciones

| Área | Funciones incluidas |
|---|---|
| Acceso | Usuarios, contraseñas y roles administrador, mesero y cocina, con permisos validados en la central |
| Mesero | Catálogo por categorías, 13 mesas, para llevar, comensales separados, cantidades, notas y productos individuales para llevar |
| Pedidos | Envío de comensales en una transacción, activos y pagados del día, agregar productos, editar cantidades/notas, cambiar mesa y cancelar |
| Cobro | Cuenta por comensal o conjunto de cuentas listas, efectivo recibido y cambio; precios originales conservados |
| Cocina | Cola por mesa y llegada, tiempos, para llevar, alertas visuales y sonido con app abierta, preparar/listo, checkboxes y extras persistentes |
| Administración | Crear/editar/eliminar usuarios; crear/editar/desactivar/eliminar productos; categorías; pedidos e historial |
| Reportes | Ventas cobradas del día/semana, tabla y gráfica de jueves a domingo, historial paginado y filtro por fecha |
| Recuperación | Carrito por usuario, cola SQLite, reintentos sin duplicar, enlace cifrado, respaldo y restauración |

Consumo adicional sobre una cuenta pagada abre una **cuenta nueva**. Los extras agregados a una cuenta lista se cobran después de terminarlos cocina. Eliminar un pedido pagado no es un reembolso y conserva la venta registrada. Nombres y notas rechazan marcado HTML y comillas para proteger las plantillas web existentes.

## Desconexiones

| Situación | Resultado |
|---|---|
| Sin Internet, con Wi-Fi local | Las tres tablets siguen operando normalmente |
| Mesero sin enlace con cocina | Consulta lo descargado y guarda nuevos pedidos, indicando que cocina aún no los recibió |
| Vuelve el enlace | Reenvía los pendientes con los mismos identificadores, incluso si se perdió una confirmación |
| Envío rechazado | Queda en Pendientes con motivo. Corrige la causa (producto desactivado o sesión vencida), inicia sesión si hace falta y pulsa Reintentar |
| Sin confirmación de cocina | No confirma cobros ni cambios de cuentas compartidas |
| Reinicio | Recupera SQLite, extras y cola; cocina debe volver a abrir la app |

Tablets completamente aisladas no pueden intercambiar pedidos. No se implementa Bluetooth ni sincronización con Supabase. No hay cuota de alojamiento, pero se necesitan tus equipos, electricidad y router.

## Respaldar

En la central, inicia sesión como administrador y pulsa **Guardar respaldo**. Usa una contraseña de al menos ocho caracteres y guarda el archivo `.3pisos` fuera de la tablet. Comprueba que quedó guardado en el destino: abrir Compartir no garantiza que se haya copiado. El archivo contiene usuarios, menú, pedidos, extras, ventas y comprobantes de reintento; no incluye sesiones ni claves de enlace. Conserva la contraseña: no existe servicio de recuperación.

En una instalación nueva pulsa **Cargar accesos o respaldo** y proporciona archivo y contraseña. Luego inicia la central, entra con los usuarios restaurados y vincula de nuevo los meseros. No mantengas dos centrales activas para un restaurante. Antes de cambiarla, verifica que los meseros no tengan pendientes: el respaldo solo contiene lo recibido en cocina. Los respaldos en la nube no están configurados.

## Desarrollo

```sh
npm ci
node scripts/build-android-web.mjs
cd tres_pisos_app
flutter pub get
flutter analyze
flutter test
POS_ALLOW_TEST_SIGNING=true flutter build apk --release
```

Flutter 3.47.2; workflow `android-apk.yml`. El punto de entrada es `LocalPosApp`; las pantallas Flutter anteriores permanecen como referencia y no se utilizan. Los recursos se reconstruyen desde la web y los lockfiles. El historial se pagina en grupos de 100 y los datos comerciales no se purgan. Reportes con UTC-6 para Hidalgo.

Pruebas: menú completo de 54 productos, conservación de ediciones, migración de comprobantes, tres dispositivos simulados con Internet bloqueado, cuatro accesos, permisos por API, pérdida y recuperación del enlace, roles, lotes atómicos, reintentos, precios, edición concurrente, extras, cobro conjunto, 601 pedidos, historial, respaldo/restauración y recuperación de cola después de perder una confirmación. No sustituyen pruebas de cobertura Wi-Fi y capacidad en las tablets reales.

El APK de pruebas usa la firma de depuración del proyecto. Antes de distribuir actualizaciones permanentes debe configurarse una clave estable guardada fuera del repositorio. Firmas distintas pueden impedir actualizar una instalación anterior. **Nunca desinstales la central sin guardar y comprobar un respaldo.**

La web se sirve solo en `127.0.0.1:8788`. LAN 8787 acepta mensajes cifrados y autenticados con AES-256-GCM y la clave de enlace guardada en almacenamiento seguro de Android; cada respuesta debe corresponder a su solicitud. La web no recibe esa clave y solo navega al origen local. HTTP está habilitado para loopback y el transporte de sobres cifrados LAN. Los cambios se consultan cada 1.2 segundos y los envíos pendientes se reintentan cada cuatro segundos.


## Seguridad y actualización 2.3

Actualiza las **tres tablets** fuera del servicio: LAN 2 exige desafíos aleatorios de un solo uso, que caducan a los 20 segundos en la central sin depender del reloj del cliente. Una app anterior no puede operar con una central actualizada. Conserva AES-256-GCM y los identificadores de operación para no duplicar pedidos.

Antes de actualizar, termina los envíos pendientes y guarda y comprueba un respaldo externo. SQLite migra de esquema 2 a 3 conservando los datos. Si un mesero tenía una sesión antigua sin caducidad almacenada, deberá entrar de nuevo; su cola permanece.

La web exige la cookie HttpOnly/SameSite creada por la WebView nativa, además del token del usuario. Comprueba Host y Origin. Solo un administrador de la central puede ver el código de enlace. En los meseros se puede pegar un código nuevo de la misma central sin revelar la clave anterior.

Cerrar sesión revoca únicamente esa sesión. Sin enlace, el cliente borra su acceso local y guarda la revocación en SQLite para enviarla al reconectar. Los pedidos pendientes se conservan; al entrar de nuevo, revisa y reintenta los bloqueados. Un cambio de contraseña o rol revoca todas las sesiones de la cuenta en la central. Una tablet aislada no puede conocer ese cambio hasta recuperar el enlace, aunque respeta la caducidad local de 30 días. Sin enlace no confirma cobros.

Si se pierde una tablet o se filtra el código: **Conexión → Renovar código de enlace**, con sesión administradora en cocina. Revisa antes los pendientes. Se invalida la clave anterior y se cierran las demás sesiones. En cada mesero pega el nuevo código y vuelve a entrar. Se conserva el mismo restaurante, sus datos y las colas locales.

Los respaldos se validan antes de restaurarse: cuentas, IDs, estados, textos, precios, totales y secuencias. El límite de importación es 64 MB. La SQLite está en el almacenamiento privado de Android; **no usa SQLCipher**. El cifrado protege mensajes LAN y respaldos. Mantén bloqueo de pantalla y Android/WebView actualizados; usa Wi-Fi de personal y no expongas el puerto 8787 a Internet.

## Firma permanente

El workflow automático `android-apk.yml` produce un **APK de validación con firma de prueba**, habilitada expresamente con `POS_ALLOW_TEST_SIGNING=true`. Una compilación release normal falla si faltan las claves privadas: no utiliza una firma de prueba silenciosamente.

Para distribuir actualizaciones permanentes se necesita una única clave privada guardada fuera de Git. Android exige la misma firma en las actualizaciones. Nunca desinstales cocina para resolver un conflicto de firma sin respaldo comprobado.

Genera la clave en tu equipo con contraseñas introducidas de forma interactiva:

```sh
keytool -genkeypair -keystore 3-pisos-release.jks -alias trespisos -keyalg RSA -keysize 3072 -validity 10000
```

Guarda la clave y una copia de seguridad privadas. En GitHub → Settings → Secrets and variables → Actions configura:

| Secreto | Valor |
|---|---|
| ANDROID_KEYSTORE_BASE64 | Archivo JKS codificado en Base64 |
| ANDROID_STORE_PASSWORD | Contraseña del almacén |
| ANDROID_KEY_ALIAS | trespisos o el alias elegido |
| ANDROID_KEY_PASSWORD | Contraseña de la clave |

Ejecuta **APK Android con firma permanente** seleccionando `app-android`. El flujo falla si falta algún secreto, elimina la copia temporal y publica solamente el APK como artefacto. Para compilar localmente usa `POS_KEYSTORE_PATH`, `POS_STORE_PASSWORD`, `POS_KEY_ALIAS` y `POS_KEY_PASSWORD`.

Configurar estos secretos exige acceso administrativo que la conexión utilizada para publicar este código no ofrece. No se han generado ni publicado claves privadas. Su configuración y la prueba en las tablets reales siguen pendientes. Consulta el [informe de seguridad](security-review-2026-09-17.md).
