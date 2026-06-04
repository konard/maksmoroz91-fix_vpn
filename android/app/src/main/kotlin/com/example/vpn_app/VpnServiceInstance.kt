package com.example.vpn_app

import java.lang.ref.WeakReference

object VpnServiceInstance {
    private var ref: WeakReference<AppVpnService>? = null

    fun set(service: AppVpnService) {
        ref = WeakReference(service)
    }

    fun clear() {
        ref = null
    }

    fun get(): AppVpnService? = ref?.get()
}
