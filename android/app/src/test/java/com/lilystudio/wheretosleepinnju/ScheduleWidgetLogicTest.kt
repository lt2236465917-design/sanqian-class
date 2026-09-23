package com.lilystudio.wheretosleepinnju

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

class ScheduleWidgetLogicTest {
    private val zone = TimeZone.getTimeZone("Asia/Shanghai")

    private fun shanghai(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long {
        return Calendar.getInstance(zone).apply {
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month - 1)
            set(Calendar.DAY_OF_MONTH, day)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    private fun event(
        title: String,
        start: Long,
        end: Long,
        room: String = "教室A",
        clock: String = "",
        id: String = title,
    ) = WidgetEvent(id, title, room, start, end, clock)

    @Test
    fun shanghaiOffsetIsEightHours() {
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            set(2026, Calendar.SEPTEMBER, 22, 1, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        assertEquals(utc.timeInMillis, shanghai(2026, 9, 22, 9, 0))
    }

    @Test
    fun snapshotDropsSecretsAndRoundTripsOccurrences() {
        val start = shanghai(2026, 9, 22, 9, 0)
        val end = shanghai(2026, 9, 22, 10, 40)
        val json = widgetSnapshotJson(
            mapOf(
                "tableId" to 7,
                "revision" to "rev",
                "generatedAtMs" to 42,
                "leadMinutes" to listOf(15),
                "password" to "secret-value",
                "occurrences" to listOf(
                    mapOf(
                        "id" to "a",
                        "title" to "艺术美学",
                        "classroom" to "",
                        "startMs" to start,
                        "endMs" to end,
                        "clockRange" to "",
                    ),
                    mapOf(
                        "id" to "bad",
                        "title" to "待定课",
                        "startMs" to end,
                        "endMs" to start,
                    ),
                ),
            )
        )
        assertFalse(json.contains("secret-value"))
        assertFalse(json.contains("leadMinutes"))
        val events = parseWidgetSnapshot(json)
        assertEquals(1, events!!.size)
        assertEquals("艺术美学", events[0].title)
        assertEquals("09:00–10:40", shanghaiClock(events[0].startMs, events[0].endMs))
        val view = presentWidget(WidgetSource.READY, events, start + 30 * 60_000L)
        assertEquals("上课中", view.compactBadge)
        assertEquals("地点待定", view.primary!!.place)
        assertEquals("今天", view.primary!!.whenLabel)
        assertTrue(view.primary!!.active)
    }

    @Test
    fun invalidSnapshotsAreRejected() {
        assertNull(parseWidgetSnapshot("not-json"))
        assertNull(parseWidgetSnapshot("""{"schemaVersion":2,"occurrences":[]}"""))
        assertNull(parseWidgetSnapshot("""{"schemaVersion":1}"""))
        assertEquals(0, parseWidgetSnapshot("""{"schemaVersion":1,"occurrences":[]}""")!!.size)
    }

    @Test
    fun statesCoverEmptyFinishedNoClassAndNotImported() {
        val morning = event(
            "中国艺术史",
            shanghai(2026, 9, 22, 9, 0),
            shanghai(2026, 9, 22, 10, 40),
            clock = "09:00–10:40",
        )
        val afternoon = event(
            "艺术美学",
            shanghai(2026, 9, 22, 13, 30),
            shanghai(2026, 9, 22, 16, 30),
            room = "教学楼",
            clock = "13:30–16:30",
        )
        val tomorrow = event(
            "摄影",
            shanghai(2026, 9, 23, 9, 0),
            shanghai(2026, 9, 23, 12, 0),
            clock = "09:00–12:00",
        )
        val evening = shanghai(2026, 9, 22, 18, 0)
        val finished = presentWidget(WidgetSource.READY, listOf(morning, tomorrow), evening)
        assertEquals("今日课程已完成", finished.emptyTitle)
        assertEquals("已完成", finished.compactBadge)
        assertEquals("摄影", finished.upcoming!!.title)
        assertEquals("明天", finished.upcoming!!.whenLabel)
        assertTrue(finished.rows.isEmpty())

        val noon = shanghai(2026, 9, 22, 12, 0)
        val during = presentWidget(WidgetSource.READY, listOf(morning, afternoon), noon)
        assertEquals("艺术美学", during.primary!!.title)
        assertEquals("下一节", during.compactBadge)
        assertEquals(1, during.todayRemaining)
        assertEquals("今日剩余 1 节", during.wideBadge)
        assertEquals("教学楼", during.rows.single().place)

        val noClass = presentWidget(WidgetSource.READY, listOf(tomorrow), evening)
        assertEquals("今天没有课", noClass.emptyTitle)
        assertEquals("无课", noClass.compactBadge)
        assertEquals("摄影", noClass.primary!!.title)

        val none = presentWidget(WidgetSource.READY, emptyList(), evening)
        assertEquals("暂无已排课程", none.emptyTitle)
        assertTrue(none.showEmptyHint)
        assertNull(none.primary)

        val missing = presentWidget(WidgetSource.NOT_SYNCED, listOf(morning), evening)
        assertEquals("尚未导入课表", missing.emptyTitle)
        assertNull(missing.primary)
        val broken = presentWidget(WidgetSource.UNAVAILABLE, emptyList(), evening)
        assertEquals("课表暂时无法读取", broken.emptyTitle)
    }

    @Test
    fun overnightClassStaysVisibleAfterMidnight() {
        val overnight = event(
            "夜课",
            shanghai(2026, 9, 22, 22, 0),
            shanghai(2026, 9, 23, 0, 30),
            clock = "22:00–00:30",
        )
        val afterMidnight = shanghai(2026, 9, 23, 0, 10)
        val view = presentWidget(WidgetSource.READY, listOf(overnight), afterMidnight)
        assertEquals(1, view.todayRemaining)
        assertTrue(view.primary!!.active)
        assertEquals("今天", view.primary!!.whenLabel)
        assertEquals("上课中", view.compactBadge)
    }

    @Test
    fun extraCoursesAreCountedAndBoundaryUsesShanghaiMidnight() {
        val now = shanghai(2026, 9, 22, 8, 0)
        val courses = (0 until 4).map { index ->
            val startHour = 9 + index
            event(
                "课$index",
                shanghai(2026, 9, 22, startHour, 0),
                shanghai(2026, 9, 22, startHour, 40),
                id = "id$index",
            )
        }
        val view = presentWidget(WidgetSource.READY, courses, now)
        assertEquals(3, view.rows.size)
        assertEquals(1, view.moreCount)
        assertEquals("课0", view.rows.first().title)
        assertEquals(courses.first().startMs, view.nextRefreshMs)

        val quiet = nextWidgetBoundaryMs(emptyList(), now)
        assertEquals(shanghai(2026, 9, 23, 0, 0), quiet)
        val soon = nextWidgetBoundaryMs(
            listOf(event("快结束", now - 60_000, now + 5_000)),
            now,
        )
        assertEquals(now + 30_000, soon)
    }

    @Test
    fun eventsAreOrderedAndPastOnesDoNotBecomeNext() {
        val later = event("后", shanghai(2026, 9, 24, 9, 0), shanghai(2026, 9, 24, 10, 0))
        val earlier = event("先", shanghai(2026, 9, 23, 9, 0), shanghai(2026, 9, 23, 10, 0))
        val past = event("旧", shanghai(2026, 9, 20, 9, 0), shanghai(2026, 9, 20, 10, 0))
        val parsed = parseWidgetSnapshot(
            widgetSnapshotJson(
                mapOf(
                    "occurrences" to listOf(later, earlier, past).map {
                        mapOf(
                            "id" to it.id,
                            "title" to it.title,
                            "classroom" to it.classroom,
                            "startMs" to it.startMs,
                            "endMs" to it.endMs,
                            "clockRange" to "09:00–10:00",
                        )
                    }
                )
            )
        )!!
        assertEquals(listOf("旧", "先", "后"), parsed.map { it.title })
        val view = presentWidget(WidgetSource.READY, parsed, shanghai(2026, 9, 22, 12, 0))
        assertEquals("先", view.primary!!.title)
        assertEquals("明天", view.primary!!.whenLabel)
        val laterView = presentWidget(WidgetSource.READY, parsed, shanghai(2026, 9, 21, 12, 0))
        assertEquals("9月23日 周三", laterView.primary!!.whenLabel)
    }
}
