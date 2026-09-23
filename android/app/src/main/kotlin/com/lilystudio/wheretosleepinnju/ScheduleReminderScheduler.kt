package com.lilystudio.wheretosleepinnju

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray

/**
 * Clears alarms left by the unused in-app queue.
 * New reminders are written to the system calendar, so this class does not
 * schedule a capped AlarmManager queue.
 */
class ScheduleReminderScheduler(private val context: Context) {
    private val app = context.applicationContext
    private val alarmManager = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val lock = Any()

    fun storedKeys(): Set<String> {
        synchronized(lock) {
            return readKeys()
        }
    }

    fun cancelAction(key: String) {
        synchronized(lock) {
            cancelPending(key)
        }
    }

    fun clear() {
        synchronized(lock) {
            for (key in readKeys()) cancelPending(key)
            if (Build.VERSION.SDK_INT >= 26) {
                val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                for (status in manager.activeNotifications) {
                    if (status.notification.channelId == CHANNEL) {
                        manager.cancel(status.tag, status.id)
                    }
                }
            }
            if (!prefs.edit().remove(KEYS).commit()) {
                throw IllegalStateException("暂时无法清理旧提醒，请重试。")
            }
        }
    }

    private fun readKeys(): Set<String> {
        val raw = prefs.getString(KEYS, null)
        val array = try {
            if (raw.isNullOrEmpty()) JSONArray() else JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
        val keys = linkedSetOf<String>()
        for (index in 0 until array.length()) {
            val key = array.optString(index)
            if (key.isNotEmpty()) keys.add(key)
        }
        return keys
    }

    private fun cancelPending(key: String) {
        val intent = Intent(app, ScheduleReminderReceiver::class.java).setAction(key)
        val pending = PendingIntent.getBroadcast(
            app,
            key.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pending)
        pending.cancel()
        NotificationManagerCompat.from(app).cancel(key.hashCode())
    }

    companion object {
        const val CHANNEL = "sanqian.schedule"
        private const val PREFS = "sanqian_reminders"
        private const val KEYS = "pending_keys"

        /** A stored key is still the fallback queue. Anything else was already retired. */
        fun shouldNotify(action: String?, storedKeys: Set<String>): Boolean {
            return !action.isNullOrEmpty() && storedKeys.contains(action)
        }

        fun show(context: Context, id: String, title: String, body: String) {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
            val notification = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(id.hashCode(), notification)
        }
    }
}

class ScheduleReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val scheduler = ScheduleReminderScheduler(context)
        if (!ScheduleReminderScheduler.shouldNotify(action, scheduler.storedKeys())) {
            if (!action.isNullOrEmpty()) scheduler.cancelAction(action)
            return
        }
        val id = intent.getStringExtra("id") ?: return
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: return
        ScheduleReminderScheduler.show(context, id, title, body)
    }
}
