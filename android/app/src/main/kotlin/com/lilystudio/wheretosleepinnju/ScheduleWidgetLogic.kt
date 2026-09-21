package com.lilystudio.wheretosleepinnju

import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

enum class WidgetSource { READY, NOT_SYNCED, UNAVAILABLE }

data class WidgetEvent(
    val id: String,
    val title: String,
    val classroom: String,
    val startMs: Long,
    val endMs: Long,
    val clockRange: String,
)

data class WidgetCourseLine(
    val title: String,
    val time: String,
    val place: String,
    val whenLabel: String,
    val active: Boolean,
)

data class WidgetPresentation(
    val source: WidgetSource,
    val headerDate: String,
    val compactBadge: String,
    val wideBadge: String,
    val todayRemaining: Int,
    val primary: WidgetCourseLine?,
    val rows: List<WidgetCourseLine>,
    val moreCount: Int,
    val upcoming: WidgetCourseLine?,
    val emptyTitle: String,
    val emptyHint: String,
    val showEmptyHint: Boolean,
    val description: String,
    val nextRefreshMs: Long,
)

private val shanghaiZone: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")
private const val REFRESH_FLOOR_MS = 30_000L

fun widgetSnapshotJson(args: Map<*, *>): String {
    val safe = linkedMapOf<String, Any?>(
        "schemaVersion" to 1,
        "tableId" to (args["tableId"] ?: 0),
        "revision" to (args["revision"] ?: ""),
        "generatedAtMs" to (args["generatedAtMs"] ?: 0),
        "occurrences" to (args["occurrences"] ?: emptyList<Any>()),
    )
    return toJsonValue(safe).toString()
}

fun parseWidgetSnapshot(text: String): List<WidgetEvent>? {
    val root = try {
        JSONObject(text)
    } catch (_: Exception) {
        return null
    }
    if (root.optInt("schemaVersion", -1) != 1) return null
    val array = root.optJSONArray("occurrences") ?: return null
    val events = mutableListOf<WidgetEvent>()
    for (index in 0 until array.length()) {
        val row = array.optJSONObject(index) ?: continue
        if (!row.has("startMs") || !row.has("endMs")) continue
        val start = row.optLong("startMs")
        val end = row.optLong("endMs")
        if (end <= start) continue
        val title = row.optString("title").trim().ifEmpty { "未命名课程" }
        events.add(
            WidgetEvent(
                id = row.optString("id"),
                title = title,
                classroom = row.optString("classroom"),
                startMs = start,
                endMs = end,
                clockRange = row.optString("clockRange"),
            )
        )
    }
    events.sortBy { it.startMs }
    return events
}

fun presentWidget(source: WidgetSource, events: List<WidgetEvent>, nowMs: Long): WidgetPresentation {
    val headerDate = shanghaiHeaderDate(nowMs)
    val nextRefreshMs = nextWidgetBoundaryMs(if (source == WidgetSource.READY) events else emptyList(), nowMs)
    if (source != WidgetSource.READY) {
        val title = if (source == WidgetSource.NOT_SYNCED) "尚未导入课表" else "课表暂时无法读取"
        val hint = if (source == WidgetSource.NOT_SYNCED) "打开 App 导入或选择课表" else "打开 App 重新同步课表"
        return WidgetPresentation(
            source = source,
            headerDate = headerDate,
            compactBadge = headerDate,
            wideBadge = headerDate,
            todayRemaining = 0,
            primary = null,
            rows = emptyList(),
            moreCount = 0,
            upcoming = null,
            emptyTitle = title,
            emptyHint = hint,
            showEmptyHint = true,
            description = title,
            nextRefreshMs = nextRefreshMs,
        )
    }
    val sorted = events.sortedBy { it.startMs }
    val ongoing = sorted.filter { it.startMs <= nowMs && it.endMs > nowMs }
    val startedToday = sorted.filter { sameShanghaiDay(it.startMs, nowMs) }
    val remaining = (startedToday.filter { it.endMs > nowMs } + ongoing)
        .distinctBy { it.id to it.startMs }
        .sortedBy { it.startMs }
    val next = sorted.firstOrNull { it.endMs > nowMs }
    val rows = remaining.take(3).map { courseLine(it, nowMs) }
    val primary = next?.let { courseLine(it, nowMs) }
    val finishedToday = startedToday.isNotEmpty() && remaining.isEmpty()
    val emptyTitle = when {
        sorted.isEmpty() -> "暂无已排课程"
        finishedToday -> "今日课程已完成"
        else -> "今天没有课"
    }
    val emptyHint = if (sorted.isEmpty()) "已确认时间的课程会显示在这里" else "暂无后续课程"
    val compactBadge = when {
        primary == null -> headerDate
        primary.active -> "上课中"
        finishedToday -> "已完成"
        startedToday.isEmpty() -> "无课"
        else -> "下一节"
    }
    val wideBadge = if (remaining.isNotEmpty()) "今日剩余 ${remaining.size} 节" else headerDate
    val description = when {
        primary?.active == true -> "正在上课，${primary.title}，${primary.time}，${primary.place}"
        rows.isNotEmpty() -> "今天还有${remaining.size}节课，${rows.first().title}，${rows.first().time}"
        primary != null -> "$emptyTitle，下次${primary.title}，${primary.whenLabel}，${primary.time}，${primary.place}"
        else -> emptyTitle
    }
    return WidgetPresentation(
        source = source,
        headerDate = headerDate,
        compactBadge = compactBadge,
        wideBadge = wideBadge,
        todayRemaining = remaining.size,
        primary = primary,
        rows = rows,
        moreCount = (remaining.size - rows.size).coerceAtLeast(0),
        upcoming = if (rows.isEmpty()) primary else null,
        emptyTitle = emptyTitle,
        emptyHint = emptyHint,
        showEmptyHint = primary == null,
        description = description,
        nextRefreshMs = nextRefreshMs,
    )
}

