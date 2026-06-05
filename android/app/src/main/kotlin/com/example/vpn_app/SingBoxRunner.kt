package com.example.vpn_app

import android.content.Context
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.lang.reflect.InvocationHandler
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.lang.reflect.Proxy

class SingBoxRunner(private val context: Context) {
    data class Config(
        val vlessHost: String,
        val vlessPort: Int,
        val vlessUserId: String,
        val realityPublicKey: String,
        val realityServerName: String,
        val realityShortId: String,
        val vlessFlow: String,
        val socksHost: String,
        val socksPort: Int,
        val mtu: Int,
    ) {
        fun hasVlessOutbound(): Boolean {
            return vlessHost.isNotBlank() &&
                vlessPort in 1..65535 &&
                vlessUserId.isNotBlank() &&
                realityPublicKey.isNotBlank()
        }
    }

    private data class LibboxClasses(
        val libboxClass: Class<*>,
        val setupOptionsClass: Class<*>,
        val commandServerClass: Class<*>,
        val commandServerHandlerClass: Class<*>,
        val platformInterfaceClass: Class<*>,
        val overrideOptionsClass: Class<*>,
    )

    companion object {
        private const val TAG = "SingBoxRunner"
        private const val DEFAULT_SOCKS_HOST = "127.0.0.1"
        private const val DEFAULT_SOCKS_PORT = 1080
        private const val TUN_TAG = "tun-in"
        private const val VLESS_TAG = "vless-out"
        private const val SOCKS_TAG = "socks-out"
        private const val DIRECT_TAG = "direct"

        @Volatile
        private var libboxSetupDone = false
    }

    private var commandServer: Any? = null
    private var handlerProxy: Any? = null
    private var platformProxy: Any? = null

    fun start(tunFd: ParcelFileDescriptor, config: Config): Boolean {
        if (commandServer != null) stop()

        val workingDir = File(context.filesDir, "sing-box").apply { mkdirs() }
        val tempDir = File(context.cacheDir, "sing-box").apply { mkdirs() }
        val configContent = buildConfig(config)
        File(workingDir, "config.json").writeText(configContent)

        return try {
            val classes = loadLibboxClasses()
            setupLibbox(classes, workingDir, tempDir)

            val handler = newCommandServerHandler(classes.commandServerHandlerClass)
            val platform = newPlatformInterface(classes.platformInterfaceClass, tunFd)
            val server = newCommandServer(classes, handler, platform)

            handlerProxy = handler
            platformProxy = platform
            commandServer = server

            invokeNoArgs(server, "start")
            invoke(
                server,
                "startOrReloadService",
                arrayOf<Class<*>>(String::class.java, classes.overrideOptionsClass),
                arrayOf<Any?>(
                    configContent,
                    classes.overrideOptionsClass.getDeclaredConstructor().newInstance(),
                ),
            )

            Log.i(TAG, "sing-box started successfully")
            true
        } catch (e: ClassNotFoundException) {
            Log.e(
                TAG,
                "libbox.aar is missing. Add sing-box libbox.aar to android/app/libs.",
                e,
            )
            false
        } catch (e: Throwable) {
            val failure = unwrapInvocation(e)
            Log.e(TAG, "Failed to start sing-box", failure)
            stop()
            false
        }
    }

    fun stop() {
        val server = commandServer
        commandServer = null
        handlerProxy = null
        platformProxy = null

        if (server != null) {
            runCatching { invokeNoArgs(server, "closeService") }
                .onFailure { Log.w(TAG, "close sing-box service", unwrapInvocation(it)) }
            runCatching { invokeNoArgs(server, "close") }
                .onFailure { Log.w(TAG, "close sing-box command server", unwrapInvocation(it)) }
        }
        Log.i(TAG, "sing-box stopped")
    }

    private fun loadLibboxClasses(): LibboxClasses {
        val loader = context.classLoader
        return LibboxClasses(
            libboxClass = Class.forName("io.nekohasekai.libbox.Libbox", true, loader),
            setupOptionsClass = Class.forName(
                "io.nekohasekai.libbox.SetupOptions",
                true,
                loader,
            ),
            commandServerClass = Class.forName(
                "io.nekohasekai.libbox.CommandServer",
                true,
                loader,
            ),
            commandServerHandlerClass = Class.forName(
                "io.nekohasekai.libbox.CommandServerHandler",
                true,
                loader,
            ),
            platformInterfaceClass = Class.forName(
                "io.nekohasekai.libbox.PlatformInterface",
                true,
                loader,
            ),
            overrideOptionsClass = Class.forName(
                "io.nekohasekai.libbox.OverrideOptions",
                true,
                loader,
            ),
        )
    }

