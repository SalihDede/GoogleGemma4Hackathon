package com.google.ai.edge.gallery_assistant

import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "com.lumos/call"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                if (call.method == "makeCall") {
                    val phone = call.argument<String>("phone") ?: ""
                    if (phone.isBlank()) {
                        result.error("EMPTY_PHONE", "Telefon numarası boş", null)
                        return@setMethodCallHandler
                    }
                    val uri = Uri.parse("tel:$phone")

                    // Önce ACTION_CALL dene (CALL_PHONE izni varsa direkt arar).
                    // Yoksa ACTION_DIAL'a düş — dialer açılır, numara önyüklü gelir.
                    try {
                        val callIntent = Intent(Intent.ACTION_CALL, uri).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(callIntent)
                        result.success("called")
                    } catch (se: SecurityException) {
                        try {
                            val dialIntent = Intent(Intent.ACTION_DIAL, uri).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(dialIntent)
                            result.success("dialed")
                        } catch (e: Exception) {
                            result.error("DIAL_FAILED", e.message, null)
                        }
                    } catch (e: Exception) {
                        // ActivityNotFoundException vs. — yine dialer'a düş
                        try {
                            val dialIntent = Intent(Intent.ACTION_DIAL, uri).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(dialIntent)
                            result.success("dialed")
                        } catch (e2: Exception) {
                            result.error("CALL_FAILED", e2.message, null)
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
