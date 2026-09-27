package com.trespisos.tres_pisos_app

import android.Manifest
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.SoftApConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Red Wi-Fi propia de la central, para trabajar sin router, sin internet y sin datos.
 *
 * - En la tablet central, [crear] levanta una "zona Wi-Fi local" de Android
 *   (LocalOnlyHotspot): no necesita SIM ni datos ni router. Android elige el
 *   nombre y la contraseña cada vez que se crea, y viajan en el QR.
 * - En la tablet del mesero, [conectar] se une a esa red con los datos del QR y
 *   hace que la app use esa red (aunque no tenga internet).
 */
object RedLocal {
    private val principal = Handler(Looper.getMainLooper())

    // Central
    private var reserva: WifiManager.LocalOnlyHotspotReservation? = null
    private var datos: Map<String, String>? = null

    // Mesero
    private var peticion: ConnectivityManager.NetworkCallback? = null

    /** Permiso que pide Android para crear la red o conectarse a ella. */
    fun permisos(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    /** Datos de la red ya creada (nombre, clave, seguridad) o `null`. */
    fun actual(): Map<String, String>? = datos

    /**
     * Crea la red de la central. [listo] recibe los datos de la red o un mensaje de
     * error en español. Si ya existe, devuelve la misma.
     */
    fun crear(contexto: Context, listo: (Map<String, String>?, String?) -> Unit) {
        datos?.let {
            listo(it, null)
            return
        }
        val wifi = contexto.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                    reserva = r
                    val nuevos = leer(r)
                    if (nuevos == null) {
                        r.close()
                        reserva = null
                        listo(null, "Android creó la red pero no dio su nombre y contraseña.")
                        return
                    }
                    datos = nuevos
                    listo(nuevos, null)
                }

                override fun onStopped() {
                    reserva = null
                    datos = null
                }

                override fun onFailed(motivo: Int) {
                    reserva = null
                    datos = null
                    listo(null, when (motivo) {
                        ERROR_INCOMPATIBLE_MODE ->
                            "Apaga la \"Zona Wi-Fi\" o \"Anclaje\" de la tablet e inténtalo de nuevo."
                        ERROR_TETHERING_DISALLOWED ->
                            "Esta tablet no permite crear redes Wi-Fi (restricción del sistema)."
                        ERROR_NO_CHANNEL ->
                            "No hay canal Wi-Fi libre. Apaga y enciende el Wi-Fi e inténtalo de nuevo."
                        else -> "No se pudo crear la red (código $motivo). Enciende el Wi-Fi e inténtalo de nuevo."
                    })
                }
            }, principal)
        } catch (e: SecurityException) {
            listo(null, "Falta el permiso de dispositivos cercanos o la ubicación está apagada.")
        } catch (e: IllegalStateException) {
            listo(null, "La red de la central ya se estaba creando. Espera unos segundos.")
        }
    }

    fun apagar() {
        reserva?.close()
        reserva = null
        datos = null
    }

    private fun leer(r: WifiManager.LocalOnlyHotspotReservation): Map<String, String>? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = r.softApConfiguration
            val nombre = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                config.wifiSsid?.toString()?.removeSurrounding("\"")
            } else {
                @Suppress("DEPRECATION")
                config.ssid
            } ?: return null
            val clave = config.passphrase ?: return null
            // Solo WPA3 "puro" exige que el mesero se conecte con WPA3; la transición acepta WPA2.
            val seguridad = if (config.securityType == SoftApConfiguration.SECURITY_TYPE_WPA3_SAE) "wpa3" else "wpa2"
            return mapOf("ssid" to nombre, "clave" to clave, "seguridad" to seguridad)
        }
        @Suppress("DEPRECATION")
        val config = r.wifiConfiguration ?: return null
        @Suppress("DEPRECATION")
        val nombre = config.SSID?.removeSurrounding("\"") ?: return null
        @Suppress("DEPRECATION")
        val clave = config.preSharedKey?.removeSurrounding("\"") ?: return null
        return mapOf("ssid" to nombre, "clave" to clave, "seguridad" to "wpa2")
    }

    /**
     * Tablet del mesero: se une a la red de la central y la usa para la app.
     * Android muestra una vez un aviso para aprobar la conexión.
     */
    fun conectar(contexto: Context, ssid: String, clave: String, seguridad: String, listo: (Boolean, String?) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            listo(false, "Esta tablet (Android 9 o anterior) no puede unirse sola: conéctala a la red \"$ssid\" desde Ajustes > Wi-Fi.")
            return
        }
        val conectividad = contexto.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        desconectar(contexto)
        val especificador = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
            if (seguridad == "wpa3") setWpa3Passphrase(clave) else setWpa2Passphrase(clave)
        }.build()
        val solicitud = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(especificador)
            .build()
        var respondido = false
        val llamada = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(red: Network) {
                // Todo lo que abra la app (HTTP y WebSocket) sale por la red de la central.
                conectividad.bindProcessToNetwork(red)
                if (!respondido) {
                    respondido = true
                    principal.post { listo(true, null) }
                }
            }

            override fun onUnavailable() {
                if (!respondido) {
                    respondido = true
                    principal.post { listo(false, "No se encontró la red \"$ssid\". Revisa que la central esté encendida y cerca.") }
                }
            }

            override fun onLost(red: Network) {
                conectividad.bindProcessToNetwork(null)
            }
        }
        peticion = llamada
        try {
            conectividad.requestNetwork(solicitud, llamada, 60_000)
        } catch (e: Exception) {
            peticion = null
            listo(false, "No se pudo pedir la conexión: ${e.message}")
        }
    }

    fun desconectar(contexto: Context) {
        val conectividad = contexto.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        peticion?.let {
            try {
                conectividad.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        peticion = null
        conectividad.bindProcessToNetwork(null)
    }
}
