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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tres_pisos/plataforma")
            .setMethodCallHandler { llamada, resultado ->
                try {
                    when (llamada.method) {
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
                            compartirImagen(
                                llamada.argument<ByteArray>("bytes")!!,
                                llamada.argument<String>("nombre") ?: "ticket.png",
                                llamada.argument<String>("texto"),
                            )
                            resultado.success(null)
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

    private fun compartirImagen(bytes: ByteArray, nombre: String, texto: String?) {
        val carpeta = File(cacheDir, "compartir").apply { mkdirs() }
        val archivo = File(carpeta, nombre.replace(Regex("[^A-Za-z0-9._-]"), "_"))
        archivo.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(this, "$packageName.archivos", archivo)
        val envio = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            if (texto != null) putExtra(Intent.EXTRA_TEXT, texto)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(envio, "Compartir ticket"))
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