    private fun setupLibbox(classes: LibboxClasses, workingDir: File, tempDir: File) {
        synchronized(SingBoxRunner::class.java) {
            val options = classes.setupOptionsClass.getDeclaredConstructor().newInstance()
            setOption(options, "setBasePath", String::class.java, context.filesDir.path)
            setOption(options, "setWorkingPath", String::class.java, workingDir.path)
            setOption(options, "setTempPath", String::class.java, tempDir.path)
            setOption(options, "setFixAndroidStack", java.lang.Boolean.TYPE, true)
            setOption(options, "setLogMaxLines", java.lang.Long.TYPE, 3000L)
            setOption(options, "setDebug", java.lang.Boolean.TYPE, BuildConfig.DEBUG)
            setOption(options, "setCrashReportSource", String::class.java, "vpn_app")

            if (libboxSetupDone) {
                runCatching {
                    invoke(
                        classes.libboxClass,
                        "reloadSetupOptions",
                        arrayOf<Class<*>>(classes.setupOptionsClass),
                        arrayOf<Any?>(options),
                    )
                }.onFailure {
                    Log.d(TAG, "reloadSetupOptions unavailable: ${unwrapInvocation(it).message}")
                }
            } else {
                invoke(
                    classes.libboxClass,
                    "setup",
                    arrayOf<Class<*>>(classes.setupOptionsClass),
                    arrayOf<Any?>(options),
                )
                libboxSetupDone = true
            }
        }
    }

    private fun setOption(target: Any, setter: String, type: Class<*>, value: Any) {
        runCatching {
            target.javaClass.getMethod(setter, type).invoke(target, value)
        }.onFailure {
            Log.d(TAG, "SetupOptions.$setter unavailable: ${unwrapInvocation(it).message}")
        }
    }

    private fun newCommandServer(classes: LibboxClasses, handler: Any, platform: Any): Any {
        return try {
            invoke(
                classes.libboxClass,
                "newCommandServer",
                arrayOf<Class<*>>(
                    classes.commandServerHandlerClass,
                    classes.platformInterfaceClass,
                ),
                arrayOf<Any?>(handler, platform),
            ) ?: error("newCommandServer returned null")
        } catch (e: NoSuchMethodException) {
            classes.commandServerClass
                .getConstructor(classes.commandServerHandlerClass, classes.platformInterfaceClass)
                .newInstance(handler, platform)
        }
    }

    private fun newCommandServerHandler(handlerClass: Class<*>): Any {
        return Proxy.newProxyInstance(
            handlerClass.classLoader,
            arrayOf(handlerClass),
            CommandServerHandlerProxy(),
        )
    }

    private fun newPlatformInterface(
        platformInterfaceClass: Class<*>,
        tunFd: ParcelFileDescriptor,
    ): Any {
        return Proxy.newProxyInstance(
            platformInterfaceClass.classLoader,
            arrayOf(platformInterfaceClass),
            PlatformInterfaceProxy(tunFd),
        )
    }

    private inner class CommandServerHandlerProxy : InvocationHandler {
        override fun invoke(proxy: Any, method: Method, args: Array<Any?>?): Any? {
            handleObjectMethod(proxy, method, args)?.let { return it }
            return when (method.name) {
                "serviceStop" -> {
                    Log.i(TAG, "sing-box requested service stop")
                    null
                }
                "serviceReload" -> {
                    Log.i(TAG, "sing-box requested service reload")
                    null
                }
                "writeDebugMessage" -> {
                    Log.d("sing-box", args?.firstOrNull()?.toString().orEmpty())
                    null
                }
                "triggerNativeCrash" -> throw RuntimeException("sing-box requested native crash")
                "connectSSHAgent" -> -1
                "getSystemProxyStatus" -> null
                "setSystemProxyEnabled" -> null
                else -> defaultReturn(method.returnType)
            }
        }
    }

    private inner class PlatformInterfaceProxy(
        private val tunFd: ParcelFileDescriptor,
    ) : InvocationHandler {
        override fun invoke(proxy: Any, method: Method, args: Array<Any?>?): Any? {
            handleObjectMethod(proxy, method, args)?.let { return it }
            return when (method.name) {
                "openTun" -> duplicateTunFd()
                "autoDetectInterfaceControl" -> {
                    val fd = (args?.firstOrNull() as? Number)?.toInt()
                    if (fd != null) {
                        VpnServiceInstance.get()?.protect(fd)
                    }
                    null
                }
                "usePlatformAutoDetectInterfaceControl" -> true
                "useProcFS" -> Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
                "underNetworkExtension",
                "includeAllNetworks",
                "usePlatformShell" -> false
                "clearDNSCache",
                "startDefaultInterfaceMonitor",
                "closeDefaultInterfaceMonitor",
                "startNeighborMonitor",
                "closeNeighborMonitor",
                "registerMyInterface",
                "checkPlatformShell",
                "sendNotification" -> null
                "systemCertificates",
                "getInterfaces" -> emptyIterator(method.returnType)
                "readWIFIState",
                "localDNSTransport",
                "findConnectionOwner",
                "lookupUser",
                "openShellSession" -> null
                "readSystemSSHHostKey",
                "lookupSFTPServer",
                "tailscaleHostname" -> ""
                else -> defaultReturn(method.returnType)
            }
        }

        private fun duplicateTunFd(): Int {
            val duplicate = ParcelFileDescriptor.dup(tunFd.fileDescriptor)
            return duplicate.detachFd()
        }
    }

