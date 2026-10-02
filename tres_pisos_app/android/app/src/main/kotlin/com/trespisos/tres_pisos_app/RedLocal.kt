package com.trespisos.tres_pisos_app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
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
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * Red Wi-Fi propia de la central, para trabajar sin router, sin internet y sin datos.
 *
 * - En la tablet central, [crear] levanta una "zona Wi-Fi local" de Android
 *   (LocalOnlyHotspot, Android 8+): no necesita SIM ni datos ni router. Android elige
 *   el nombre y la contraseña cada vez que se crea, y viajan en el QR. Si Android la
 *   apaga, se vuelve a crear sola (con nombre y contraseña nuevos) y se avisa a Flutter.
 * - En la tablet del mesero, [conectar] se une a esa red con los datos del QR
 *   (Android 10+) y hace que la app use esa red (aunque no tenga internet). Si la red
 *   se pierde, reintenta unas veces y, si no vuelve, suelta el enlace y avisa.
 *
 * Todo el estado se toca solo desde el hilo principal: los avisos de Android se piden
 * con [principal] y el canal de Flutter exige ese hilo.
 *
 * Las llamadas a APIs que no existen en Android viejo viven en los objetos `ApiNN`,
 * para que esos equipos ni siquiera carguen esas clases.
 */
object RedLocal {
    private const val TAG = "TresPisos"
    private val principal = Handler(Looper.getMainLooper())

    private const val APAGADA = "apagada"
    private const val CREANDO = "creando"
    private const val ACTIVA = "activa"
    private const val CAIDA = "caida"

    private const val NINGUNA = "ninguna"
    private const val UNIENDO = "uniendo"
    private const val UNIDA = "unida"
    private const val REINTENTANDO = "reintentando"
    private const val PERDIDA = "perdida"

    /** Esperas entre reintentos de crear la red de la central; después se deja de insistir. */
    private val esperasCentral = longArrayOf(2_000, 5_000, 15_000, 30_000, 60_000)

    /** Esperas entre reintentos del mesero: cada intento puede mostrar un aviso de Android. */
    private val esperasMesero = longArrayOf(3_000, 20_000)

    /** Avisa a Flutter de un cambio: (método del canal, estado). Lo pone `MainActivity`. */
    var alCambiar: ((String, Map<String, Any?>) -> Unit)? = null

    /** La actividad está a la vista: Android solo deja crear la red o unirse con la app al frente. */
    private var alFrente = false
    private var app: Context? = null

    // ---------------------------------------------------------------- Central

    /** El usuario quiere trabajar con red propia (aunque ahora mismo esté caída). */
    private var deseada = false
    private var faseCentral = APAGADA
    private var errorCentral: String? = null
    private var codigoCentral: String? = null
    private var reintentoCentral = false
    private var intentosCentral = 0
    private var crearAlVolver = false
    private var activaDesde = 0L

    /** Cambia al apagar: descarta los avisos de una creación anterior. */
    private var generacion = 0

    /** Reserva de la red (LocalOnlyHotspotReservation) y el aviso que la creó. */
    private var reserva: AutoCloseable? = null
    private var duena: Any? = null
    private var datos: Map<String, String>? = null
    private val esperando = ArrayList<(Map<String, String>?, String?, String?) -> Unit>()

