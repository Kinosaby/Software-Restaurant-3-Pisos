package com.trespisos.tres_pisos_app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.WindowManager
import android.widget.Toast
import androidx.core.content.FileProvider
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canal "tres_pisos/plataforma": funciones del sistema que la app necesita sin
 * depender de plugins (varios arrastran paquetes que no compilan en rutas con espacios).
 */
class MainActivity : FlutterActivity() {
    private var tonos: ToneGenerator? = null
    private var bloqueoMulticast: WifiManager.MulticastLock? = null

    // Selector de archivos en curso (guardar o abrir un respaldo).
    private var pendiente: MethodChannel.Result? = null
    private var porGuardar: ByteArray? = null

    companion object {
        private const val PEDIR_GUARDAR = 41
        private const val PEDIR_ABRIR = 42
        private const val PEDIR_NOTIFICACIONES = 43
        private const val PEDIR_RED = 44
        private const val LIMITE_ARCHIVO = 64 * 1024 * 1024
    }

    @Deprecated("Se usa startActivityForResult para no depender de androidx.activity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PEDIR_GUARDAR && requestCode != PEDIR_ABRIR) return
        val resultado = pendiente ?: return
        val bytes = porGuardar
        pendiente = null
        porGuardar = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            resultado.success(if (requestCode == PEDIR_GUARDAR) false else null)
            return
        }
        try {
            if (requestCode == PEDIR_GUARDAR) {
                contentResolver.openOutputStream(uri, "wt")!!.use { it.write(bytes!!) }
                resultado.success(true)
            } else {
                val leidos = contentResolver.openInputStream(uri)!!.use { entrada ->
                    val salida = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val n = entrada.read(buffer)
                        if (n < 0) break
                        salida.write(buffer, 0, n)
                        if (salida.size() > LIMITE_ARCHIVO) throw IllegalStateException("Archivo demasiado grande")
                    }
                    salida.toByteArray()
                }
                resultado.success(leidos)
            }
        } catch (e: Exception) {
            resultado.error("ARCHIVO", e.message, null)
        }
    }

    // Enlace trespisos://enlace?… con el que se abrió la app (QR leído con la cámara del sistema).
    private var enlacePendiente: String? = null
    private var canal: MethodChannel? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        enlacePendiente = enlaceDe(intent)
        super.onCreate(savedInstanceState)
    }

    /// La app ya estaba abierta (launchMode singleTop): se avisa a Dart en el momento.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val enlace = enlaceDe(intent) ?: return
        canal?.invokeMethod("enlaceRecibido", enlace) ?: run { enlacePendiente = enlace }
    }

    private var escaneando = false

    /**
     * Escáner de Google Play Services: no pide permiso de cámara. null si se cancela.
     * Errores: "DESCARGANDO" (Google aún no baja el módulo del escáner) o "ESCANER".
     */
    private fun escanearQr(resultado: MethodChannel.Result) {
        // Un segundo toque con el escáner abierto lo rechazaría ML Kit (TASK_IN_PROGRESS).
        if (escaneando) {
            resultado.success(null)
            return
        }
        escaneando = true
        val opciones = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
        GmsBarcodeScanning.getClient(this, opciones).startScan()
            .addOnSuccessListener { codigo ->
                escaneando = false
                resultado.success(codigo.rawValue)
            }
            .addOnCanceledListener {
                escaneando = false
                resultado.success(null)
            }
            .addOnFailureListener { e ->
                escaneando = false
                when ((e as? MlKitException)?.errorCode) {
                    MlKitException.CODE_SCANNER_CANCELLED,
                    MlKitException.CODE_SCANNER_TASK_IN_PROGRESS -> resultado.success(null)
                    MlKitException.UNAVAILABLE,
                    MlKitException.CODE_SCANNER_UNAVAILABLE -> resultado.error("DESCARGANDO", e.message, null)
                    else -> resultado.error("ESCANER", e.message, null)
                }
            }
    }

    private fun enlaceDe(intent: Intent?): String? {
        val datos = intent?.data ?: return null
        return if (intent.action == Intent.ACTION_VIEW && datos.scheme == "trespisos") datos.toString() else null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        canal = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tres_pisos/plataforma")
        RedLocal.alCambiar = avisoDeRed
        canal!!.setMethodCallHandler { llamada, resultado ->
                try {
                    when (llamada.method) {
                        "enlaceInicial" -> {
                            resultado.success(enlacePendiente)
                            enlacePendiente = null
                        }
                        "escanearQr" -> escanearQr(resultado)
                        "sonar" -> {
                            sonar(llamada.argument<String>("tipo") ?: "aviso")
                            resultado.success(null)
                        }
                        "vibrar" -> {
                            vibrar(llamada.argument<List<Int>>("patron") ?: listOf(0, 300))
                            resultado.success(null)
                        }
                        "pantallaEncendida" -> {
                            pantallaEncendida(llamada.argument<Boolean>("activa") ?: false)
                            resultado.success(null)
                        }
                        "compartirImagen" -> {
                            compartirArchivo(
                                llamada.argument<ByteArray>("bytes")!!,
                                llamada.argument<String>("nombre") ?: "ticket.png",
                                "image/png",
                                llamada.argument<String>("texto"),
                            )
                            resultado.success(null)
                        }
                        "compartirArchivo" -> {
                            compartirArchivo(
                                llamada.argument<ByteArray>("bytes")!!,
                                llamada.argument<String>("nombre") ?: "archivo",
                                llamada.argument<String>("tipo") ?: "application/octet-stream",
                                llamada.argument<String>("texto"),
                            )
                            resultado.success(null)
                        }
                        // Guarda donde elija el usuario (Descargas, Drive, USB...). Devuelve false si cancela.
                        "guardarArchivo" -> {
                            if (pendiente != null) {
                                resultado.error("OCUPADO", "Ya hay un selector de archivos abierto", null)
                            } else {
                                porGuardar = llamada.argument<ByteArray>("bytes")!!
                                pendiente = resultado
                                startActivityForResult(
                                    Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                        addCategory(Intent.CATEGORY_OPENABLE)
                                        type = llamada.argument<String>("tipo") ?: "application/octet-stream"
                                        putExtra(Intent.EXTRA_TITLE, llamada.argument<String>("nombre") ?: "archivo")
                                    },
                                    PEDIR_GUARDAR,
                                )
                            }
                        }
                        // Devuelve los bytes del archivo elegido, o null si cancela.
                        "abrirArchivo" -> {
                            if (pendiente != null) {
                                resultado.error("OCUPADO", "Ya hay un selector de archivos abierto", null)
                            } else {
                                pendiente = resultado
                                startActivityForResult(
                                    Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                        addCategory(Intent.CATEGORY_OPENABLE)
                                        type = "*/*"
                                    },
                                    PEDIR_ABRIR,
                                )
                            }
                        }
                        // Almacenamiento privado y persistente (no la caché, que Android puede vaciar).
                        "carpetaDatos" -> resultado.success(filesDir.absolutePath)
                        "multicast" -> {
                            multicast(llamada.argument<Boolean>("activo") ?: false)
                            resultado.success(null)
                        }
                        // Solo la tablet central: mantiene vivo el proceso fuera de primer plano.
                        "servicioCentral" -> {
                            servicioCentral(llamada.argument<Boolean>("activo") ?: false)
                            resultado.success(null)
                        }
                        // Red Wi-Fi propia de la central (sin router, internet ni datos).
                        "redPropia" -> {
                            if (llamada.argument<Boolean>("activa") == true) {
                                crearRedPropia(UnaVez(resultado))
                            } else {
                                RedLocal.apagar()
                                resultado.success(null)
                            }
                        }
                        "redPropiaEstado" -> resultado.success(RedLocal.estadoCentral())
                        // Qué puede hacer esta versión de Android: crear la red (8+) y unirse sola (10+).
                        "redCapacidades" -> resultado.success(
                            mapOf("crear" to RedLocal.puedeCrear(), "unir" to RedLocal.puedeUnirse()),
                        )
                        // Tablet del mesero: unirse a la red propia de la central.
                        "conectarRed" -> {
                            val ssid = llamada.argument<String>("ssid")
                            val clave = llamada.argument<String>("clave")
                            if (ssid == null || clave == null) {
                                resultado.error("RED", "Faltan los datos de la red", null)
                            } else {
                                val respuesta = UnaVez(resultado)
                                RedLocal.conectar(this, ssid, clave, llamada.argument<String>("seguridad") ?: "wpa2") { ok, codigo, error ->
                                    if (ok) respuesta.exito(true) else respuesta.error(codigo ?: "RED", error)
                                }
                            }
                        }
                        "desconectarRed" -> {
                            RedLocal.desconectar(this)
                            resultado.success(null)
                        }
                        "redMeseroEstado" -> resultado.success(RedLocal.estadoMesero())
                        // Pantalla de Ajustes donde se arregla lo que falta: "ubicacion", "wifi" o "app" (permisos).
                        "abrirAjustes" -> {
                            abrirAjustes(llamada.argument<String>("cual") ?: "app")
                            resultado.success(null)
                        }
                        "bateriaSinRestriccion" -> resultado.success(bateriaSinRestriccion())
                        // Diálogo del sistema para excluir la app del ahorro de batería.
                        "pedirSinRestriccionBateria" -> {
                            pedirSinRestriccionBateria()
                            resultado.success(null)
                        }
                        else -> resultado.notImplemented()
                    }
                } catch (e: Exception) {
                    resultado.error("PLATAFORMA", e.message, null)
                }
            }
    }

    private fun sonar(tipo: String) {
        val generador = tonos ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100).also { tonos = it }
        when (tipo) {
            // Dos pitidos largos: entra trabajo a cocina.
            "pedido" -> generador.startTone(ToneGenerator.TONE_PROP_BEEP2, 700)
            // Tono corto y agudo: un pedido está listo para servir.
            "listo" -> generador.startTone(ToneGenerator.TONE_PROP_ACK, 400)
            else -> generador.startTone(ToneGenerator.TONE_PROP_BEEP, 250)
        }
    }

    private fun vibrar(patron: List<Int>) {
        val vibrador: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrador.hasVibrator()) return
        val tiempos = patron.map { it.toLong() }.toLongArray()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrador.vibrate(VibrationEffect.createWaveform(tiempos, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrador.vibrate(tiempos, -1)
        }
    }

    private fun pantallaEncendida(activa: Boolean) {
        runOnUiThread {
            if (activa) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    private fun compartirArchivo(bytes: ByteArray, nombre: String, tipo: String, texto: String?) {
        val carpeta = File(cacheDir, "compartir").apply { mkdirs() }
        val archivo = File(carpeta, nombre.replace(Regex("[^A-Za-z0-9._-]"), "_"))
        archivo.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(this, "$packageName.archivos", archivo)
        val envio = Intent(Intent.ACTION_SEND).apply {
            type = tipo
            putExtra(Intent.EXTRA_STREAM, uri)
            if (texto != null) putExtra(Intent.EXTRA_TEXT, texto)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(envio, "Compartir"))
    }

    /** Android descarta los paquetes UDP de difusión si no se pide este bloqueo. */
    private fun multicast(activo: Boolean) {
        if (activo) {
            if (bloqueoMulticast == null) {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                bloqueoMulticast = wifi.createMulticastLock("tres_pisos_descubrimiento").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } else {
            bloqueoMulticast?.release()
            bloqueoMulticast = null
        }
    }

    private var centralActiva = false

    private fun servicioCentral(activo: Boolean) {
        centralActiva = activo
        if (activo) {
            pedirPermisoNotificaciones()
            try {
                ServicioCentral.iniciar(this)
            } catch (e: Exception) {
                // Android 12+ no deja iniciarlo si la app no está al frente; se reintenta al volver.
                android.util.Log.w("TresPisos", "No se pudo iniciar el servicio de la central: ${e.message}")
            }
        } else {
            ServicioCentral.detener(this)
        }
    }

    override fun onResume() {
        super.onResume()
        // Android solo deja crear la red propia o unirse a ella con la app a la vista.
        RedLocal.alVolver(this)
        if (centralActiva && !ServicioCentral.activo) {
            try {
                ServicioCentral.iniciar(this)
            } catch (e: Exception) {
                android.util.Log.w("TresPisos", "No se pudo reiniciar el servicio de la central: ${e.message}")
            }
        }
    }

    override fun onPause() {
        RedLocal.alSalir()
        super.onPause()
    }

    /** Flutter solo admite una respuesta por llamada: una segunda cerraría la app. */
    private class UnaVez(private val resultado: MethodChannel.Result) {
        private var hecho = false

        fun exito(valor: Any?) {
            if (hecho) return
            hecho = true
            resultado.success(valor)
        }

        fun error(codigo: String, mensaje: String?) {
            if (hecho) return
            hecho = true
            resultado.error(codigo, mensaje, null)
        }
    }

    /** Cambios de la red propia (central) o de la unión a ella (mesero): llegan en el hilo principal. */
    private val avisoDeRed: (String, Map<String, Any?>) -> Unit = { metodo, estado ->
        canal?.invokeMethod(metodo, estado)
    }

    // Acción que espera el permiso de dispositivos cercanos / ubicación para la red propia.
    private var trasPermisoRed: (() -> Unit)? = null

    /**
     * Pide el permiso si falta y crea la red. Si el permiso se niega, `RedLocal.crear`
     * lo detecta y responde con el motivo (y la pantalla de la central lo muestra).
     */
    private fun crearRedPropia(respuesta: UnaVez) {
        val crear: () -> Unit = {
            RedLocal.crear(this) { datos, codigo, error ->
                if (datos != null) respuesta.exito(datos) else respuesta.error(codigo ?: "RED", error)
            }
        }
        if (!RedLocal.puedeCrear() || RedLocal.tienePermiso(this)) {
            crear()
            return
        }
        if (trasPermisoRed != null) {
            respuesta.error("OCUPADO", "Responde primero al permiso que pide Android.")
            return
        }
        trasPermisoRed = crear
        // Se piden todos juntos: Android 12 ignora la ubicación precisa si no va con la aproximada.
        requestPermissions(RedLocal.permisos(), PEDIR_RED)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PEDIR_RED) return
        val accion = trasPermisoRed
        trasPermisoRed = null
        accion?.invoke()
    }

    private fun abrirAjustes(cual: String) {
        val intento = when (cual) {
            "ubicacion" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            "wifi" -> Intent(Settings.ACTION_WIFI_SETTINGS)
            else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        try {
            startActivity(intento)
        } catch (e: Exception) {
            // Algunas marcas no traen esa pantalla: se abren los ajustes generales.
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS))
            } catch (e2: Exception) {
                android.util.Log.w("TresPisos", "No se pudieron abrir los ajustes: ${e2.message}")
            }
        }
    }

    /** Android 13+: sin este permiso el servicio funciona, pero su aviso fijo no se ve. */
    private fun pedirPermisoNotificaciones() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PEDIR_NOTIFICACIONES)
    }

    private fun bateriaSinRestriccion(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val energia = getSystemService(Context.POWER_SERVICE) as PowerManager
        return energia.isIgnoringBatteryOptimizations(packageName)
    }

    @SuppressLint("BatteryLife")
    private fun pedirSinRestriccionBateria() {
        if (bateriaSinRestriccion()) return
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")),
            )
        } catch (e: Exception) {
            // Algunas marcas no traen ese diálogo: se abre la lista general de optimización.
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    /**
     * Flutter llama aquí cuando se pulsa Atrás sin pantallas que cerrar. En la central
     * no se cierra la actividad (eso destruiría el motor de Flutter y el servidor):
     * la app solo pasa a segundo plano, como con el botón Inicio.
     */
    override fun popSystemNavigator(): Boolean {
        if (!centralActiva) return false
        moveTaskToBack(true)
        Toast.makeText(this, "La central sigue activa en segundo plano", Toast.LENGTH_SHORT).show()
        return true
    }

    override fun onDestroy() {
        tonos?.release()
        bloqueoMulticast?.release()
        if (RedLocal.alCambiar === avisoDeRed) RedLocal.alCambiar = null
        // Si la actividad se cierra de verdad, el motor de Flutter (y el servidor) se va con ella.
        if (isFinishing) {
            ServicioCentral.detener(this)
            // Mesero: al cerrar la app la tablet deja la red de la central y nada queda atado.
            RedLocal.desconectar(this)
        }
        super.onDestroy()
    }
}
