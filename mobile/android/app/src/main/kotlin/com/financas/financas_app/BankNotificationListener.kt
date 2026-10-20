package com.financas.financas_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * Recebe do Android as notificações do celular e guarda só as dos apps de banco que falam de
 * dinheiro (RN-43). Nada sai do aparelho aqui: o app lê a fila quando é aberto e o usuário revisa.
 * As de outros apps (WhatsApp, e-mail...) são ignoradas na hora, sem guardar nada.
 */
class BankNotificationListener : NotificationListenerService() {
    companion object {
        // Mesma lista de lib/services/bank_notifications.dart.
        val BANKS = setOf(
            "com.nu.production", "br.com.intermedium", "com.itau", "br.com.bb.android", "com.bradesco",
            "br.com.bradesco.next", "br.com.gabba.Caixa", "com.santander.app", "com.c6bank.app", "com.picpay",
            "com.mercadopago.wallet", "br.com.uol.ps.myaccount",
        )
        const val PREFS = "economizze_bank_notifications"
        private const val MAX_ITEMS = 200
        private const val MAX_AGE_MS = 45L * 24 * 60 * 60 * 1000
        private const val CHANNEL = "gastos_detectados"
        private const val NOTIFICATION_ID = 2000

        fun read(context: Context): JSONArray =
            JSONArray(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("items", "[]"))

        fun write(context: Context, items: JSONArray) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("items", items.toString()).apply()
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in BANKS) return
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("active", false)) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
        if (!"$title $text".contains("R$")) return
        // Notificação de resumo de grupo repete o texto das outras.
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        // O mesmo texto pode ser repostado (atualização da notificação): uma entrada só.
        val id = "${sbn.packageName}:${"$title|$text".hashCode().toUInt().toString(16)}:${sbn.postTime / 60000}"
        synchronized(BankNotificationListener::class.java) {
            val now = System.currentTimeMillis()
            val old = read(this)
            val items = JSONArray()
            for (i in 0 until old.length()) {
                val item = old.getJSONObject(i)
                if (item.getString("id") == id) return
                if (now - item.getLong("time") < MAX_AGE_MS) items.put(item)
            }
            items.put(JSONObject().put("id", id).put("package", sbn.packageName).put("title", title).put("text", text).put("time", sbn.postTime))
            while (items.length() > MAX_ITEMS) items.remove(0)
            write(this, items)
        }
        notifyDetected()
    }

    /** "Gasto detectado: toque para lançar". Uma notificação só, atualizada a cada nova. */
    private fun notifyDetected() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Gastos detectados", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Aviso quando uma compra ou Pix do seu banco está pronto para lançar"
                },
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra("open", "detected"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val count = read(this).length()
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(if (count == 1) "Gasto detectado no seu banco" else "$count movimentações detectadas")
            .setContentText("Toque para conferir e lançar no Economizze")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Sem permissão de notificação (Android 13+): a fila continua e aparece ao abrir o app.
        }
    }
}
