package com.financas.financas_app

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.service.notification.NotificationListenerService
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Ponte com lib/services/bank_notifications.dart (RN-43).
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "economizze/bank_notifications").apply {
            setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences(BankNotificationListener.PREFS, Context.MODE_PRIVATE)
                when (call.method) {
                    // O APK do site sai sem o serviço (src/sideload/AndroidManifest.xml).
                    "available" -> result.success(
                        packageManager.queryIntentServices(
                            Intent(NotificationListenerService.SERVICE_INTERFACE).setPackage(packageName), 0,
                        ).isNotEmpty(),
                    )
                    "isEnabled" -> result.success(NotificationManagerCompat.getEnabledListenerPackages(this@MainActivity).contains(packageName))
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "setActive" -> {
                        val active = call.arguments as Boolean
                        prefs.edit().putBoolean("active", active).apply()
                        if (!active) BankNotificationListener.write(this@MainActivity, JSONArray())
                        result.success(null)
                    }
                    "pending" -> {
                        val items = BankNotificationListener.read(this@MainActivity)
                        result.success((0 until items.length()).map { i ->
                            val o = items.getJSONObject(i)
                            mapOf("id" to o.getString("id"), "package" to o.getString("package"), "title" to o.optString("title"),
                                "text" to o.optString("text"), "time" to o.getLong("time"))
                        })
                    }
                    "remove" -> {
                        @Suppress("UNCHECKED_CAST") val ids = (call.arguments as List<String>).toSet()
                        synchronized(BankNotificationListener::class.java) {
                            val items = BankNotificationListener.read(this@MainActivity)
                            val kept = JSONArray()
                            for (i in 0 until items.length()) if (items.getJSONObject(i).getString("id") !in ids) kept.put(items.getJSONObject(i))
                            BankNotificationListener.write(this@MainActivity, kept)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // Toque no aviso "gasto detectado" com o app já aberto: avisa o Flutter para abrir a revisão.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getStringExtra("open") == "detected") channel?.invokeMethod("openDetected", null)
    }
}
