# ML Kit crea sus registradores de componentes por reflexión. Sin esto R8 borra
# los constructores y el escáner de QR falla en release con NoSuchMethodException.
-keep class com.google.mlkit.** { *; }
