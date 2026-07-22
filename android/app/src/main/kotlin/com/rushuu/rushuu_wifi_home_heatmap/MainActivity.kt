package com.rushuu.rushuu_wifi_home_heatmap

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "rushuu_wifi_home_heatmap/wifi"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSignalInfo" -> result.success(getSignalInfo())
                else -> result.notImplemented()
            }
        }
    }

    private fun getSignalInfo(): Map<String, Any?> {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val info = wifiManager.connectionInfo
        val rssi = info?.rssi
        val ssid = info?.ssid?.removeSurrounding("\"")

        if (info == null || rssi == null || rssi == -127) {
            return mapOf("connected" to false)
        }

        return mapOf(
            "connected" to true,
            "ssid" to ssid,
            "rssiDbm" to rssi,
        )
    }
}