fun nextWidgetBoundaryMs(events: List<WidgetEvent>, nowMs: Long): Long {
    var next = startOfNextShanghaiDay(nowMs)
    for (event in events) {
        if (event.startMs > nowMs && event.startMs < next) next = event.startMs
        if (event.endMs > nowMs && event.endMs < next) next = event.endMs
    }
    val earliest = nowMs + REFRESH_FLOOR_MS
    return if (next < earliest) earliest else next
}

private fun courseLine(event: WidgetEvent, nowMs: Long): WidgetCourseLine {
    val active = event.startMs <= nowMs && event.endMs > nowMs
    val time = event.clockRange.trim().ifEmpty { shanghaiClock(event.startMs, event.endMs) }
    val place = event.classroom.trim().ifEmpty { "地点待定" }
    return WidgetCourseLine(
        title = event.title.ifBlank { "未命名课程" },
        time = time,
        place = place,
        whenLabel = if (active) "今天" else shanghaiDateLabel(event.startMs, nowMs),
        active = active,
    )
}

internal fun shanghaiClock(startMs: Long, endMs: Long): String {
    return "${shanghaiHourMinute(startMs)}–${shanghaiHourMinute(endMs)}"
}

private fun shanghaiHourMinute(ms: Long): String {
    val calendar = shanghaiCalendar(ms)
    return "%02d:%02d".format(
        calendar.get(Calendar.HOUR_OF_DAY),
        calendar.get(Calendar.MINUTE),
    )
}

private fun shanghaiHeaderDate(ms: Long): String {
    val calendar = shanghaiCalendar(ms)
    return "%02d/%02d".format(calendar.get(Calendar.MONTH) + 1, calendar.get(Calendar.DAY_OF_MONTH))
}

private fun shanghaiDateLabel(eventMs: Long, nowMs: Long): String {
    if (sameShanghaiDay(eventMs, nowMs)) return "今天"
    if (sameShanghaiDay(eventMs, startOfNextShanghaiDay(nowMs))) return "明天"
    val calendar = shanghaiCalendar(eventMs)
    val weekdays = arrayOf("日", "一", "二", "三", "四", "五", "六")
    val week = weekdays[calendar.get(Calendar.DAY_OF_WEEK) - 1]
    return "${calendar.get(Calendar.MONTH) + 1}月${calendar.get(Calendar.DAY_OF_MONTH)}日 周$week"
}

private fun sameShanghaiDay(leftMs: Long, rightMs: Long): Boolean {
    val left = shanghaiCalendar(leftMs)
    val right = shanghaiCalendar(rightMs)
    return left.get(Calendar.YEAR) == right.get(Calendar.YEAR) &&
        left.get(Calendar.DAY_OF_YEAR) == right.get(Calendar.DAY_OF_YEAR)
}

private fun startOfNextShanghaiDay(ms: Long): Long {
    val calendar = shanghaiCalendar(ms)
    calendar.set(Calendar.HOUR_OF_DAY, 0)
    calendar.set(Calendar.MINUTE, 0)
    calendar.set(Calendar.SECOND, 0)
    calendar.set(Calendar.MILLISECOND, 0)
    calendar.add(Calendar.DAY_OF_MONTH, 1)
    return calendar.timeInMillis
}

private fun shanghaiCalendar(ms: Long): Calendar {
    return Calendar.getInstance(shanghaiZone).apply {
        timeInMillis = ms
    }
}
