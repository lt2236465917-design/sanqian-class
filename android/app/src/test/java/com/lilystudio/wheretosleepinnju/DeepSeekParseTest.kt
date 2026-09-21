package com.lilystudio.wheretosleepinnju

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
        assertEquals(0, rows.getJSONObject(2).getJSONArray("meetings").length())
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
