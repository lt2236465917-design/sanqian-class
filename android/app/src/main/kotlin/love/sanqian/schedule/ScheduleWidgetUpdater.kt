package love.sanqian.schedule

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews

object ScheduleWidgetUpdater {
    const val EXTRA_OPEN_SCHEDULE = "openSchedule"
    private const val ACTION_REFRESH = "love.sanqian.schedule.action.WIDGET_REFRESH"
    private const val REQUEST_REFRESH = 0x5102
    private const val REQUEST_OPEN = 0x5101
    private const val MEDIUM_WIDTH_DP = 250

    fun refresh(context: Context?) {
        val app = context?.applicationContext ?: return
        try {
            val ids = ScheduleWidgetSafety.widgetIds(app)
            if (ids.isEmpty()) {
                cancelRefresh(app)
                return
            }
            val manager = AppWidgetManager.getInstance(app) ?: return
            update(app, manager, ids)
            schedule(app, load(app).nextRefreshMs)
        } catch (_: Throwable) {
            // Package replace on Xiaomi can deliver a null widget list. Keep the process alive.
        }
    }

    fun update(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val app = context.applicationContext
        val presentation = load(app)
        for (id in ids) {
            try {
                val options = ScheduleWidgetSafety.options(manager, id)
                // The host supplies portrait (min width / max height) and landscape
                // (max width / min height) bounds. Let it select on rotation as well.
                val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, -1)
                val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, -1)
                val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minWidth)
                val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, minHeight)
                val portrait = render(app, presentation, minWidth, maxHeight)
                val landscape = render(app, presentation, maxWidth, minHeight)
                manager.updateAppWidget(id, RemoteViews(landscape, portrait))
            } catch (_: Throwable) {
                // One widget's options can be null during an update. Skip that id.
            }
        }
    }

    private fun render(app: Context, presentation: WidgetPresentation, width: Int, height: Int): RemoteViews {
        val medium = width < 0 || width >= MEDIUM_WIDTH_DP
        val large = medium && height >= 300
        val layout = when {
            large -> R.layout.widget_schedule_large
            medium -> R.layout.widget_schedule_medium
            else -> R.layout.widget_schedule_small
        }
        var views = RemoteViews(app.packageName, layout)
        val now = System.currentTimeMillis()
        val largeText = app.resources.configuration.fontScale > 1.2f
        val tight = height in 0..159
        val inset = if (tight) 8 else if (height in 160..179) 12 else 16
        val padding = (inset * app.resources.displayMetrics.density).toInt()
        views.setViewPadding(R.id.widget_root, padding, padding, padding, padding)
        views.setTextViewText(R.id.widget_date, presentation.headerDate)
        views.setTextViewText(R.id.widget_summary, presentation.wideBadge)
        views.setViewVisibility(R.id.widget_date, if (height in 0..139) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.widget_summary, if (medium && !largeText && !tight && presentation.primary != null) View.VISIBLE else View.GONE)
        bindPrimary(app, views, presentation, !medium || height < 180, now)
        views.setInt(R.id.widget_title, "setMaxLines", if (tight) 1 else 2)
        views.setTextViewTextSize(R.id.widget_status, TypedValue.COMPLEX_UNIT_SP, if (tight) 11f else 12f)
        views.setTextViewTextSize(R.id.widget_time, TypedValue.COMPLEX_UNIT_SP, if (tight) 14f else 16f)
        views.setTextViewTextSize(R.id.widget_place, TypedValue.COMPLEX_UNIT_SP, if (tight) 11f else 12f)
        if (tight) {
            views.setTextViewTextSize(R.id.widget_title, TypedValue.COMPLEX_UNIT_SP, 16f)
        }
        when {
            large -> {
                // Measure the same native layout the launcher renders, including
                // wrapped titles, font scale, padding and the overflow footer.
                val maximum = minOf(presentation.dayRows.size, height / 36).coerceAtLeast(1)
                for (capacity in maximum downTo 1) {
                    val candidate = RemoteViews(views)
                    bindLarge(app, candidate, presentation, now, capacity)
                    if (capacity == 1 || fits(app, candidate, width, height)) {
                        views = candidate
                        break
                    }
                }
            }
            medium -> {
                val maximum = if (tight) 0 else minOf(2, presentation.following.size)
                for (capacity in maximum downTo 0) {
                    val candidate = RemoteViews(views)
                    bindMedium(app, candidate, presentation, capacity)
                    val content = candidate.apply(app, null)
                    val header = content.findViewById<View>(R.id.widget_date)
                    val sidebar = content.findViewById<View>(R.id.widget_following)
                    val availableWidth = (width - inset * 2 - 16).coerceAtLeast(1)
                    val sidebarHeight = measuredHeight(app, sidebar, (availableWidth * 0.4f).toInt())
                    val headerHeight = measuredHeight(app, header, availableWidth)
                    val availableHeight = ((height - inset * 2 - 14) * app.resources.displayMetrics.density).toInt()
                    if (capacity == 0 || height < 0 || sidebarHeight + headerHeight <= availableHeight) {
                        views = candidate
                        break
                    }
                }
            }
        }
        views.setContentDescription(R.id.widget_root, presentation.description)
        views.setOnClickPendingIntent(R.id.widget_root, openIntent(app, if (medium) null else presentation.primary, now))
        views.setOnClickPendingIntent(R.id.widget_date, openIntent(app, null, now))
        return views
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

    private fun openIntent(context: Context, course: WidgetCourseLine?, nowMs: Long): PendingIntent {
        // Keep the day target stable across refreshes so its PendingIntent is reused.
        val dayStart = ((nowMs + 8 * 3_600_000L) / 86_400_000L) * 86_400_000L - 8 * 3_600_000L
        val uri = Uri.Builder().scheme("ncs").authority("schedule")
            .appendQueryParameter("date", (course?.startMs ?: dayStart).toString())
            .apply { course?.let { appendQueryParameter("occurrence", it.id) } }.build()
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = uri
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_SCHEDULE, true)
        }
        // Data URI keeps every course's PendingIntent distinct.
        return PendingIntent.getActivity(context, REQUEST_OPEN, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun bindPrimary(context: Context, views: RemoteViews, p: WidgetPresentation, compact: Boolean, now: Long) {
        val course = p.primary
        views.setTextViewText(R.id.widget_status, p.compactBadge)
        views.setTextViewText(R.id.widget_title, course?.title ?: p.emptyTitle)
        views.setTextViewText(R.id.widget_time, course?.time ?: "")
        views.setTextViewText(R.id.widget_place, course?.place ?: "")
        views.setTextViewText(R.id.widget_hint, p.emptyHint)
        views.setTextViewTextSize(R.id.widget_title, TypedValue.COMPLEX_UNIT_SP, if (compact) 18f else 20f)
        views.setInt(R.id.widget_place, "setMaxLines", if (compact) 1 else 2)
        views.setViewVisibility(R.id.widget_status, if (course == null) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.widget_time, if (course == null) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.widget_place, if (course == null) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.widget_hint, if (course == null) View.VISIBLE else View.GONE)
        views.setOnClickPendingIntent(R.id.widget_primary, openIntent(context, course, now))
    }

    private fun bindMedium(context: Context, views: RemoteViews, p: WidgetPresentation, capacity: Int) {
        val following = p.following.take(capacity)
        views.setViewVisibility(R.id.widget_following, if (following.isEmpty()) View.GONE else View.VISIBLE)
        for (index in 0..1) {
            val root = if (index == 0) R.id.widget_following_1 else R.id.widget_following_2
            val title = if (index == 0) R.id.widget_following_1_title else R.id.widget_following_2_title
            val time = if (index == 0) R.id.widget_following_1_time else R.id.widget_following_2_time
            val course = following.getOrNull(index)
            views.setViewVisibility(root, if (course == null) View.GONE else View.VISIBLE)
            if (course != null) {
                views.setTextViewText(title, course.title)
                views.setTextViewText(time, shanghaiHourMinute(course.startMs))
                views.setOnClickPendingIntent(root, openIntent(context, course, course.startMs))
                views.setContentDescription(root, "${course.time}，${course.title}")
            }
        }
        val hidden = p.following.size - following.size
        views.setViewVisibility(R.id.widget_more, if (hidden > 0) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.widget_more, "另有 $hidden 节")
    }

    private fun bindLarge(context: Context, views: RemoteViews, p: WidgetPresentation, now: Long, capacity: Int) {
        // With no lessons left today the next lesson keeps the full primary area.
        val rows = if (p.todayRemaining > 0) widgetTimelineWindow(p.dayRows, now, capacity) else emptyList()
        views.setViewVisibility(R.id.widget_primary, if (rows.isEmpty()) View.VISIBLE else View.GONE)
        views.removeAllViews(R.id.widget_days)
        for (course in rows) {
            val row = RemoteViews(context.packageName, R.layout.widget_schedule_row)
            row.setTextViewText(R.id.widget_day_start, shanghaiHourMinute(course.startMs))
            row.setTextViewText(R.id.widget_day_end, shanghaiHourMinute(course.endMs))
            row.setTextViewText(R.id.widget_day_title, course.title)
            row.setTextViewText(R.id.widget_day_place, (if (course.active) "上课中 · " else "") + course.place)
            row.setInt(R.id.widget_day, "setBackgroundResource", if (course.active) R.drawable.widget_next_background else 0)
            row.setFloat(R.id.widget_day, "setAlpha", if (course.endMs <= now) 0.55f else 1f)
            row.setOnClickPendingIntent(R.id.widget_day, openIntent(context, course, now))
            row.setContentDescription(R.id.widget_day, "${course.time}，${course.title}，${course.place}")
            views.addView(R.id.widget_days, row)
        }
        val more = rows.isNotEmpty() && p.dayRows.size > rows.size
        views.setViewVisibility(R.id.widget_more, if (more) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.widget_more, "共 ${p.dayRows.size} 节 · 点开查看完整日程")
    }

    private fun fits(context: Context, views: RemoteViews, width: Int, height: Int): Boolean {
        val content = views.apply(context, null)
        return measuredHeight(context, content, width) <= height * context.resources.displayMetrics.density
    }

    private fun measuredHeight(context: Context, view: View, width: Int): Int {
        val pixels = (width.coerceAtLeast(1) * context.resources.displayMetrics.density).toInt()
        view.measure(View.MeasureSpec.makeMeasureSpec(pixels, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        return view.measuredHeight
    }
}