    fun puedeCrear(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    fun puedeUnirse(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /**
     * Permisos que pide Android para crear la red. En Android 12 hay que pedir la
     * ubicación precisa junto con la aproximada o el sistema ignora la petición.
     */
    fun permisos(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
        }

    fun tienePermiso(contexto: Context): Boolean {
        val permiso = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.NEARBY_WIFI_DEVICES
        } else {
            Manifest.permission.ACCESS_FINE_LOCATION
        }
        return contexto.checkSelfPermission(permiso) == PackageManager.PERMISSION_GRANTED
    }

    fun estadoCentral(): Map<String, Any?> = mapOf(
        "fase" to faseCentral,
        "ssid" to datos?.get("ssid"),
        "clave" to datos?.get("clave"),
        "seguridad" to datos?.get("seguridad"),
        "error" to errorCentral,
        "codigo" to codigoCentral,
        "reintentando" to (reintentoCentral || crearAlVolver),
    )

    private fun avisarCentral() {
        alCambiar?.invoke("redPropiaCambio", estadoCentral())
    }

    /**
     * Crea la red de la central (o la vuelve a intentar si estaba caída). [listo] recibe
     * los datos de la red, o un código y un mensaje en español. Si ya existe, devuelve la misma.
     * No pide permisos: eso lo hace antes `MainActivity`.
     */
    fun crear(contexto: Context, listo: (Map<String, String>?, String?, String?) -> Unit) {
        if (!puedeCrear()) {
            listo(null, "NO_COMPATIBLE", "Esta tablet (Android 7) no puede crear su propia red Wi-Fi. Usa un router.")
            return
        }
        val aplicacion = contexto.applicationContext
        app = aplicacion
        deseada = true
        datos?.let {
            listo(it, null, null)
            return
        }
        esperando.add(listo)
        if (faseCentral == CREANDO) return
        principal.removeCallbacks(reintentarCentral)
        reintentoCentral = false
        intentosCentral = 0
        if (alFrente) {
            iniciar(aplicacion)
        } else {
            // La app aún no está a la vista (arranque): se crea en cuanto lo esté.
            faseCentral = CREANDO
            errorCentral = null
            codigoCentral = null
            crearAlVolver = true
            avisarCentral()
        }
    }

    private fun iniciar(aplicacion: Context) {
        if (!deseada || reserva != null || !puedeCrear()) return
        crearAlVolver = false
        if (!tienePermiso(aplicacion)) {
            fallarCentral(
                "PERMISO",
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    "Falta el permiso \"Dispositivos cercanos\". Acéptalo cuando Android pregunte; " +
                        "si ya no pregunta, actívalo en Ajustes > Aplicaciones > Tres Pisos > Permisos."
                } else {
                    "Falta el permiso de \"Ubicación\" (precisa). Android lo exige para crear la red Wi-Fi; " +
                        "la app no usa tu ubicación. Acéptalo cuando Android pregunte o actívalo en " +
                        "Ajustes > Aplicaciones > Tres Pisos > Permisos."
                },
                false,
            )
            return
        }
        // Antes de Android 13 la red local exige además la Ubicación del sistema encendida.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && !ubicacionEncendida(aplicacion)) {
            fallarCentral("UBICACION", MENSAJE_UBICACION, false)
            return
        }
        faseCentral = CREANDO
        errorCentral = null
        codigoCentral = null
        avisarCentral()
        try {
            Api26.iniciar(aplicacion, generacion)
        } catch (e: SecurityException) {
            if (!ubicacionEncendida(aplicacion)) {
                fallarCentral("UBICACION", MENSAJE_UBICACION, false)
            } else {
                fallarCentral("PERMISO", "Android no dio permiso para crear la red: revisa los permisos de la app en Ajustes > Aplicaciones > Tres Pisos > Permisos.", false)
            }
            return
        } catch (e: IllegalStateException) {
            // Android aún tiene registrada la petición anterior: se le da tiempo.
            fallarCentral("RED", "Android todavía está cerrando la red anterior.", true)
            return
        } catch (e: Exception) {
            fallarCentral("RED", "No se pudo crear la red: ${e.message}", true)
            return
        }
        principal.removeCallbacks(vigilanteCentral)
        principal.postDelayed(vigilanteCentral, 25_000)
    }

    /** Android no contestó ni que sí ni que no. */
    private val vigilanteCentral = Runnable {
        if (faseCentral == CREANDO && !crearAlVolver) {
            fallarCentral("RED", "Android no respondió al crear la red.", true)
        }
    }

    private val reintentarCentral = Runnable {
        reintentoCentral = false
        val aplicacion = app
        if (aplicacion != null && deseada && reserva == null) iniciar(aplicacion)
    }

    private fun fallarCentral(codigo: String, mensaje: String, reintentable: Boolean) {
        Log.w(TAG, "Red propia: $mensaje")
        principal.removeCallbacks(vigilanteCentral)
        principal.removeCallbacks(reintentarCentral)
        faseCentral = CAIDA
        errorCentral = mensaje
        codigoCentral = codigo
        reintentoCentral = false
        if (reintentable && deseada && intentosCentral < esperasCentral.size) {
            reintentoCentral = true
            principal.postDelayed(reintentarCentral, esperasCentral[intentosCentral])
            intentosCentral++
        }
        val pendientes = ArrayList(esperando)
        esperando.clear()
        avisarCentral()
        for (listo in pendientes) listo(null, codigo, mensaje)
    }

    private fun alIniciar(quien: Any, gen: Int, nueva: AutoCloseable, nuevos: Map<String, String>?) {
        if (gen != generacion || !deseada || reserva != null) {
            // Llegó tarde (ya se apagó o ya hay otra red): no se deja una red huérfana.
            cerrar(nueva)
            return
        }
        if (nuevos == null) {
            cerrar(nueva)
            fallarCentral("RED", "Android creó la red pero no dio su nombre y contraseña.", true)
            return
        }
        principal.removeCallbacks(vigilanteCentral)
        principal.removeCallbacks(reintentarCentral)
        reintentoCentral = false
        crearAlVolver = false
        reserva = nueva
        duena = quien
        datos = nuevos
        activaDesde = SystemClock.elapsedRealtime()
        faseCentral = ACTIVA
        errorCentral = null
        codigoCentral = null
        val pendientes = ArrayList(esperando)
        esperando.clear()
        avisarCentral()
        for (listo in pendientes) listo(nuevos, null, null)
    }

    /** Android apagó la red (por ejemplo, tras un rato sin tablets conectadas). */
    private fun alDetenerse(quien: Any) {
        if (duena !== quien) return
        duena = null
        reserva?.let { cerrar(it) }
        reserva = null
        datos = null
        if (!deseada) return
        // Si duró poco no se reinicia la cuenta: evita crear y perder la red sin parar.
        if (SystemClock.elapsedRealtime() - activaDesde > 60_000) intentosCentral = 0
        fallarCentral("RED", "Android apagó la red Wi-Fi de la central.", true)
    }

    private fun alFallar(gen: Int, mensaje: String, reintentable: Boolean) {
        if (gen != generacion || faseCentral != CREANDO) return
        fallarCentral("RED", mensaje, reintentable)
    }

    fun apagar() {
        deseada = false
        generacion++
        principal.removeCallbacks(vigilanteCentral)
        principal.removeCallbacks(reintentarCentral)
        reintentoCentral = false
        crearAlVolver = false
        reserva?.let { cerrar(it) }
        reserva = null
        duena = null
        datos = null
        val cambio = faseCentral != APAGADA
        faseCentral = APAGADA
        errorCentral = null
        codigoCentral = null
        val pendientes = ArrayList(esperando)
        esperando.clear()
        if (cambio) avisarCentral()
        for (listo in pendientes) listo(null, "RED", "Se apagó la red propia de la central.")
    }

    private fun cerrar(cosa: AutoCloseable) {
        try {
            cosa.close()
        } catch (e: Exception) {
            Log.w(TAG, "No se pudo cerrar la red propia: ${e.message}")
        }
    }

    private const val MENSAJE_UBICACION =
        "Enciende la \"Ubicación\" de la tablet (desliza la barra de arriba y toca Ubicación). " +
            "Android la exige para crear la red Wi-Fi; la app no usa tu ubicación."

    private fun ubicacionEncendida(aplicacion: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            (aplicacion.getSystemService(Context.LOCATION_SERVICE) as LocationManager).isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            val modo = Settings.Secure.getInt(
                aplicacion.contentResolver,
                Settings.Secure.LOCATION_MODE,
                Settings.Secure.LOCATION_MODE_OFF,
            )
            @Suppress("DEPRECATION")
            val apagada = Settings.Secure.LOCATION_MODE_OFF
            modo != apagada
        }
    } catch (e: Exception) {
        // Si no se puede saber, se intenta crear la red y Android dirá.
        true
    }

    // ---------------------------------------------------------------- Mesero

    private class Objetivo(val ssid: String, val clave: String, val seguridad: String)

    private var objetivo: Objetivo? = null
    private var faseMesero = NINGUNA
    private var errorMesero: String? = null
    private var peticion: ConnectivityManager.NetworkCallback? = null
    private var redAtada: Network? = null
    private var respuestaMesero: ((Boolean, String?, String?) -> Unit)? = null
    private var intentosMesero = 0
    private var generacionMesero = 0
    private var unirAlVolver = false

    fun estadoMesero(): Map<String, Any?> = mapOf(
        "fase" to faseMesero,
        "ssid" to objetivo?.ssid,
        "error" to errorMesero,
    )

    private fun avisarMesero() {
        alCambiar?.invoke("redMeseroCambio", estadoMesero())
    }

    /**
     * Tablet del mesero: se une a la red de la central y la usa para la app.
     * Android muestra un aviso para aprobar la conexión.
     */
    fun conectar(contexto: Context, ssid: String, clave: String, seguridad: String, listo: (Boolean, String?, String?) -> Unit) {
        if (!puedeUnirse()) {
            listo(false, "NO_COMPATIBLE", "Esta tablet (Android 9 o anterior) no puede unirse sola: conéctala a la red \"$ssid\" desde Ajustes > Wi-Fi.")
            return
        }
        val aplicacion = contexto.applicationContext
        app = aplicacion
        soltar(aplicacion)
        objetivo = Objetivo(ssid, clave, seguridad)
        intentosMesero = 0
        errorMesero = null
        respuestaMesero = listo
        if (alFrente) {
            pedir(aplicacion, 60_000)
        } else {
            // Android rechaza la petición si la app no está a la vista (arranque): se pide al estarlo.
            faseMesero = UNIENDO
            unirAlVolver = true
            avisarMesero()
        }
    }

    private fun pedir(aplicacion: Context, limite: Int) {
        val destino = objetivo ?: return
        if (!puedeUnirse()) return
        unirAlVolver = false
        generacionMesero++
        faseMesero = if (respuestaMesero != null) UNIENDO else REINTENTANDO
        avisarMesero()
        try {
            peticion = Api29.pedir(aplicacion, destino.ssid, destino.clave, destino.seguridad, generacionMesero, limite)
        } catch (e: Exception) {
            peticion = null
            perder(aplicacion, "No se pudo pedir la conexión a la red de la central: ${e.message}")
        }
    }

    private fun redDisponible(aplicacion: Context, gen: Int, red: Network) {
        if (gen != generacionMesero) return
        // Todo lo que abra la app (HTTP y WebSocket) sale por la red de la central.
        val atada = try {
            conectividad(aplicacion).bindProcessToNetwork(red)
        } catch (e: Exception) {
            false
        }
        if (!atada) {
            dejarPeticion(aplicacion)
            perder(aplicacion, "Android no dejó usar la red de la central. Vuelve a escanear el QR de la central.")
            return
        }
        redAtada = red
        intentosMesero = 0
        faseMesero = UNIDA
        errorMesero = null
        val listo = respuestaMesero
        respuestaMesero = null
        avisarMesero()
        listo?.invoke(true, null, null)
    }

    /** Venció el tiempo, el usuario canceló o Android rechazó la petición (ya la retiró él). */
    private fun redNoDisponible(aplicacion: Context, gen: Int) {
        if (gen != generacionMesero) return
        peticion = null
        if (respuestaMesero != null) {
            val nombre = objetivo?.ssid ?: ""
            perder(aplicacion, "No se encontró la red \"$nombre\" de la central o no se aceptó la conexión. " +
                "Acerca la tablet a la central y vuelve a escanear el QR de la central.")
        } else {
            reintentarMesero(aplicacion)
        }
    }

    private fun redPerdida(aplicacion: Context, gen: Int, red: Network) {
        if (gen != generacionMesero) return
        val atada = redAtada
        if (atada != null && atada != red) return
        // La app no se queda atada a una red que ya no existe.
        desatar(aplicacion)
        dejarPeticion(aplicacion)
        reintentarMesero(aplicacion)
    }

    private fun reintentarMesero(aplicacion: Context) {
        if (objetivo == null) return
        if (intentosMesero >= esperasMesero.size) {
            perder(aplicacion, "Se perdió la red Wi-Fi de la central. Vuelve a escanear el QR de la central.")
            return
        }
        faseMesero = REINTENTANDO
        errorMesero = null
        avisarMesero()
        principal.removeCallbacks(reintentoMesero)
        principal.postDelayed(reintentoMesero, esperasMesero[intentosMesero])
        intentosMesero++
    }

    private val reintentoMesero = Runnable { volverAPedir() }

    private fun volverAPedir() {
        val aplicacion = app ?: return
        if (objetivo == null || faseMesero != REINTENTANDO) return
        if (alFrente) {
            pedir(aplicacion, 30_000)
        } else {
            // Con la pantalla apagada Android rechazaría la petición: se hace al volver.
            unirAlVolver = true
        }
    }

    /** No se pudo (o ya no se insiste): nada queda atado y la interfaz lo dice. */
    private fun perder(aplicacion: Context, mensaje: String) {
        Log.w(TAG, "Red del mesero: $mensaje")
        principal.removeCallbacks(reintentoMesero)
        unirAlVolver = false
        desatar(aplicacion)
        faseMesero = PERDIDA
        errorMesero = mensaje
        val listo = respuestaMesero
        respuestaMesero = null
        avisarMesero()
        listo?.invoke(false, "RED", mensaje)
    }

    /** Deja de usar la red de la central: la app vuelve a la red normal de la tablet. */
    fun desconectar(contexto: Context) {
        val aplicacion = contexto.applicationContext
        soltar(aplicacion)
        objetivo = null
        errorMesero = null
        val cambio = faseMesero != NINGUNA
        faseMesero = NINGUNA
        if (cambio) avisarMesero()
    }

    private fun soltar(aplicacion: Context) {
        generacionMesero++
        principal.removeCallbacks(reintentoMesero)
        unirAlVolver = false
        dejarPeticion(aplicacion)
        desatar(aplicacion)
        val listo = respuestaMesero
        respuestaMesero = null
        listo?.invoke(false, "RED", "Se canceló la conexión anterior.")
    }

    private fun dejarPeticion(aplicacion: Context) {
        val anterior = peticion ?: return
        peticion = null
        try {
            conectividad(aplicacion).unregisterNetworkCallback(anterior)
        } catch (e: Exception) {
            // Android ya la había retirado.
        }
    }

    private fun desatar(aplicacion: Context) {
        redAtada = null
        try {
            conectividad(aplicacion).bindProcessToNetwork(null)
        } catch (e: Exception) {
            Log.w(TAG, "No se pudo soltar la red: ${e.message}")
        }
    }

    private fun conectividad(aplicacion: Context): ConnectivityManager =
        aplicacion.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    // ---------------------------------------------------------- Ciclo de vida

    /** La actividad volvió al frente: se retoma lo que Android no deja hacer en segundo plano. */
    fun alVolver(contexto: Context) {
        alFrente = true
        val aplicacion = contexto.applicationContext
        app = aplicacion
        if (deseada && reserva == null && puedeCrear()) {
            if (crearAlVolver) {
                iniciar(aplicacion)
            } else if (faseCentral == CAIDA && !reintentoCentral) {
                intentosCentral = 0
                iniciar(aplicacion)
            }
        }
        if (unirAlVolver && objetivo != null) {
            pedir(aplicacion, if (respuestaMesero != null) 60_000 else 30_000)
        }
    }

    fun alSalir() {
        alFrente = false
    }

    // ------------------------------------------------- APIs según la versión

    @RequiresApi(Build.VERSION_CODES.O)
    private object Api26 {
        @SuppressLint("MissingPermission")
        fun iniciar(aplicacion: Context, gen: Int) {
            val wifi = aplicacion.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                    val nuevos = try {
                        leer(r)
                    } catch (e: Exception) {
                        null
                    }
                    RedLocal.alIniciar(this, gen, r, nuevos)
                }

                override fun onStopped() {
                    RedLocal.alDetenerse(this)
                }

                override fun onFailed(motivo: Int) {
                    val mensaje = when (motivo) {
                        WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE ->
                            if (RedLocal.alFrente) {
                                "Apaga la \"Zona Wi-Fi\" o \"Conexión compartida\" de la tablet e inténtalo de nuevo."
                            } else {
                                "Abre la app en la tablet central para que vuelva a crear su red."
                            }
                        WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED ->
                            "Esta tablet no permite crear redes Wi-Fi (restricción del sistema)."
                        WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL ->
                            "No hay canal Wi-Fi libre. Apaga y enciende el Wi-Fi de la tablet."
                        else -> "Android no pudo crear la red (código $motivo). Apaga y enciende el Wi-Fi de la tablet."
                    }
                    RedLocal.alFallar(gen, mensaje, motivo != WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED)
                }
            }, RedLocal.principal)
        }

        private fun leer(r: WifiManager.LocalOnlyHotspotReservation): Map<String, String>? {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) return Api30.leer(r)
            @Suppress("DEPRECATION")
            val config = r.wifiConfiguration ?: return null
            @Suppress("DEPRECATION")
            val nombre = config.SSID?.removeSurrounding("\"") ?: return null
            @Suppress("DEPRECATION")
            val clave = config.preSharedKey?.removeSurrounding("\"") ?: return null
            if (nombre.isEmpty() || clave.length < 8) return null
            return mapOf("ssid" to nombre, "clave" to clave, "seguridad" to "wpa2")
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private object Api30 {
        @Suppress("DEPRECATION")
        fun leer(r: WifiManager.LocalOnlyHotspotReservation): Map<String, String>? {
            val config: SoftApConfiguration = r.softApConfiguration
            val moderno = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Api33.nombre(config) else null
            val nombre: String = moderno ?: config.ssid ?: return null
            val clave: String = config.passphrase ?: return null
            if (nombre.isEmpty() || clave.length < 8) return null
            // Solo WPA3 "puro" exige que el mesero se conecte con WPA3; la transición acepta WPA2.
            val seguridad = if (config.securityType == SoftApConfiguration.SECURITY_TYPE_WPA3_SAE) "wpa3" else "wpa2"
            return mapOf("ssid" to nombre, "clave" to clave, "seguridad" to seguridad)
        }
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private object Api33 {
        /** El nombre llega entre comillas si es texto normal; si no, no sirve para el QR. */
        fun nombre(config: SoftApConfiguration): String? {
            val texto = config.wifiSsid?.toString() ?: return null
            return if (texto.length > 2 && texto.startsWith("\"") && texto.endsWith("\"")) {
                texto.substring(1, texto.length - 1)
            } else {
                null
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private object Api29 {
        fun pedir(
            aplicacion: Context,
            ssid: String,
            clave: String,
            seguridad: String,
            gen: Int,
            limite: Int,
        ): ConnectivityManager.NetworkCallback {
            val especificador = WifiNetworkSpecifier.Builder().setSsid(ssid)
            if (seguridad == "wpa3") especificador.setWpa3Passphrase(clave) else especificador.setWpa2Passphrase(clave)
            val solicitud = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(especificador.build())
                .build()
            val llamada = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(red: Network) {
                    RedLocal.redDisponible(aplicacion, gen, red)
                }

                override fun onUnavailable() {
                    RedLocal.redNoDisponible(aplicacion, gen)
                }

                override fun onLost(red: Network) {
                    RedLocal.redPerdida(aplicacion, gen, red)
                }
            }
            // Con `principal`, los avisos llegan en el hilo principal (el del canal de Flutter).
            RedLocal.conectividad(aplicacion).requestNetwork(solicitud, llamada, RedLocal.principal, limite)
            return llamada
        }
    }
}
