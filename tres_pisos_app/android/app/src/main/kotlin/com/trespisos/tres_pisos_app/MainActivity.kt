package com.trespisos.tres_pisos_app

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.wifi.WifiManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import androidx.core.content.FileProvider
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

    private fun enlaceDe(intent: Intent?): String? {
        val datos = intent?.data ?: return null
        return if (intent.action == Intent.ACTION_VIEW && datos.scheme == "trespisos") datos.toString() else null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        canal = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tres_pisos/plataforma")
        canal!!.setMethodCallHandler { llamada, resultado ->
                try {
                    when (llamada.method) {
                        "enlaceInicial" -> {
                            resultado.success(enlacePendiente)
                            enlacePendiente = null
                        }
                        // Escáner de Google Play Services: no pide permiso de cámara. null si se cancela.
                        "escanearQr" -> {
                            val opciones = GmsBarcodeScannerOptions.Builder()
                                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                                .build()
                            GmsBarcodeScanning.getClient(this, opciones).startScan()
                                .addOnSuccessListener { codigo -> resultado.success(codigo.rawValue) }
                                .addOnCanceledListener { resultado.success(null) }
                                .addOnFailureListener { e -> resultado.error("ESCANER", e.message, null) }
                        }
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

    override fun onDestroy() {
        tonos?.release()
        bloqueoMulticast?.release()
        super.onDestroy()
    }
}
