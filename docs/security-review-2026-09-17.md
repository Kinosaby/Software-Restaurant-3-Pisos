# Revisión de seguridad y funcionamiento

Iniciada el 17 y actualizada el 18 de septiembre de 2026. Rama `app-android`, versión 2.3.1+6.

Se revisaron el motor SQLite, HTTP local, protocolo LAN, puente nativo, acceso por roles, respaldos, pantallas web empaquetadas, configuración Android, autenticación del backend web conservado y dependencias Node. No es una certificación de ausencia de vulnerabilidades.

## Hallazgos corregidos

| Hallazgo | Impacto | Corrección |
|---|---|---|
| Notas y nombres del carrito se insertaban como HTML antes de enviarse | Alto: ejecución de JavaScript | Escape de texto y atributos en carrito, detalles, cocina, catálogo, usuarios y avisos; nombres fuera del código de los botones. |
| Cerrar sesión solo borraba datos del navegador | Alto: token aún válido | Revocación idempotente de la sesión actual; si no hay LAN, revocación local y envío persistente al reconectar. |
| Caché accesible sin comprobar caducidad local | Alto: acceso antiguo | Caducidad, eliminación de identidad/caché tras cierre o rechazo y validación antes de restaurar la pantalla; conservar pedidos pendientes. |
| Código de enlace visible sin sesión administradora | Alto: exposición de la clave compartida | Permiso nativo de administrador; cliente sin clave visible; renovación manual que invalida el enlace anterior y las otras sesiones. |
| Límite de intentos diferenciaba mayúsculas y espacios | Medio: elusión del bloqueo | Normalizar cuenta y limitar por cuenta/origen; longitud acotada y derivación de contraseña también para cuentas inexistentes. |
| Mensajes cifrados sin desafío previo consumible | Medio: repetición de mensajes | Desafío aleatorio de 20 segundos y un solo uso, consumido antes de ejecutar; respuestas ligadas a solicitud e idempotencia transaccional. |
| Servidor local sin acceso propio de la WebView ni validación de Host | Medio: superficie de acceso local | Cookie HttpOnly/SameSite de arranque nativo, Host/Origin/JSON comprobados y CSP sin marcos ni objetos. |
| Un cobro admitía el mismo ID como número y texto | Alto: importe duplicado | Normalizar antes de detectar duplicados; operación atómica frente a cobros simultáneos. |
| Respaldo descifrado con validación insuficiente | Alto: HTML, datos inválidos y colisiones | Validación previa de cuentas, IDs, estados, textos, cantidades, precios y totales; mínimos de secuencia y restauración atómica. |
| Solicitud antigua podía completar un extra cancelado | Medio: inconsistencia de cocina | Exigir extra pendiente y cuenta lista antes de modificar. |
| Cocina mostraba un botón de cobro; administrador usaba una ruta anterior | Funcional | Cocina solo indica entrega; administrador usa diálogo y cobro atómico vigente. |
| JWT del backend conservado mantenía permisos después de modificar la cuenta | Alto si se desplegara ese backend | Token ligado por HMAC a contraseña/rol actuales; consulta de BD en HTTP y conexión Socket.IO; desconexión tras cambios y control de expiración. |
| Release usaba firma de prueba implícita | Distribución | Release exige firma privada. Pruebas con excepción explícita y flujo separado para firma permanente. Falta configurar secretos del propietario. |
| Filtrar por estado o consultar un ID evitaba el permiso de historial | Medio: exposición de cuentas antiguas a meseros/cocina | La restricción también se aplica a filtros, detalle y operaciones sobre cuentas cerradas anteriores al día actual; los pedidos todavía abiertos siguen accesibles. Los eventos consultan el estado actual antes de entregar instantáneas antiguas. |
| Cambiar una cuenta lista de mesa no actualizaba sus extras pendientes | Funcional: cocina podía entregar en la mesa equivocada | Mesa y tipo de entrega de extras se actualizan en la misma transacción que el pedido, con aviso de actualización; se conservan productos y preparación. |
| Un rechazo tardío podía bloquear un pedido después de renovar su sesión | Funcional y sesiones: pedidos retenidos innecesariamente | El rechazo solo cambia la cola si todavía coincide el token enviado y sigue pendiente. Un rechazo 401 de sincronización también invalida el acceso local antiguo. |

