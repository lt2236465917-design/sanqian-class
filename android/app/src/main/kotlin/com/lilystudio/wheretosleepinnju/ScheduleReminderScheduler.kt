package com.lilystudio.wheretosleepinnju

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray

class ScheduleReminderScheduler(private val context: Context) {
    private val app = context.applicationContext
    private val alarmManager = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val lock = Any()
    private var generation = 0

    fun notificationsEnabled(): Boolean = NotificationManagerCompat.from(app).areNotificationsEnabled()

    fun replace(occurrences: List<Map<String, Any?>>, leadMinutes: List<Int>): Map<String, Any?> {
        synchronized(lock) {
            generation += 1
            ensureChannel()
            cancelStored()
            if (!notificationsEnabled()) {
                return mapOf("count" to 0, "permission" to "denied")
            }
            val allowedLeads = leadMinutes.toSet().intersect(setOf(15, 180, 1440))
            val now = System.currentTimeMillis()
            val candidates = mutableListOf<Reminder>()
            for (row in occurrences) {
                val id = row["id"] as? String ?: continue
                val start = number(row["startMs"]) ?: continue
                val end = number(row["endMs"]) ?: continue
                if (end <= start) continue
                val title = row["title"] as? String ?: continue
                val classroom = row["classroom"] as? String ?: ""
                for (lead in allowedLeads) {
                    val fire = start - lead * 60_000L
                    if (fire <= now) continue
                    val label = when (lead) {
                        15 -> "15 分钟"
                        180 -> "3 小时"
                        else -> "1 天"
                    }
                    candidates.add(
                        Reminder(
                            key = "$PREFIX$id.$lead",
                            fireAt = fire,
                            title = title,
                            body = "还有${label}上课 · $classroom"
                        )
                    )
                }
            }
            candidates.sortBy { it.fireAt }
            val selected = candidates.take(60)
            var failures = 0
            val stored = JSONArray()
            for (item in selected) {
                try {
                    schedule(item)
                    stored.put(item.key)
                } catch (_: Exception) {
                    failures += 1
                }
            }
            prefs.edit().putString(KEYS, stored.toString()).apply()
            val coverage = selected.lastOrNull()?.fireAt ?: 0L
            return mapOf(
                "count" to (selected.size - failures),
                "failed" to failures,
                "permission" to "authorized",
                "limited" to (candidates.size > selected.size),
                "coverageEndMs" to coverage
            )
        }
    }

    fun clear() {
        synchronized(lock) {
            generation += 1
            val raw = prefs.getString(KEYS, null)
            val array = try {
                if (raw.isNullOrEmpty()) JSONArray() else JSONArray(raw)
            } catch (_: Exception) {
                JSONArray()
            }
            for (index in 0 until array.length()) {
                val key = array.optString(index)
                if (key.isEmpty()) continue
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
            if (Build.VERSION.SDK_INT >= 26) {
                val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
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

    private fun schedule(item: Reminder) {
        val intent = Intent(app, ScheduleReminderReceiver::class.java)
            .setAction(item.key)
            .putExtra("id", item.key)
            .putExtra("title", item.title)
            .putExtra("body", item.body)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pending = PendingIntent.getBroadcast(app, item.key.hashCode(), intent, flags)
        try {
            if (Build.VERSION.SDK_INT >= 31 && !alarmManager.canScheduleExactAlarms()) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.fireAt, pending)
            } else {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.fireAt, pending)
            }
        } catch (_: SecurityException) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.fireAt, pending)
        }
    }

    private fun cancelStored() {
        val raw = prefs.getString(KEYS, null) ?: return
        val array = try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
        for (i in 0 until array.length()) {
            val key = array.optString(i)
            if (key.isEmpty()) continue
            val intent = Intent(app, ScheduleReminderReceiver::class.java).setAction(key)
            val pending = PendingIntent.getBroadcast(
                app,
                key.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pending)
            pending.cancel()
        }
        prefs.edit().remove(KEYS).apply()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL, "上课提醒", NotificationManager.IMPORTANCE_DEFAULT)
        channel.description = "按已核对课程时间提醒"
        manager.createNotificationChannel(channel)
    }

    private data class Reminder(val key: String, val fireAt: Long, val title: String, val body: String)

    companion object {
        const val CHANNEL = "sanqian.schedule"
        private const val PREFIX = "sanqian.schedule."
        private const val PREFS = "sanqian_reminders"
        private const val KEYS = "pending_keys"

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

        private fun number(value: Any?): Long? {
            return when (value) {
                is Number -> value.toLong()
                is String -> value.toLongOrNull()
                else -> null
            }
        }
    }
}

class ScheduleReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: return
        ScheduleReminderScheduler.show(context, id, title, body)
    }
}
