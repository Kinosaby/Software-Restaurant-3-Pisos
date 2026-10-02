package com.trespisos.tres_pisos_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Servicio en primer plano de la tablet central (cocina). No hace trabajo propio:
 * el servidor HTTP/WebSocket corre en Dart dentro de la app. Su función es que
 * Android no congele ni mate el proceso cuando la app sale de primer plano
 * (botón Inicio, otra app, pantalla apagada/Doze), y mantener el Wi-Fi y la CPU
 * despiertos para seguir atendiendo a las tablets de los meseros.
 */
class ServicioCentral : Service() {
    private var bloqueoWifi: WifiManager.WifiLock? = null
    private var bloqueoWifiLatencia: WifiManager.WifiLock? = null
    private var bloqueoCpu: PowerManager.WakeLock? = null

    companion object {
        private const val CANAL = "central_cocina"
        private const val ID_NOTIFICACION = 3087

        @Volatile
        var activo = false
            private set

        fun iniciar(contexto: Context) {
            val intento = Intent(contexto, ServicioCentral::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                contexto.startForegroundService(intento)
            } else {
                contexto.startService(intento)
            }
        }

        fun detener(contexto: Context) {
            contexto.stopService(Intent(contexto, ServicioCentral::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        crearCanal()
        val tipo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        ServiceCompat.startForeground(this, ID_NOTIFICACION, notificacion(), tipo)
        adquirirBloqueos()
        activo = true
        // Si Android matara el proceso, no tiene sentido revivir solo el servicio:
        // el servidor vive en Dart y vuelve a arrancar cuando se abre la app.
        return START_NOT_STICKY
    }

    /** Al quitar la app de recientes se destruye el motor de Flutter (y con él el servidor). */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        activo = false
        liberarBloqueos()
        // Sin central, su red propia ya no sirve.
        RedLocal.apagar()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun crearCanal() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val gestor = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (gestor.getNotificationChannel(CANAL) != null) return
        val canal = NotificationChannel(CANAL, "Central de cocina", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Aviso fijo mientras esta tablet atiende a las demás"
            setShowBadge(false)
        }
        gestor.createNotificationChannel(canal)
    }

    private fun notificacion(): Notification {
        val abrir = packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        return NotificationCompat.Builder(this, CANAL)
            // PNG (no el ícono adaptativo, que en Android 8.0 rompe las notificaciones).
            .setSmallIcon(R.mipmap.ic_launcher_foreground)
            .setContentTitle("Central de cocina activa")
            .setContentText("Las tablets de los meseros se conectan a esta. No cierres la app.")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .apply { if (abrir != null) setContentIntent(abrir) }
            .build()
    }

    private fun adquirirBloqueos() {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        // Alto rendimiento: evita que el Wi-Fi entre en ahorro con la pantalla apagada.
        if (bloqueoWifi == null) {
            @Suppress("DEPRECATION")
            val modo = WifiManager.WIFI_MODE_FULL_HIGH_PERF
            bloqueoWifi = wifi.createWifiLock(modo, "tres_pisos:central").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        // Baja latencia (Android 10+): solo actúa con la app al frente y la pantalla encendida.
        if (bloqueoWifiLatencia == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            bloqueoWifiLatencia = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "tres_pisos:central_latencia").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (bloqueoCpu == null) {
            val energia = getSystemService(Context.POWER_SERVICE) as PowerManager
            // Sin tiempo límite a propósito: la central debe atender todo el turno.
            bloqueoCpu = energia.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "tres_pisos:central").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun liberarBloqueos() {
        bloqueoWifi?.let { if (it.isHeld) it.release() }
        bloqueoWifi = null
        bloqueoWifiLatencia?.let { if (it.isHeld) it.release() }
        bloqueoWifiLatencia = null
        bloqueoCpu?.let { if (it.isHeld) it.release() }
        bloqueoCpu = null
    }
}
