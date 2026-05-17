package com.google.ai.edge.gallery_assistant

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {

    private val channel = "com.lumos/call"
    private var wifiCallback: ConnectivityManager.NetworkCallback? = null
    private var mobileCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "makeCall" -> makeCall(call.argument<String>("phone") ?: "", result)
                    "bindWifiForEsp" -> bindWifiForEsp(result)
                    "bindMobileForInternet" -> bindMobileForInternet(result)
                    "releaseWifiForEsp" -> releaseWifiForEsp(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun makeCall(phone: String, result: MethodChannel.Result) {
        if (phone.isBlank()) {
            result.error("EMPTY_PHONE", "Phone number is empty", null)
            return
        }

        val uri = Uri.parse("tel:$phone")
        try {
            val callIntent = Intent(Intent.ACTION_CALL, uri).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(callIntent)
            result.success("called")
        } catch (se: SecurityException) {
            openDialer(uri, result, "DIAL_FAILED")
        } catch (e: Exception) {
            openDialer(uri, result, "CALL_FAILED")
        }
    }

    private fun openDialer(uri: Uri, result: MethodChannel.Result, errorCode: String) {
        try {
            val dialIntent = Intent(Intent.ACTION_DIAL, uri).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(dialIntent)
            result.success("dialed")
        } catch (e: Exception) {
            result.error(errorCode, e.message, null)
        }
    }

    private fun bindWifiForEsp(result: MethodChannel.Result) {
        Thread {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

                for (network in cm.allNetworks) {
                    val caps = cm.getNetworkCapabilities(network) ?: continue
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                        bindProcess(cm, network)
                        runOnUiThread { result.success("bound_existing_wifi") }
                        return@Thread
                    }
                }

                val latch = CountDownLatch(1)
                var selected: Network? = null
                val request = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .build()
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        selected = network
                        latch.countDown()
                    }
                }

                wifiCallback?.let {
                    try {
                        cm.unregisterNetworkCallback(it)
                    } catch (_: Exception) {
                    }
                }
                wifiCallback = callback
                mobileCallback?.let {
                    try {
                        cm.unregisterNetworkCallback(it)
                    } catch (_: Exception) {
                    }
                }
                mobileCallback = callback
                cm.requestNetwork(request, callback)

                if (latch.await(3, TimeUnit.SECONDS) && selected != null) {
                    bindProcess(cm, selected!!)
                    runOnUiThread { result.success("bound_requested_wifi") }
                } else {
                    runOnUiThread {
                        result.error("NO_WIFI_NETWORK", "No Wi-Fi network available", null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("BIND_WIFI_FAILED", e.message, null) }
            }
        }.start()
    }

    private fun bindMobileForInternet(result: MethodChannel.Result) {
        Thread {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

                for (network in cm.allNetworks) {
                    val caps = cm.getNetworkCapabilities(network) ?: continue
                    if (
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
                        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    ) {
                        bindProcess(cm, network)
                        runOnUiThread { result.success("bound_existing_mobile") }
                        return@Thread
                    }
                }

                val latch = CountDownLatch(1)
                var selected: Network? = null
                val request = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build()
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        selected = network
                        latch.countDown()
                    }
                }

                cm.requestNetwork(request, callback)

                if (latch.await(4, TimeUnit.SECONDS) && selected != null) {
                    bindProcess(cm, selected!!)
                    runOnUiThread { result.success("bound_requested_mobile") }
                } else {
                    bindProcess(cm, null)
                    runOnUiThread {
                        result.error("NO_MOBILE_NETWORK", "No mobile data network available", null)
                    }
                }

            } catch (e: Exception) {
                runOnUiThread { result.error("BIND_MOBILE_FAILED", e.message, null) }
            }
        }.start()
    }

    private fun bindProcess(cm: ConnectivityManager, network: Network?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            cm.bindProcessToNetwork(network)
        } else {
            @Suppress("DEPRECATION")
            ConnectivityManager.setProcessDefaultNetwork(network)
        }
    }

    private fun releaseWifiForEsp(result: MethodChannel.Result) {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm.bindProcessToNetwork(null)
            } else {
                @Suppress("DEPRECATION")
                ConnectivityManager.setProcessDefaultNetwork(null)
            }
            wifiCallback?.let {
                try {
                    cm.unregisterNetworkCallback(it)
                } catch (_: Exception) {
                }
            }
            wifiCallback = null
            result.success("released")
        } catch (e: Exception) {
            result.error("RELEASE_WIFI_FAILED", e.message, null)
        }
    }
}
