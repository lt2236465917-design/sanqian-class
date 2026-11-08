package love.sanqian.schedule

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeepSeekParseTest {
    private val valid =
        """{"courses":[{"name":"英语","courseCode":"ENG","section":"1","teacher":null,"meetings":[{"weekday":1,"weeks":[3,4,6],"startMinute":540,"endMinute":600,"location":null}],"pendingReason":null}]}"""

    private fun envelope(content: String, reason: String? = "stop"): ByteArray {
        val choice = JSONObject().put("message", JSONObject().put("content", content))
        if (reason != null) choice.put("finish_reason", reason)
        return JSONObject().put("choices", JSONArray().put(choice)).toString().toByteArray()
    }

    private fun expect(error: DeepSeekTimetableClientError, block: () -> Unit) {
        try {
            block()
            throw AssertionError("expected $error")
        } catch (actual: DeepSeekTimetableClientError) {
            assertEquals(error.message, actual.message)
        }
    }

    private fun courses(content: String): JSONArray {
        val result = DeepSeekTimetableClient.parseResponse(envelope(content))
        return JSONObject(result.jsonText).getJSONArray("courses")
    }

    @Test
    fun localGridClockAndCoverageRequireRequestContext() {
        val cell = mapOf<String, Any?>("id" to "p0r1c1", "imageIndex" to 0, "weekday" to 1, "startMinute" to 1140, "endMinute" to 1290, "rowLabel" to "晚上课 19:00--21:30", "texts" to listOf("课程甲"))
        val text = """{"courses":[{"name":"课程甲","meetings":[{"weekday":1,"weeks":[4],"startMinute":1140,"endMinute":1170,"cellRefs":["p0r1c1"]}]}]}"""
        fun parsed(value: String, cells: List<Map<String, Any?>> = listOf(cell)): JSONObject = JSONObject(
            DeepSeekTimetableClient.parseResponse(envelope(value), cells).jsonText
        ).getJSONArray("courses").getJSONObject(0)
        fun first(course: JSONObject) = course.getJSONArray("meetings").getJSONObject(0)
        fun warnings(course: JSONObject) = course.getJSONObject("raw").let { it.getJSONArray("recognitionWarnings").toString() + (it.optJSONArray("batchRecognitionWarnings")?.toString() ?: "") }
        val singleRef = text.replace("\"cellRefs\":[\"p0r1c1\"]", "\"cellRef\":\"p0r1c1\"")
        assertEquals(1290, first(parsed(singleRef)).getInt("endMinute"))
        expect(DeepSeekTimetableClientError.InvalidCourseField("courses[0].meetings[0].cellRef")) {
            parsed(text.replace("cellRefs", "cellRef"))
        }
        val corrected = parsed(text)
        assertEquals(1290, first(corrected).getInt("endMinute"))
        assertEquals(1170, first(corrected).getJSONObject("raw").getInt("modelEndMinute"))
        assertEquals("[]", warnings(corrected))
        assertEquals(1170, first(parsed(text, emptyList())).getInt("endMinute"))
        val wrongDay = parsed(text.replace("\"weekday\":1", "\"weekday\":3"))
        assertTrue(first(wrongDay).isNull("weekday"))
        assertTrue(warnings(wrongDay).contains("图片列"))
        val wrongRef = parsed(text.replace("p0r1c1", "invented"))
        assertEquals(1170, first(wrongRef).getInt("endMinute"))
        assertTrue(warnings(wrongRef).contains("无效"))
        val explicit = parsed(text.replace("\"cellRefs\"", "\"sourceLine\":\"19:00-19:30\",\"cellRefs\""))
        assertTrue(first(explicit).isNull("startMinute") && first(explicit).isNull("endMinute"))
        val other = cell + mapOf("id" to "p0r1c2", "weekday" to 2)
        assertTrue(warnings(parsed(text, listOf(cell, other))).contains("非空格子"))
        val crossed = parsed(text.replace("[\"p0r1c1\"]", "[\"p0r1c1\",\"p0r1c2\"]"), listOf(cell, other))
        assertTrue(first(crossed).isNull("weekday") && first(crossed).isNull("startMinute"))

        // The source and local summary agree; only the model's numeric end is wrong.
        val matchingSource = parsed(text.replace("\"cellRefs\"", "\"sourceLine\":\"19:00–21:30\",\"cellRefs\""))
        assertEquals(1140, first(matchingSource).getInt("startMinute"))
        assertEquals(1290, first(matchingSource).getInt("endMinute"))
        assertEquals("[]", warnings(matchingSource))

        // An explicitly shorter course inside the cell must not inherit the whole row.
        val shorterBlock = parsed(text, listOf(cell + mapOf("texts" to listOf("课程甲 19:00–19:30"))))
        assertTrue(first(shorterBlock).isNull("startMinute") && first(shorterBlock).isNull("endMinute"))
        assertTrue(warnings(shorterBlock).contains("钟点"))

        // Another screenshot can add a week or room despite sharing title and slot.
        val firstVersion = cell + mapOf("texts" to listOf("课程甲 第4周 A教室"))
        for (newText in listOf("课程甲 第5周 A教室", "课程甲 第4周 B教室")) {
            val additional = cell + mapOf("id" to "p1r1c1", "imageIndex" to 1, "texts" to listOf(newText))
            val missingVersion = parsed(text, listOf(firstVersion, additional))
            assertTrue(warnings(missingVersion).contains("1个非空格子"))
            assertTrue(warnings(missingVersion).contains("图2"))
        }

        // Deduplication must keep both screenshot references, before and after correction.
        val repeatedCell = cell + mapOf("id" to "p1r1c1", "imageIndex" to 1)
        for (repeatedEnd in listOf(1170, 1290)) {
            val repeated = JSONObject(text)
            val meetings = repeated.getJSONArray("courses").getJSONObject(0).getJSONArray("meetings")
            val duplicate = JSONObject(meetings.getJSONObject(0).toString())
                .put("endMinute", repeatedEnd).put("cellRefs", JSONArray().put("p1r1c1"))
            meetings.put(duplicate)
            val merged = parsed(repeated.toString(), listOf(cell, repeatedCell))
            assertEquals(1, merged.getJSONArray("meetings").length())
            assertEquals(1290, first(merged).getInt("endMinute"))
            assertEquals("[\"p0r1c1\",\"p1r1c1\"]", first(merged).getJSONObject("raw").getJSONArray("cellRefs").toString())
            assertEquals(2, first(merged).getJSONObject("raw").getJSONArray("localGridCells").length())
            assertEquals("[]", warnings(merged))
        }
        expect(DeepSeekTimetableClientError.TruncatedResponse) {
            DeepSeekTimetableClient.parseResponse(envelope(text, "length"), listOf(cell))
        }
    }

    @Test
    fun sourceLineRepairsClosedWeekRangeAndSunday() {
        val range = courses(
            """{"courses":[{"name":"英语","meetings":[{"weekday":5,"weeks":[6,11],"startMinute":810,"endMinute":990,"location":"6406","sourceLine":"6-11周一-下午课-6406","gridWeekday":1,"gridWeeks":"6-11"}]}]}"""
        ).getJSONObject(0).getJSONArray("meetings").getJSONObject(0)
        assertEquals(1, range.getInt("weekday"))
        assertEquals(listOf(6, 7, 8, 9, 10, 11), (0 until range.getJSONArray("weeks").length()).map { range.getJSONArray("weeks").getInt(it) })
        val sunday = courses(
            """{"courses":[{"name":"摄影","meetings":[{"weekday":5,"weeks":[5],"startMinute":540,"endMinute":720,"location":"虚拟教室1","sourceLine":"5周日-上午课-虚拟教室1","gridWeekday":7,"gridWeeks":"5"}]}]}"""
        ).getJSONObject(0).getJSONArray("meetings").getJSONObject(0)
        assertEquals(7, sunday.getInt("weekday"))
    }

    @Test
    fun scheduleEvidenceConflictsStayPendingAndExactRepeatsAreRemoved() {
        val conflicting = courses(
            """{"courses":[{"name":"证据冲突","sourceKind":"list","titleText":"证据冲突","listRows":["6-12周三","14周二"],"meetings":[{"listRow":1,"weekday":3,"weeks":[6,7,8,9,10,11,12],"startMinute":540,"endMinute":720,"sourceLine":"6-12周三","gridWeekday":4,"gridWeeks":"6-10"}]}]}"""
        ).getJSONObject(0)
        val row = conflicting.getJSONArray("meetings").getJSONObject(0)
        assertTrue(row.isNull("weekday") && row.isNull("weeks"))
        assertTrue(conflicting.getString("pendingReason").contains("名单有2条安排，识别为1条"))
        assertEquals(4, row.getJSONObject("raw").getInt("gridWeekday"))
        val unsupported = courses(
            """{"courses":[{"name":"无网格证据","meetings":[{"weekday":4,"weeks":[6,7,8,9,10],"sourceLine":"6-12周三"}]}]}"""
        ).getJSONObject(0).getJSONArray("meetings").getJSONObject(0)
        assertTrue(unsupported.isNull("weekday") && unsupported.isNull("weeks"))
        val repeated = courses(
            """{"courses":[{"name":"重复节次","listedMeetingCount":1,"sourceLine":"12周二","meetings":[{"weekday":4,"weeks":[3,4],"startMinute":540,"endMinute":720,"location":"A"},{"weekday":4,"weeks":[3,4],"startMinute":540,"endMinute":720,"location":"A"}]}]}"""
        ).getJSONObject(0)
        assertEquals(1, repeated.getJSONArray("meetings").length())
        val kept = repeated.getJSONArray("meetings").getJSONObject(0)
        assertEquals(4, kept.getInt("weekday"))
        assertEquals("[3,4]", kept.getJSONArray("weeks").toString())
        assertTrue(repeated.isNull("pendingReason"))
        assertEquals(listOf(6,7,8,9,10,12), DeepSeekTimetableClient.schedulePrefix("6–10、12 周二")?.first)
        assertNull(DeepSeekTimetableClient.schedulePrefix("3-11周 三楼报告厅"))
        assertEquals(4, DeepSeekTimetableClient.schedulePrefix("3-11周四上午")?.second)
        assertNull(DeepSeekTimetableClient.schedulePrefix("1-7周二（单 周）"))
    }

    @Test
    fun titleSectionAndListEvidenceAreNotInvented() {
        val identity = courses(
            """{"courses":[{"name":"专题甲-2","titleText":"专题甲-2","section":"2","sectionSource":"titleSuffix","sourceKind":"grid","listedMeetingCount":9,"listRows":["伪名单"],"meetings":[{"weekday":2,"weeks":[3],"startMinute":540,"endMinute":720}]},{"name":"专题乙","titleText":"专题甲","sourceKind":"grid","meetings":[{"weekday":2,"weeks":[3],"startMinute":540,"endMinute":720}]},{"name":"设计-2","titleText":"设计-2","sourceKind":"grid","meetings":[{"weekday":2,"weeks":[3],"startMinute":540,"endMinute":720}]}]}"""
        )
        assertEquals("专题甲", identity.getJSONObject(0).getString("name"))
        assertEquals("2", identity.getJSONObject(0).getString("section"))
        val raw = identity.getJSONObject(0).getJSONObject("raw")
        assertTrue(raw.isNull("listRows") && raw.isNull("listedMeetingCount"))
        assertEquals("专题乙", identity.getJSONObject(1).getString("name"))
        assertTrue(identity.getJSONObject(1).getJSONObject("raw").getJSONArray("recognitionWarnings").toString().contains("课名与标题原文不一致"))
        assertEquals("设计-2", identity.getJSONObject(2).getString("name"))
        assertTrue(identity.getJSONObject(2).isNull("section"))
        val numbered = courses(
            """{"courses":[{"name":"设计-2","titleText":"设计-2","section":"2","sectionSource":"field","sourceKind":"list","listRows":[],"meetings":[],"pendingReason":"待定"}]}"""
        ).getJSONObject(0)
        assertEquals("设计-2", numbered.getString("name"))
        val constructedTitle = courses(
            """{"courses":[{"name":"专题甲","titleText":"专题甲-2","section":"2","sectionSource":"field","sourceKind":"list","listRows":[],"meetings":[],"pendingReason":"待定"}]}"""
        ).getJSONObject(0)
        assertTrue(constructedTitle.getJSONObject("raw").getJSONArray("recognitionWarnings").toString().contains("课名与标题原文不一致"))
        val coverage = courses(
            """{"courses":[{"name":"专题甲","titleText":"专题甲","sourceKind":"list","listRows":["3周二上午A","4周三上午B"],"meetings":[{"listRow":1,"weekday":2,"weeks":[3],"startMinute":540,"endMinute":720,"location":"A"},{"listRow":1,"weekday":2,"weeks":[3],"startMinute":810,"endMinute":990,"location":"A"}]}]}"""
        ).getJSONObject(0)
        assertTrue(coverage.getJSONObject("raw").getJSONArray("recognitionWarnings").toString().contains("名单第2行未对应"))
        val alternating = courses(
            """{"courses":[{"name":"专题甲","meetings":[{"sourceLine":"1-7周二(单周)","weekday":2,"weeks":[1,3,5,7],"gridWeekday":2,"gridWeeks":[1,3,5,7],"startMinute":540,"endMinute":720}]}]}"""
        ).getJSONObject(0).getJSONArray("meetings").getJSONObject(0)
        assertEquals("[1,3,5,7]", alternating.getJSONArray("weeks").toString())
    }

    @Test
    fun pendingOnlyListLinesDoNotShiftReferencesOrHideScheduledContactLines() {
        val firstLine = "3周二-上午课-A"
        val pendingLine = "请与任课教师联系确认安排"
        val lastLine = "4周三-下午课-B"
        val mixed = courses(
            """{"courses":[{"name":"课程甲","titleText":"课程甲","sourceKind":"list","listRows":["$firstLine","$pendingLine","$lastLine"],"meetings":[{"listRow":1,"weekday":2,"weeks":[3],"startMinute":540,"endMinute":720,"location":"A"},{"listRow":3,"weekday":3,"weeks":[4],"startMinute":810,"endMinute":990,"location":"B"}]}]}"""
        ).getJSONObject(0)
        val mixedRaw = mixed.getJSONObject("raw")
        val meetings = mixed.getJSONArray("meetings")
        assertEquals(2, mixedRaw.getInt("listedMeetingCount"))
        assertEquals(JSONArray(listOf(firstLine, lastLine)).toString(), mixedRaw.getJSONArray("listRows").toString())
        assertEquals(2, meetings.length())
        assertEquals(firstLine, meetings.getJSONObject(0).getString("sourceReference"))
        assertEquals(lastLine, meetings.getJSONObject(1).getString("sourceReference"))
        assertEquals(1, meetings.getJSONObject(0).getJSONObject("raw").getInt("listRow"))
        assertEquals(2, meetings.getJSONObject(1).getJSONObject("raw").getInt("listRow"))
        assertEquals("[]", mixedRaw.getJSONArray("recognitionWarnings").toString())
        assertTrue(mixed.isNull("pendingReason"))
        assertTrue(mixedRaw.getJSONArray("ignoredPendingListRows").toString().contains(pendingLine))

        val placeholder = "teachtask/week.null 请与任课教师联系"
        val pending = courses(
            """{"courses":[{"name":"课程乙","titleText":"课程乙","sourceKind":"list","listRows":["$placeholder"],"meetings":[],"pendingReason":"请与任课教师联系"}]}"""
        ).getJSONObject(0)
        val pendingRaw = pending.getJSONObject("raw")
        assertEquals(0, pending.getJSONArray("meetings").length())
        assertEquals(0, pendingRaw.getInt("listedMeetingCount"))
        assertEquals("[]", pendingRaw.getJSONArray("listRows").toString())
        assertEquals("[]", pendingRaw.getJSONArray("recognitionWarnings").toString())
        assertTrue(pendingRaw.getJSONArray("ignoredPendingListRows").toString().contains(placeholder))

        val scheduledContact = "6-10周二-上午课-A；请与任课教师联系"
        val scheduled = courses(
            """{"courses":[{"name":"课程丙","titleText":"课程丙","sourceKind":"list","listRows":["$scheduledContact"],"meetings":[{"listRow":1,"weekday":2,"weeks":[6,7,8,9,10],"startMinute":540,"endMinute":720,"location":"A"}]}]}"""
        ).getJSONObject(0)
        val scheduledRaw = scheduled.getJSONObject("raw")
        assertEquals(1, scheduledRaw.getInt("listedMeetingCount"))
        assertEquals(scheduledContact, scheduledRaw.getJSONArray("listRows").getString(0))
        assertEquals("[]", scheduledRaw.getJSONArray("recognitionWarnings").toString())
        assertEquals("[]", scheduledRaw.getJSONArray("ignoredPendingListRows").toString())
        assertEquals("[6,7,8,9,10]", scheduled.getJSONArray("meetings").getJSONObject(0).getJSONArray("weeks").toString())
    }

    @Test
    fun validResponseKeepsScheduledCourse() {
        val result = DeepSeekTimetableClient.parseResponse(envelope(valid))
        assertEquals("stop", result.finishReason)
        assertEquals(1, JSONObject(result.jsonText).getJSONArray("courses").length())
    }

    @Test
    fun rejectsBrokenAndEmptyJson() {
        expect(DeepSeekTimetableClientError.InvalidJSON) {
            DeepSeekTimetableClient.parseResponse(envelope("{broken"))
        }
        expect(DeepSeekTimetableClientError.EmptyCourses) {
            DeepSeekTimetableClient.parseResponse(envelope("""{"courses":[]}"""))
        }
        expect(DeepSeekTimetableClientError.InvalidCourseField("courses")) {
            DeepSeekTimetableClient.parseResponse(envelope("{}"))
        }
    }

    @Test
    fun rejectsMalformedFields() {
        val cases = listOf(
            Triple("\"weekday\":1", "\"weekday\":true", "weekday"),
            Triple("\"weekday\":1", "\"weekday\":8", "weekday"),
            Triple("\"weeks\":[3,4,6]", "\"weeks\":[0]", "weeks"),
            Triple("\"weeks\":[3,4,6]", "\"weeks\":\"3周4周\"", "weeks"),
            Triple("\"endMinute\":600", "\"endMinute\":500", "endMinute"),
            Triple("\"startMinute\":540", "\"startMinute\":540.5", "startMinute"),
            Triple("\"location\":null", "\"location\":123", "location")
        )
        for ((old, new, field) in cases) {
            expect(DeepSeekTimetableClientError.InvalidCourseField("courses[0].meetings[0].$field")) {
                DeepSeekTimetableClient.parseResponse(envelope(valid.replace(old, new)))
            }
        }
    }

    @Test
    fun acceptsFencedAndReferenceShapes() {
        assertEquals(1, courses("```json\n$valid\n```").length())
        val reference =
            """{"scheduled":[{"title":"艺术史","weekday":"周一","weeks":"3,4,6-7","startTime":"13:30","endTime":"16:30","room":"6406","sourceLine":"3,4,6-7周一下午"},{"title":"艺术史","weekday":"周一","weeks":"8","startTime":"19:00","endTime":"21:30","room":"6407"}],"pending":[{"title":"导师课","reason":"联系老师"}]}"""
        val rows = courses(reference)
        assertEquals(3, rows.length())
        val meeting = rows.getJSONObject(0).getJSONArray("meetings").getJSONObject(0)
        assertEquals(listOf(3, 4, 6, 7), jsonInts(meeting.getJSONArray("weeks")))
        assertEquals(810, meeting.getInt("startMinute"))
        assertEquals(990, meeting.getInt("endMinute"))
        assertEquals("3,4,6-7周一下午", meeting.getString("sourceReference"))
        assertTrue(rows.getJSONObject(0).isNull("teacher"))
        assertTrue(rows.getJSONObject(2).isNull("teacher"))
        assertEquals(0, rows.getJSONObject(2).getJSONArray("meetings").length())
    }

    @Test
    fun recognizedTeacherClassAndRoomAreKeptWithoutInventingTime() {
        val meetingTeacher = courses(
            """{"courses":[{"name":"中国画","teacher":null,"meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":"6406","teacher":"葛玉清"}]}]}""",
        )
        assertEquals("葛玉清", meetingTeacher.getJSONObject(0).getString("teacher"))

        val labeled = courses(
            """{"courses":[{"name":"中国画","teacher":null,"sourceLine":"中国画 教师：葛玉清 周一","meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":null}]}]}""",
        )
        assertEquals("葛玉清", labeled.getJSONObject(0).getString("teacher"))

        val unlabeled = courses(
            """{"courses":[{"name":"中国画","teacher":null,"sourceLine":"中国画 葛玉清 周一","meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":null}]}]}""",
        )
        assertTrue(unlabeled.getJSONObject(0).isNull("teacher"))

        val conflict = courses(
            """{"courses":[{"name":"中国画","teacher":null,"meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":null,"teacher":"葛玉清"},{"weekday":2,"weeks":[1],"startMinute":540,"endMinute":630,"location":null,"teacher":"李老师"}]}]}""",
        )
        assertTrue(conflict.getJSONObject(0).isNull("teacher"))

        val aliases = courses(
            """{"courses":[{"name":"中国画","课程代码":"ART-01","教学班":"一班","教师":"葛玉清","教室":"6406","meetings":[{"weekday":1,"weeks":null,"startMinute":null,"endMinute":null,"location":null}]}]}""",
        )
        val alias = aliases.getJSONObject(0)
        assertEquals("ART-01", alias.getString("courseCode"))
        assertEquals("一班", alias.getString("section"))
        assertEquals("葛玉清", alias.getString("teacher"))
        val aliasMeeting = alias.getJSONArray("meetings").getJSONObject(0)
        assertEquals("6406", aliasMeeting.getString("location"))
        assertTrue(aliasMeeting.isNull("weeks"))
        assertTrue(aliasMeeting.isNull("startMinute"))
        assertTrue(aliasMeeting.isNull("endMinute"))

        val explicitRoom = courses(
            """{"courses":[{"name":"中国画","教室":"其他","meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":"6406"}]}]}""",
        )
        assertEquals(
            "6406",
            explicitRoom.getJSONObject(0).getJSONArray("meetings").getJSONObject(0).getString("location"),
        )

        val placeholder = courses(
            """{"courses":[{"name":"导师课","teacher":"待定","meetings":[],"pendingReason":"联系老师"}]}""",
        )
        assertTrue(placeholder.getJSONObject(0).isNull("teacher"))
        assertEquals(0, placeholder.getJSONObject(0).getJSONArray("meetings").length())

        val ignoredAlias = courses(
            """{"courses":[{"name":"中国画","教师":123,"meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":null}]}]}""",
        )
        assertTrue(ignoredAlias.getJSONObject(0).isNull("teacher"))
        expect(DeepSeekTimetableClientError.InvalidCourseField("courses[0].teacher")) {
            DeepSeekTimetableClient.parseResponse(
                envelope(valid.replace("\"teacher\":null", "\"teacher\":123")),
            )
        }
    }

    @Test
    fun partialClockNeverFabricatesInterval() {
        val incomplete =
            courses("""{"courses":[{"name":"未知安排","meetings":[{"weekday":1,"weeks":[],"startMinute":810}]}]}""")
                .getJSONObject(0)
        val partial = incomplete.getJSONArray("meetings").getJSONObject(0)
        assertTrue(partial.isNull("startMinute"))
        assertTrue(partial.isNull("endMinute"))
        assertEquals(810, partial.getJSONObject("raw").getInt("knownStartMinute"))
        assertTrue(incomplete.getString("pendingReason").isNotEmpty())
        assertTrue(partial.isNull("weeks"))
    }

    @Test
    fun rejectsProseAndTruncation() {
        expect(DeepSeekTimetableClientError.InvalidJSON) {
            DeepSeekTimetableClient.parseResponse(envelope("结果是$valid"))
        }
        expect(DeepSeekTimetableClientError.TruncatedResponse) {
            DeepSeekTimetableClient.parseResponse(envelope(valid, "length"))
        }
        for (reason in listOf(null, "content_filter", "tool_calls")) {
            expect(DeepSeekTimetableClientError.InvalidResponse) {
                DeepSeekTimetableClient.parseResponse(envelope(valid, reason))
            }
        }
    }

    @Test
    fun pendingAndUnknownWeeksSurvive() {
        val pending = courses("""{"courses":[{"name":"导师课","meetings":[],"pendingReason":"时间待定"}]}""")
        assertEquals("导师课", pending.getJSONObject(0).getString("name"))
        val missingWeeks = valid.replace("\"weeks\":[3,4,6]", "\"weeks\":null")
            .replace("\"pendingReason\":null", "\"pendingReason\":\"周次待核对\"")
        assertTrue(courses(missingWeeks).getJSONObject(0).getJSONArray("meetings").getJSONObject(0).isNull("weeks"))
    }

    private fun jsonInts(array: JSONArray): List<Int> = List(array.length()) { array.getInt(it) }
}
