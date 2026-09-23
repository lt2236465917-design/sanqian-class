package com.lilystudio.wheretosleepinnju

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews

object ScheduleWidgetUpdater {
    const val EXTRA_OPEN_SCHEDULE = "openSchedule"
    private const val ACTION_REFRESH = "com.lilystudio.wheretosleepinnju.action.WIDGET_REFRESH"
    private const val REQUEST_REFRESH = 0x5102
    private const val REQUEST_OPEN = 0x5101
    private const val MEDIUM_WIDTH_DP = 250

    fun refresh(context: Context) {
        val app = context.applicationContext
        val manager = AppWidgetManager.getInstance(app)
        val ids = manager.getAppWidgetIds(ComponentName(app, ScheduleWidgetProvider::class.java))
        if (ids.isEmpty()) {
            cancelRefresh(app)
            return
        }
        update(app, manager, ids)
        schedule(app, load(app).nextRefreshMs)
    }

    fun update(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val app = context.applicationContext
        val presentation = load(app)
        for (id in ids) {
            val options = manager.getAppWidgetOptions(id)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, -1)
            val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, -1)
            val medium = width < 0 || width >= MEDIUM_WIDTH_DP
            val layout = if (medium) R.layout.widget_schedule_medium else R.layout.widget_schedule_small
            val views = RemoteViews(app.packageName, layout)
            if (medium) bindMedium(views, presentation, if (height >= 180) 3 else 2)
            else bindSmall(views, presentation)
            views.setContentDescription(R.id.widget_root, presentation.description)
            views.setOnClickPendingIntent(R.id.widget_root, openIntent(app))
            manager.updateAppWidget(id, views)
        }
    }

    fun cancelRefresh(context: Context) {
        val app = context.applicationContext
        val alarmManager = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(refreshIntent(app))
    }

    private fun load(context: Context): WidgetPresentation {
        val now = System.currentTimeMillis()
        return try {
            val text = ScheduleWidgetStore.readText(context)
            if (text == null) {
                presentWidget(WidgetSource.NOT_SYNCED, emptyList(), now)
            } else {
                val events = parseWidgetSnapshot(text)
                if (events == null) presentWidget(WidgetSource.UNAVAILABLE, emptyList(), now)
                else presentWidget(WidgetSource.READY, events, now)
            }
        } catch (_: Exception) {
            presentWidget(WidgetSource.UNAVAILABLE, emptyList(), System.currentTimeMillis())
        }
    }

    private fun schedule(context: Context, atMs: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = refreshIntent(context)
        // Inexact by design: targetSdk 36 does not grant exact alarms. Doze can delay this.
        if (Build.VERSION.SDK_INT >= 23) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC, atMs, pending)
        } else {
            alarmManager.set(AlarmManager.RTC, atMs, pending)
        }
    }

    private fun refreshIntent(context: Context): PendingIntent {
        val intent = Intent(context, ScheduleWidgetRefreshReceiver::class.java).setAction(ACTION_REFRESH)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_REFRESH,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun openIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_SCHEDULE, true)
        }
        return PendingIntent.getActivity(
            context,
            REQUEST_OPEN,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun bindSmall(views: RemoteViews, presentation: WidgetPresentation) {
        views.setTextViewText(R.id.widget_badge, presentation.compactBadge)
        val course = presentation.primary
        if (course == null) {
            views.setTextViewText(R.id.widget_title, presentation.emptyTitle)
            views.setTextViewText(R.id.widget_hint, presentation.emptyHint)
            views.setViewVisibility(R.id.widget_time, View.GONE)
            views.setViewVisibility(R.id.widget_when, View.GONE)
            views.setViewVisibility(R.id.widget_place, View.GONE)
            views.setViewVisibility(R.id.widget_hint, View.VISIBLE)
        } else {
            views.setTextViewText(R.id.widget_title, course.title)
            views.setTextViewText(R.id.widget_time, course.time)
            views.setTextViewText(R.id.widget_when, course.whenLabel)
            views.setTextViewText(R.id.widget_place, course.place)
            views.setViewVisibility(R.id.widget_time, View.VISIBLE)
            views.setViewVisibility(R.id.widget_when, View.VISIBLE)
            views.setViewVisibility(R.id.widget_place, View.VISIBLE)
            views.setViewVisibility(R.id.widget_hint, View.GONE)
        }
    }

    private fun bindMedium(views: RemoteViews, presentation: WidgetPresentation, maxRows: Int) {
        views.setTextViewText(R.id.widget_badge, presentation.wideBadge)
        if (presentation.rows.isEmpty()) {
            views.setViewVisibility(R.id.widget_rows, View.GONE)
            views.setViewVisibility(R.id.widget_more, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            views.setTextViewText(R.id.widget_empty_title, presentation.emptyTitle)
            views.setTextViewText(R.id.widget_empty_hint, presentation.emptyHint)
            views.setViewVisibility(
                R.id.widget_empty_hint,
                if (presentation.showEmptyHint) View.VISIBLE else View.GONE,
            )
            val upcoming = presentation.upcoming
            if (upcoming == null) {
                views.setViewVisibility(R.id.widget_next, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_next, View.VISIBLE)
                views.setTextViewText(R.id.widget_next_title, upcoming.title)
                views.setTextViewText(R.id.widget_next_when, upcoming.whenLabel)
                views.setTextViewText(R.id.widget_next_time, upcoming.time)
                views.setTextViewText(R.id.widget_next_place, upcoming.place)
            }
            return
        }
        views.setViewVisibility(R.id.widget_rows, View.VISIBLE)
        views.setViewVisibility(R.id.widget_empty, View.GONE)
        val visible = presentation.rows.take(maxRows.coerceIn(1, 3))
        for (index in 0 until 3) {
            bindRow(views, index, visible.getOrNull(index))
        }
        val hidden = presentation.moreCount + (presentation.rows.size - visible.size)
        if (hidden > 0) {
            views.setViewVisibility(R.id.widget_more, View.VISIBLE)
            views.setTextViewText(R.id.widget_more, "还有 $hidden 节，打开 App 查看")
        } else {
            views.setViewVisibility(R.id.widget_more, View.GONE)
        }
    }

    private fun bindRow(views: RemoteViews, index: Int, line: WidgetCourseLine?) {
        val row = rowId(index, "row")
        if (line == null) {
            views.setViewVisibility(row, View.GONE)
            return
        }
        views.setViewVisibility(row, View.VISIBLE)
        views.setTextViewText(rowId(index, "title"), line.title)
        views.setTextViewText(rowId(index, "place"), line.place)
        views.setTextViewText(rowId(index, "time"), line.time)
        views.setViewVisibility(rowId(index, "status"), if (line.active) View.VISIBLE else View.GONE)
    }

    private fun rowId(index: Int, part: String): Int {
        val number = index + 1
        return when ("$number:$part") {
            "1:row" -> R.id.widget_row_1
            "1:title" -> R.id.widget_row_1_title
            "1:place" -> R.id.widget_row_1_place
            "1:time" -> R.id.widget_row_1_time
            "1:status" -> R.id.widget_row_1_status
            "1:bar" -> R.id.widget_row_1_bar
            "2:row" -> R.id.widget_row_2
            "2:title" -> R.id.widget_row_2_title
            "2:place" -> R.id.widget_row_2_place
            "2:time" -> R.id.widget_row_2_time
            "2:status" -> R.id.widget_row_2_status
            "2:bar" -> R.id.widget_row_2_bar
            "3:row" -> R.id.widget_row_3
            "3:title" -> R.id.widget_row_3_title
            "3:place" -> R.id.widget_row_3_place
            "3:time" -> R.id.widget_row_3_time
            "3:status" -> R.id.widget_row_3_status
            "3:bar" -> R.id.widget_row_3_bar
            else -> error("unknown widget row")
        }
    }
}
