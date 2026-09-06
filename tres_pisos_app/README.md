# 3 Pisos POS para Android

Aplicación Flutter conectada al backend Node.js de este repositorio. Incluye:

- inicio de sesión con perfiles `admin`, `mesero` y `cocina`;
- catálogo, carrito, notas, pedidos en mesa y para llevar;
- cola de cocina y actualización de estados en tiempo real;
- cobro y cancelación por mesero;
- administración de usuarios, productos, pedidos y métricas;
- sesión guardada de forma segura en Android.

## Ejecutar en desarrollo

El emulador Android utiliza `http://10.0.2.2:3000` de forma predeterminada:

```bash
flutter pub get
flutter run
```

Para un teléfono físico o para Railway, indica la URL del backend:

```bash
flutter run --dart-define=API_BASE_URL=https://software-restaurant-3-pisos-production.up.railway.app
```

## Generar el APK

```bash
flutter analyze
flutter test
flutter build apk --release --dart-define=API_BASE_URL=https://software-restaurant-3-pisos-production.up.railway.app
```

El archivo resultante queda en:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Cada actualización de la rama `app-android` ejecuta las validaciones y genera un APK conectado a Railway. También puede generarse manualmente desde **Actions → Generar APK Android → Run workflow**; la URL de producción ya aparece como valor predeterminado. El APK queda disponible como artefacto descargable de la ejecución.