    private fun emptyIterator(iteratorClass: Class<*>): Any {
        return Proxy.newProxyInstance(
            iteratorClass.classLoader,
            arrayOf(iteratorClass),
        ) { _, method, _ ->
            when (method.name) {
                "len" -> 0
                "hasNext" -> false
                "next" -> throw NoSuchElementException()
                else -> defaultReturn(method.returnType)
            }
        }
    }

    private fun buildConfig(config: Config): String {
        val outbound = if (config.hasVlessOutbound()) {
            buildVlessOutbound(config)
        } else {
            buildSocksOutbound(config)
        }

        return JSONObject()
            .put(
                "log",
                JSONObject()
                    .put("level", "info")
                    .put("timestamp", true),
            )
            .put(
                "dns",
                JSONObject()
                    .put(
                        "servers",
                        JSONArray().put(
                            JSONObject()
                                .put("tag", "dns-direct")
                                .put("address", "8.8.8.8"),
                        ),
                    )
                    .put("final", "dns-direct"),
            )
            .put(
                "inbounds",
                JSONArray().put(
                    JSONObject()
                        .put("type", "tun")
                        .put("tag", TUN_TAG)
                        .put("interface_name", "tun0")
                        .put("address", JSONArray().put("10.0.0.2/30"))
                        .put("mtu", config.mtu)
                        .put("auto_route", false)
                        .put("strict_route", false)
                        .put("stack", "system")
                        .put("sniff", true),
                ),
            )
            .put(
                "outbounds",
                JSONArray()
                    .put(outbound)
                    .put(
                        JSONObject()
                            .put("type", "direct")
                            .put("tag", DIRECT_TAG),
                    ),
            )
            .put(
                "route",
                JSONObject()
                    .put(
                        "rules",
                        JSONArray().put(
                            JSONObject()
                                .put("protocol", "dns")
                                .put("action", "hijack-dns"),
                        ),
                    )
                    .put("final", outbound.getString("tag")),
            )
            .toString(2)
    }

    private fun buildVlessOutbound(config: Config): JSONObject {
        val tls = JSONObject()
            .put("enabled", true)
            .put("server_name", config.realityServerName.ifBlank { config.vlessHost })
            .put(
                "utls",
                JSONObject()
                    .put("enabled", true)
                    .put("fingerprint", "chrome"),
            )
            .put(
                "reality",
                JSONObject()
                    .put("enabled", true)
                    .put("public_key", config.realityPublicKey)
                    .put("short_id", config.realityShortId),
            )

        return JSONObject()
            .put("type", "vless")
            .put("tag", VLESS_TAG)
            .put("server", config.vlessHost)
            .put("server_port", config.vlessPort)
            .put("uuid", config.vlessUserId)
            .put("network", "tcp")
            .put("tls", tls)
            .apply {
                if (config.vlessFlow.isNotBlank()) {
                    put("flow", config.vlessFlow)
                }
            }
    }

    private fun buildSocksOutbound(config: Config): JSONObject {
        val host = config.socksHost.takeIf { it.isNotBlank() } ?: DEFAULT_SOCKS_HOST
        val port = config.socksPort.takeIf { it in 1..65535 } ?: DEFAULT_SOCKS_PORT
        return JSONObject()
            .put("type", "socks")
            .put("tag", SOCKS_TAG)
            .put("server", host)
            .put("server_port", port)
            .put("version", "5")
    }

    private fun invokeNoArgs(target: Any, methodName: String): Any? {
        return invoke(target, methodName, emptyArray<Class<*>>(), emptyArray<Any?>())
    }

    private fun invoke(
        target: Any,
        methodName: String,
        parameterTypes: Array<Class<*>>,
        args: Array<Any?>,
    ): Any? {
        val method = if (target is Class<*>) {
            target.getMethod(methodName, *parameterTypes)
        } else {
            target.javaClass.getMethod(methodName, *parameterTypes)
        }
        return method.invoke(if (target is Class<*>) null else target, *args)
    }

    private fun handleObjectMethod(proxy: Any, method: Method, args: Array<Any?>?): Any? {
        return when (method.name) {
            "toString" -> "${javaClass.simpleName}@${System.identityHashCode(proxy)}"
            "hashCode" -> System.identityHashCode(proxy)
            "equals" -> proxy === args?.firstOrNull()
            else -> null
        }.takeIf { method.declaringClass == Any::class.java }
    }

    private fun defaultReturn(returnType: Class<*>): Any? {
        return when (returnType) {
            java.lang.Boolean.TYPE -> false
            java.lang.Byte.TYPE -> 0.toByte()
            java.lang.Character.TYPE -> 0.toChar()
            java.lang.Double.TYPE -> 0.0
            java.lang.Float.TYPE -> 0f
            java.lang.Integer.TYPE -> 0
            java.lang.Long.TYPE -> 0L
            java.lang.Short.TYPE -> 0.toShort()
            java.lang.Void.TYPE -> null
            else -> null
        }
    }

    private fun unwrapInvocation(error: Throwable): Throwable {
        return if (error is InvocationTargetException && error.targetException != null) {
            error.targetException
        } else {
            error
        }
    }
}
