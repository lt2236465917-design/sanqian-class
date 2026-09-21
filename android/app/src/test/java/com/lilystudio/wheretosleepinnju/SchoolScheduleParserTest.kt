package com.lilystudio.wheretosleepinnju

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SchoolScheduleParserTest {
    private fun table(
        rows: List<List<SchoolPortalTableCell>>,
        url: String = "https://school.example/table?ticket=SECRET#token"
    ): SchoolPortalFrameMessage {
        return SchoolPortalFrameMessage(
            version = 1,
            kind = "scheduleTables",
            requestID = "request",
            frame = SchoolPortalFrameIdentity(url, "https://school.example", false),
            title = "",
            innerText = "",
            html = "",
            rows = rows
        )
    }

    private fun parse(meeting: String): List<SchoolScheduleDraft> {
        return SchoolScheduleParser.parse(
            table(
                listOf(
                    listOf(SchoolPortalTableCell("课程名称"), SchoolPortalTableCell("上课时间")),
                    listOf(SchoolPortalTableCell("英语"), SchoolPortalTableCell(meeting))
                )
            )
        ).drafts
    }

    @Test
    fun htmlRowspanAndPendingSurvive() {
        val html = """
            <table><tr><th>课程编号</th><th>课程名称</th><th>上课时间</th><th>上课地点</th><th>任课教师</th></tr>
            <tr><td rowspan="2">ART-01</td><td rowspan="2">摄影</td><td>周六 1-4,6-10,12-16周 08:00-09:40</td><td>教室A</td><td>李老师</td></tr>
            <tr><td>周六 5,11周 13:30-15:10</td><td>教室B</td><td>李老师</td></tr>
            <tr><td></td><td>导师课</td><td>待定</td><td></td><td></td></tr></table>
        """.trimIndent()
        val result = SchoolScheduleParser.parseHTML(html, sourceURL = "https://school.example/t?ticket=SECRET#SECRET")
        assertEquals(3, result.drafts.size)
        assertEquals("摄影", result.drafts[0].title)
        assertEquals("ART-01", result.drafts[1].courseCode)
        assertFalse(result.drafts[0].weeks?.contains(5) == true)
        assertFalse(result.drafts[0].weeks?.contains(11) == true)
        assertEquals(listOf(5, 11), result.drafts[1].weeks)
        assertEquals("教室B", result.drafts[1].location)
        assertEquals("导师课", result.drafts[2].title)
        assertTrue(result.drafts[2].isPending)
        assertEquals("https://school.example/t", result.sourceURL)
        assertTrue(result.drafts.all { it.sourceURL?.contains("SECRET") != true })
    }

    @Test
    fun periodsAreNotClocksOrWeeks() {
        val periods = parse("周一 第1-2节")[0]
        assertEquals(1, periods.weekday)
        assertNull(periods.weeks)
        assertNull(periods.startMinutes)
        assertNull(periods.endMinutes)
        assertEquals(1, periods.startPeriod)
        assertEquals(2, periods.endPeriod)
        val partial = parse("周四 08:00-09:40")[0]
        assertEquals(4, partial.weekday)
        assertEquals(480, partial.startMinutes)
        assertEquals(580, partial.endMinutes)
        assertNull(partial.weeks)
        assertNull(parse("1-16周 08:00-09:40")[0].weekday)
        assertNull(parse("周一 1-16周 08:99-10:00")[0].startMinutes)
        assertNull(parse("周一 1-16周 23:00-24:00")[0].endMinutes)
        assertNull(parse("周一 1-16周 10:00-08:00")[0].startMinutes)
        assertNull(parse("周一 16-1周 08:00-09:00")[0].weeks)
        assertEquals(listOf(1, 3, 5, 7, 9, 11, 13, 15), parse("周一 1-16周(单) 08:00-09:00")[0].weeks)
    }

    @Test
    fun multipleArrangementsSplit() {
        val multiple = parse("周一 1-4周 08:00-09:00；周四 5-8周 13:00-14:00")
        assertEquals(2, multiple.size)
        assertEquals(1, multiple[0].weekday)
        assertEquals(4, multiple[1].weekday)
        val unseparated = parse("周一 1-4周 08:00-09:00 周四 5-8周 13:00-14:00")
        assertEquals(2, unseparated.size)
        assertEquals(780, unseparated[1].startMinutes)
        val sameDay = parse("周一 1-4周 08:00-09:00 13:00-14:00")
        assertEquals(2, sameDay.size)
        assertEquals(780, sameDay[1].startMinutes)
    }

    @Test
    fun gridMergedDurationIsNotFabricated() {
        val merged = SchoolScheduleParser.parse(
            table(
                listOf(
                    listOf(SchoolPortalTableCell("时间"), SchoolPortalTableCell("周一"), SchoolPortalTableCell("周二")),
                    listOf(SchoolPortalTableCell("08:00-09:00"), SchoolPortalTableCell("英语\n1-4周", rowSpan = 2), SchoolPortalTableCell("")),
                    listOf(SchoolPortalTableCell("09:10-10:00"), SchoolPortalTableCell(""))
                )
            )
        )
        assertEquals(1, merged.drafts.size)
        assertTrue(merged.drafts[0].isPending)
        assertNull(merged.drafts[0].startMinutes)
    }

    @Test
    fun expandRestoresSpans() {
        val expanded = SchoolScheduleParser.expand(
            listOf(
                listOf(SchoolPortalTableCell("横跨", colSpan = 2), SchoolPortalTableCell("尾")),
                listOf(SchoolPortalTableCell("跨行", rowSpan = 2), SchoolPortalTableCell("B")),
                listOf(SchoolPortalTableCell("C"))
            )
        )
        assertEquals(listOf("横跨", "横跨", "尾"), expanded[0])
        assertEquals("跨行", expanded[2][0])
        assertEquals("C", expanded[2][1])
    }

    @Test
    fun weeklyGridKeepsPartialFields() {
        val grid = SchoolScheduleParser.parse(
            table(
                listOf(
                    listOf(SchoolPortalTableCell("时间"), SchoolPortalTableCell("周一"), SchoolPortalTableCell("周二")),
                    listOf(SchoolPortalTableCell("08:00-09:40"), SchoolPortalTableCell("英语\n1-4周"), SchoolPortalTableCell("导师课"))
                )
            )
        )
        assertEquals(2, grid.drafts.size)
        assertTrue(grid.drafts.any { it.title == "英语" && it.weeks == listOf(1, 2, 3, 4) && it.startMinutes == 480 })
        assertTrue(grid.drafts.any { it.title == "导师课" && it.weekday == 2 && it.weeks == null })
        assertTrue(SchoolScheduleParser.parseHTML("<form><input type='password' value='SECRET'></form>").drafts.isEmpty())
    }

    @Test
    fun sanitizedUrlDropsQuery() {
        assertEquals(
            "https://school.example/t",
            SchoolPortalSecurity.sanitizedURL("https://school.example/t?ticket=SECRET#token")
        )
    }
}
