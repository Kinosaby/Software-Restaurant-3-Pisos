# Android local: web completa

La versión 2.0 empaqueta `restaurante-app/index.html`, sus pantallas y recursos dentro de Flutter. SQLite en la tablet de cocina atiende la misma API. No necesita Railway, Supabase, CDN ni computadora. El backend web existente se conserva por separado.

## Empezar

1. Instala el APK en las tres tablets, Android 7 / API 24 o superior. Mantén actualizado Android System WebView.
2. Conéctalas al mismo Wi-Fi. El router funciona sin Internet, pero no debe aislar dispositivos como una red de invitados. Conviene reservar la IP de cocina en el router.
3. En cocina selecciona **Central de cocina** y crea el administrador. No hay contraseña predeterminada. Abre **Conexión** y copia el código `trespisos://…`.
4. En meseros selecciona **Vincular tablet** y pega el código. El enlace inicial y el inicio de sesión requieren comunicación con cocina.
5. Desde Administración registra tu menú y crea los usuarios de mesero y cocina. Después inicia sesión como cocina en la central.
6. Mantén la app abierta en cocina y la tablet conectada a corriente. La app mantiene activa la pantalla mientras se utiliza. No se promete operación en segundo plano, con Android suspendido, la app cerrada o la tablet apagada.
7. Prueba con tus tres tablets: dos comensales, extras, cancelación, cobro, reinicio y desconexión de Internet del router antes de atender clientes.

**Esta instalación crea una base local nueva. Los datos de Railway no se copian automáticamente.** No borres el PostgreSQL anterior: se necesita su exportación para preparar una importación de usuarios, menú e historial. Los respaldos de esta app recuperan instalaciones de esta misma versión.

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

En una instalación nueva pulsa **Restaurar un respaldo local** y proporciona archivo y contraseña. Luego inicia la central, entra con los usuarios restaurados y vincula de nuevo los meseros. No mantengas dos centrales activas para un restaurante. Antes de cambiarla, verifica que los meseros no tengan pendientes: el respaldo solo contiene lo recibido en cocina. Los respaldos en la nube no están configurados.

## Desarrollo

```sh
npm ci
node scripts/build-android-web.mjs
cd tres_pisos_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Flutter 3.47.2; workflow `android-apk.yml`. El punto de entrada es `LocalPosApp`; las pantallas Flutter anteriores permanecen como referencia y no se utilizan. Los recursos se reconstruyen desde la web y los lockfiles. El historial se pagina en grupos de 100 y los datos comerciales no se purgan. Reportes con UTC-6 para Hidalgo.

Pruebas: roles, lotes atómicos, reintentos, precios, edición concurrente, extras, cobro conjunto, 601 pedidos, historial, respaldo/restauración y recuperación de cola después de perder una confirmación. No sustituyen pruebas de cobertura Wi-Fi y capacidad en las tablets reales.

El APK de pruebas usa la firma de depuración del proyecto. Antes de distribuir actualizaciones permanentes debe configurarse una clave estable guardada fuera del repositorio. Firmas distintas pueden impedir actualizar una instalación anterior. **Nunca desinstales la central sin guardar y comprobar un respaldo.**

La web se sirve solo en `127.0.0.1:8788`. LAN 8787 acepta mensajes cifrados y autenticados con AES-256-GCM y la clave de enlace guardada en almacenamiento seguro de Android; cada respuesta debe corresponder a su solicitud. La web no recibe esa clave y solo navega al origen local. HTTP está habilitado para loopback y el transporte de sobres cifrados LAN. Los cambios se consultan cada 1.2 segundos y los envíos pendientes se reintentan cada cuatro segundos.
