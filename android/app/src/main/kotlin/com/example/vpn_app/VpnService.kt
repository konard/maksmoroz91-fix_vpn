package com.example.vpn_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream

class VpnService : VpnService() {
    companion object {
        private const val TAG = "VpnService"
        private const val VIRTUAL_ADDR = "10.0.0.2"
        private const val VIRTUAL_ROUTE = "0.0.0.0"
        private const val DEFAULT_SOCKS_HOST = "127.0.0.1"
        private const val DEFAULT_SOCKS_PORT = 1080
        private const val MTU = 1500
        private const val NOTIF_CHANNEL_ID = "vpn_channel"
        private const val NOTIF_ID = 1
        private var instance: VpnService? = null

        fun getInstance(): VpnService? = instance
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var tun2SocksRunner: Tun2SocksRunner? = null
    private var tunReaderThread: Thread? = null
    private var running = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "CONNECT" -> connect(intent)
            "DISCONNECT" -> disconnect()
        }
        return START_STICKY
    }

    private fun connect(intent: Intent) {
        if (vpnInterface != null) disconnect()

        val telemostRoomUrl = intent.getStringExtra("telemostRoomUrl").orEmpty()
        val vlessHost = intent.getStringExtra("vlessHost").orEmpty()
        val vlessPort = getIntExtra(intent, "vlessPort", 0)
        val socksHost = intent.getStringExtra("socksHost")
            ?.takeIf { it.isNotBlank() }
            ?: DEFAULT_SOCKS_HOST
        val socksPort = getIntExtra(intent, "socksPort", DEFAULT_SOCKS_PORT)

        // For Android 14+ (API 34+) the foreground service type must be declared.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, buildNotification())
        }

        val builder = Builder()
        builder.setSession("WebRTC VPN")
            .addAddress(VIRTUAL_ADDR, 24)
            .addRoute(VIRTUAL_ROUTE, 0)
            .addDisallowedApplication(packageName)
            .setMtu(MTU)

        vpnInterface = builder.establish()
        if (vpnInterface == null) {
            Log.e(TAG, "VPN interface creation failed")
            stopSelf()
            return
        }

        tun2SocksRunner = Tun2SocksRunner(this)
        if (tun2SocksRunner!!.start(vpnInterface!!, socksHost, socksPort, MTU)) {
            Log.i(
                TAG,
                "VPN + tun2socks started room=$telemostRoomUrl " +
                    "vless=$vlessHost:$vlessPort socks=$socksHost:$socksPort",
            )
            return
        }
        tun2SocksRunner = null

        startPacketBridgeReader()
        Log.i(
            TAG,
            "VPN started with Dart packet bridge fallback room=$telemostRoomUrl " +
                "vless=$vlessHost:$vlessPort",
        )
    }

    private fun startPacketBridgeReader() {
        running = true
        tunReaderThread = Thread {
            val input = FileInputStream(vpnInterface!!.fileDescriptor)
            val buffer = ByteArray(MTU)
            while (running) {
                val len = input.read(buffer)
                if (len > 0) {
                    val packet = buffer.copyOf(len)
                    VpnPlugin.sendPacket(packet)
                }
            }
        }.apply { start() }
    }

    private fun disconnect() {
        running = false
        tun2SocksRunner?.stop()
        tun2SocksRunner = null
        tunReaderThread?.interrupt()
        tunReaderThread = null
        vpnInterface?.close()
        vpnInterface = null
        stopForeground(false)
        stopSelf()
        Log.i(TAG, "VPN stopped")
    }

    fun writePacket(packet: ByteArray) {
        vpnInterface?.let {
            try {
                FileOutputStream(it.fileDescriptor).write(packet)
            } catch (e: Exception) {
                Log.e(TAG, "writePacket error", e)
            }
        }
    }

    private fun getIntExtra(intent: Intent, key: String, defaultValue: Int): Int {
        return when (val value = intent.extras?.get(key)) {
            is Int -> value
            is Long -> value.toInt()
            is String -> value.toIntOrNull() ?: defaultValue
            else -> defaultValue
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIF_CHANNEL_ID)
                .setContentTitle("VPN Active")
                .setContentText("Tunnel is running")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentIntent(pi)
                .build()
        } else {
            Notification.Builder(this)
                .setContentTitle("VPN Active")
                .setContentText("Tunnel is running")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentIntent(pi)
                .build()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(NOTIF_CHANNEL_ID, "VPN Service", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
