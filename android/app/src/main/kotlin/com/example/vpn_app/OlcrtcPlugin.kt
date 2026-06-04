package com.example.vpn_app

import android.content.Context
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.Locale
import java.util.concurrent.Executors

class OlcrtcPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var logChannel: EventChannel
    private val mainExecutor = Executors.newSingleThreadExecutor()
    private var eventSink: EventChannel.EventSink? = null
    private var logWriterProxy: Any? = null
    private var protectorProxy: Any? = null

    companion object {
        private const val TAG = "OlcrtcPlugin"
        private const val DEFAULT_CARRIER = "telemost"
        private const val DEFAULT_SOCKS_PORT = 1080
        private const val DEFAULT_WAIT_READY_MILLIS = 10000
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "olcrtc_channel")
        logChannel = EventChannel(binding.binaryMessenger, "olcrtc_logs")
        methodChannel.setMethodCallHandler(this)
        logChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        logChannel.setStreamHandler(null)
        eventSink = null
        mainExecutor.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDeviceId" -> result.success(getDeviceId())
            "start" -> runNative(result) {
                startNative(call.arguments as? Map<*, *>)
                true
            }
            "stop" -> runNative(result, ignoreMissing = true) {
                stopNative()
                true
            }
            "isRunning" -> runNative(result, ignoreMissing = true) {
                isRunningNative()
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun runNative(
        result: MethodChannel.Result,
        ignoreMissing: Boolean = false,
        block: () -> Any?,
    ) {
        mainExecutor.execute {
            try {
                val value = block()
                MethodChannelResultPoster.success(result, value)
            } catch (e: Throwable) {
                val failure = unwrapInvocation(e)
                if (ignoreMissing && failure is OlcrtcMissingException) {
                    MethodChannelResultPoster.success(result, false)
                } else {
                    MethodChannelResultPoster.error(result, failure)
                }
            }
        }
    }

    private fun getDeviceId(): String {
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID,
        )
        val stableId = androidId
            ?.lowercase(Locale.US)
            ?.filter { it.isLetterOrDigit() }
            ?.takeIf { it.isNotBlank() }
            ?.take(8)
            ?: "unknown"
        return "device-$stableId"
    }

    private fun startNative(arguments: Map<*, *>?) {
        val mobileClass = loadMobileClass()
        configureNativeBridge(mobileClass)

        val carrier = stringArg(arguments, "carrier", "authProvider") ?: DEFAULT_CARRIER
        val roomId = stringArg(
            arguments,
            "roomId",
            "roomID",
            "telemostRoomUrl",
            "telemostRoomId",
        ).orEmpty()
        val clientId = stringArg(arguments, "clientId", "clientID") ?: getDeviceId()
        val key = stringArg(arguments, "key", "keyHex", "olcrtcKey", "cryptoKey").orEmpty()
        val socksPort = intArg(arguments, "socksPort") ?: DEFAULT_SOCKS_PORT
        val socksUser = stringArg(arguments, "socksUser").orEmpty()
        val socksPass = stringArg(arguments, "socksPass").orEmpty()
        val transport = stringArg(arguments, "transport", "transportName")
        val waitReadyMillis =
            intArg(arguments, "waitReadyTimeoutMillis") ?: DEFAULT_WAIT_READY_MILLIS

        stringArg(arguments, "socksHost")?.let {
            invokeOptional(mobileClass, "SetSocksListenHost", it)
        }
        stringArg(arguments, "dns", "dnsServer")?.let { invokeOptional(mobileClass, "SetDNS", it) }
        boolArg(arguments, "debug")?.let { invokeOptional(mobileClass, "SetDebug", it) }

        if (transport.isNullOrBlank()) {
            invokeStart(mobileClass, carrier, roomId, clientId, key, socksPort, socksUser, socksPass)
        } else {
            invokeStartWithTransport(
                mobileClass,
                carrier,
                transport,
                roomId,
                clientId,
                key,
                socksPort,
                socksUser,
                socksPass,
            )
        }

        if (waitReadyMillis > 0) {
            invokeWaitReady(mobileClass, waitReadyMillis)
            emitLog("olcrtc waitReady completed; SOCKS5 ready on :$socksPort")
        }
        emitLog("olcrtc started: carrier=$carrier clientId=$clientId")
    }

    private fun stopNative() {
        val mobileClass = loadMobileClass()
        invokeStatic(mobileClass, listOf("Stop", "stop"), emptyArray())
        emitLog("olcrtc stopped")
    }

    private fun isRunningNative(): Boolean {
        val mobileClass = loadMobileClass()
        return invokeStatic(mobileClass, listOf("IsRunning", "isRunning"), emptyArray()) as? Boolean
            ?: false
    }

    private fun configureNativeBridge(mobileClass: Class<*>) {
        invokeOptional(mobileClass, "SetProviders")
        installLogWriter(mobileClass)
        installSocketProtector(mobileClass)
    }

    private fun installLogWriter(mobileClass: Class<*>) {
        if (logWriterProxy != null) return

        val logWriterInterface = findClass(
            "mobile.LogWriter",
            "go.mobile.LogWriter",
            "mobile.Mobile\$LogWriter",
            "go.mobile.Mobile\$LogWriter",
        ) ?: return

        logWriterProxy = Proxy.newProxyInstance(
            mobileClass.classLoader,
            arrayOf(logWriterInterface),
        ) { _, method, args ->
            if (method.name == "WriteLog" || method.name == "writeLog") {
                val message = args?.firstOrNull()?.toString().orEmpty()
                emitLog(message)
            }
            null
        }
        invokeOptional(mobileClass, "SetLogWriter", logWriterInterface, logWriterProxy!!)
    }

    private fun installSocketProtector(mobileClass: Class<*>) {
        if (protectorProxy != null) return

        val protectorInterface = findClass(
            "mobile.SocketProtector",
            "go.mobile.SocketProtector",
            "mobile.Mobile\$SocketProtector",
            "go.mobile.Mobile\$SocketProtector",
        ) ?: return

        protectorProxy = Proxy.newProxyInstance(
            mobileClass.classLoader,
            arrayOf(protectorInterface),
        ) { _, method, args ->
            if (method.name == "Protect" || method.name == "protect") {
                val fd = (args?.firstOrNull() as? Number)?.toInt()
                if (fd != null) {
                    VpnServiceInstance.get()?.protect(fd) ?: true
                } else {
                    false
                }
            } else {
                false
            }
        }
        invokeOptional(mobileClass, "SetProtector", protectorInterface, protectorProxy!!)
    }

    private fun invokeStart(
        mobileClass: Class<*>,
        carrier: String,
        roomId: String,
        clientId: String,
        key: String,
        socksPort: Int,
        socksUser: String,
        socksPass: String,
    ) {
        invokeWithIntOrLong(
            mobileClass,
            listOf("Start", "start"),
            listOf(carrier, roomId, clientId, key),
            socksPort,
            listOf(socksUser, socksPass),
        )
    }

    private fun invokeStartWithTransport(
        mobileClass: Class<*>,
        carrier: String,
        transport: String,
        roomId: String,
        clientId: String,
        key: String,
        socksPort: Int,
        socksUser: String,
        socksPass: String,
    ) {
        invokeWithIntOrLong(
            mobileClass,
            listOf("StartWithTransport", "startWithTransport"),
            listOf(carrier, transport, roomId, clientId, key),
            socksPort,
            listOf(socksUser, socksPass),
        )
    }

    private fun invokeWaitReady(mobileClass: Class<*>, waitReadyMillis: Int) {
        invokeWithIntOrLong(
            mobileClass,
            listOf("WaitReady", "waitReady"),
            emptyList(),
            waitReadyMillis,
            emptyList(),
        )
    }

    private fun invokeWithIntOrLong(
        mobileClass: Class<*>,
        methodNames: List<String>,
        beforeInt: List<String>,
        intArg: Int,
        afterInt: List<String>,
    ) {
        val stringTypesBefore = Array<Class<*>>(beforeInt.size) { String::class.java }
        val stringTypesAfter = Array<Class<*>>(afterInt.size) { String::class.java }
        val intTypes =
            stringTypesBefore +
                arrayOf<Class<*>>(Int::class.javaPrimitiveType!!) +
                stringTypesAfter
        val intArgs =
            (beforeInt.map { it as Any } + intArg + afterInt.map { it as Any }).toTypedArray()

        try {
            invokeStatic(mobileClass, methodNames, intTypes, intArgs)
            return
        } catch (e: NoSuchMethodException) {
            val longTypes =
                stringTypesBefore +
                    arrayOf<Class<*>>(Long::class.javaPrimitiveType!!) +
                    stringTypesAfter
            val longArgs =
                (beforeInt.map { it as Any } + intArg.toLong() + afterInt.map { it as Any })
                    .toTypedArray()
            invokeStatic(mobileClass, methodNames, longTypes, longArgs)
        }
    }

    private fun invokeOptional(mobileClass: Class<*>, methodName: String) {
        try {
            invokeStatic(
                mobileClass,
                listOf(methodName, methodName.replaceFirstChar { it.lowercase() }),
                emptyArray(),
            )
        } catch (e: NoSuchMethodException) {
            Log.d(TAG, "Optional olcrtc method missing: $methodName")
        }
    }

    private fun invokeOptional(mobileClass: Class<*>, methodName: String, value: String) {
        try {
            invokeStatic(
                mobileClass,
                listOf(methodName, methodName.replaceFirstChar { it.lowercase() }),
                arrayOf<Class<*>>(String::class.java),
                arrayOf<Any>(value),
            )
        } catch (e: NoSuchMethodException) {
            Log.d(TAG, "Optional olcrtc method missing: $methodName")
        }
    }

    private fun invokeOptional(mobileClass: Class<*>, methodName: String, value: Boolean) {
        try {
            invokeStatic(
                mobileClass,
                listOf(methodName, methodName.replaceFirstChar { it.lowercase() }),
                arrayOf<Class<*>>(Boolean::class.javaPrimitiveType!!),
                arrayOf<Any>(value),
            )
        } catch (e: NoSuchMethodException) {
            Log.d(TAG, "Optional olcrtc method missing: $methodName")
        }
    }

    private fun invokeOptional(
        mobileClass: Class<*>,
        methodName: String,
        argType: Class<*>,
        value: Any,
    ) {
        try {
            invokeStatic(
                mobileClass,
                listOf(methodName, methodName.replaceFirstChar { it.lowercase() }),
                arrayOf<Class<*>>(argType),
                arrayOf<Any>(value),
            )
        } catch (e: NoSuchMethodException) {
            Log.d(TAG, "Optional olcrtc method missing: $methodName")
        }
    }

    private fun invokeStatic(
        mobileClass: Class<*>,
        methodNames: List<String>,
        parameterTypes: Array<Class<*>>,
        args: Array<Any> = emptyArray(),
    ): Any? {
        val method = findMethod(mobileClass, methodNames, parameterTypes)
        return invoke(method, args)
    }

    private fun findMethod(
        mobileClass: Class<*>,
        methodNames: List<String>,
        parameterTypes: Array<Class<*>>,
    ): Method {
        for (name in methodNames) {
            try {
                return mobileClass.getMethod(name, *parameterTypes)
            } catch (_: NoSuchMethodException) {
                // Try the next possible gomobile Java name.
            }
        }
        throw NoSuchMethodException("${mobileClass.name}.${methodNames.joinToString("|")}")
    }

    private fun invoke(method: Method, args: Array<Any>): Any? {
        try {
            return method.invoke(null, *args)
        } catch (e: InvocationTargetException) {
            throw unwrapInvocation(e)
        }
    }

    private fun loadMobileClass(): Class<*> {
        return findClass("mobile.Mobile", "go.mobile.Mobile")
            ?: throw OlcrtcMissingException(
                "olcrtc.aar is not packaged. Put the gomobile AAR in android/app/libs/olcrtc.aar.",
            )
    }

    private fun findClass(vararg names: String): Class<*>? {
        for (name in names) {
            try {
                return Class.forName(name)
            } catch (_: ClassNotFoundException) {
                // Try the next possible gomobile Java package.
            }
        }
        return null
    }

    private fun emitLog(message: String) {
        if (message.isBlank()) return

        Log.i(TAG, message)
        MethodChannelResultPoster.post {
            eventSink?.success(message)
        }
    }

    private fun stringArg(arguments: Map<*, *>?, vararg keys: String): String? {
        for (key in keys) {
            val value = arguments?.get(key)
            if (value is String && value.isNotBlank()) return value
        }
        return null
    }

    private fun intArg(arguments: Map<*, *>?, key: String): Int? {
        return when (val value = arguments?.get(key)) {
            is Int -> value
            is Long -> value.toInt()
            is Number -> value.toInt()
            is String -> value.toIntOrNull()
            else -> null
        }
    }

    private fun boolArg(arguments: Map<*, *>?, key: String): Boolean? {
        return when (val value = arguments?.get(key)) {
            is Boolean -> value
            is String -> value.toBooleanStrictOrNull()
            else -> null
        }
    }

    private fun unwrapInvocation(error: Throwable): Throwable {
        var current = error
        while (current is InvocationTargetException && current.targetException != null) {
            current = current.targetException
        }
        return current
    }

    private class OlcrtcMissingException(message: String) : Exception(message)

    private object MethodChannelResultPoster {
        private val handler = android.os.Handler(android.os.Looper.getMainLooper())

        fun success(result: MethodChannel.Result, value: Any?) {
            post { result.success(value) }
        }

        fun error(result: MethodChannel.Result, error: Throwable) {
            val code = if (error is OlcrtcMissingException) "olcrtc_missing" else "olcrtc_error"
            post { result.error(code, error.message ?: error.toString(), null) }
        }

        fun post(block: () -> Unit) {
            handler.post(block)
        }
    }
}