## Segunda revisión: 2.3.1

Se agregaron cuatro pruebas de regresión: historial por roles, filtros, IDs y eventos; traslado de extras con rechazo de ediciones antiguas y reversión de cambios inválidos; y renovación de sesión mientras hay un envío pendiente, tanto en primer plano como en segundo plano. La prueba de concurrencia retiene deliberadamente la respuesta antigua, inicia una sesión real nueva y luego libera el rechazo: el pedido debe permanecer pendiente y llegar una sola vez a la central.

El corte del día conserva la regla existente de las 06:00 UTC. La restricción de historial usa la fecha de creación y el estado actual de la cuenta. Los eventos ocultos avanzan el cursor y envían solo la instrucción de retirar el ID de la vista operativa, sin productos, nombres ni importes. No cambia el esquema SQLite ni el protocolo LAN 2.

La validación de esta revisión se registra en GitHub Actions para el commit publicado; no debe confundirse con los resultados de la revisión anterior que se describen abajo.

## Evidencia

La revisión inicial pasó 24 pruebas locales Dart, incluidas 601 órdenes, recuperación de colas y respaldos, y 8 pruebas Node. También pasó una prueba de interfaz real con cuatro accesos y tres servidores de tablet simulados: inyección HTML, pedido, preparación, cobro, cierre de sesión, recarga sin LAN y reenvío único. Esa prueba registró cero errores JavaScript y cero solicitudes externas.

Tras la limpieza del entorno temporal se reconstruyeron las correcciones desde el registro de la revisión y se publicaron en la rama. Las ocho pruebas Node se volvieron a ejecutar satisfactoriamente. La validación definitiva del código publicado corresponde al workflow del último commit: `flutter analyze`, `flutter test` y compilación APK, además del workflow del backend.

`npm audit` reportó cero vulnerabilidades conocidas en 172 dependencias resueltas el 18/09/2026. Esto no equivale a un análisis de todas las dependencias nativas de Android o Dart. Las pruebas de seguridad están en `tres_pisos_app/test/security_regression_test.dart`, `test/frontend.security.test.js` y `test/pedidos.flow.test.js`.

## Límites y tareas de instalación

- Actualizar las tres tablets a la misma versión: LAN 2 no admite la versión anterior. Antes resolver pendientes y guardar y comprobar un respaldo externo.
- Configurar una clave de firma permanente y los cuatro secretos de GitHub de [android-local.md](android-local.md). La conexión usada para subir el código no permite escribir secretos administrativos. Los APK automáticos ordinarios conservan firma de validación. No desinstalar cocina por un conflicto de firma sin respaldo comprobado.
- Probar instalación, actualización, renovación del enlace, reinicio, Wi-Fi, energía y restauración en los dispositivos reales. No se han probado tablets físicas; cocina debe permanecer abierta y alimentada.
- SQLite está en el almacenamiento privado de Android y no usa SQLCipher. AES-GCM protege mensajes LAN y respaldos. El dispositivo debe tener bloqueo de pantalla; no se garantiza protección frente a un sistema rooteado o un equipo desbloqueado.
- Una tablet aislada conoce revocaciones de otra al reconectar; conserva operación limitada y caducidad local. No confirma cobros sin central. Un pedido en cola aún no ha llegado a cocina.
- La clave LAN es compartida y no ofrece secreto hacia adelante. Ante pérdida de un equipo, renovar el enlace y cambiar las credenciales afectadas; esto no borra información previamente copiada.
- Los respaldos importados tienen límite de 64 MB. Las pruebas automáticas no sustituyen capacidad y cobertura en el restaurante.

Los criterios se contrastaron con las guías primarias de [autenticación](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html), [autorización](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html) y [sesiones](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html) de OWASP. Aplicar estos controles no constituye una certificación.
