package com.lilystudio.wheretosleepinnju

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

data class SchoolPortalTableCell(val text: String, val rowSpan: Int = 1, val colSpan: Int = 1)

data class SchoolPortalFrameIdentity(val url: String, val securityOrigin: String, val isMainFrame: Boolean)

data class SchoolPortalFrameMessage(
    val version: Int,
    val kind: String,
    val requestID: String,
    val frame: SchoolPortalFrameIdentity,
    val title: String,
    val innerText: String,
    val html: String,
    val rows: List<List<SchoolPortalTableCell>>,
    val truncated: Boolean? = null
) {
    val isExtractionMessage: Boolean get() = kind == "scheduleTables" && version == CURRENT_VERSION

    companion object {
        const val CURRENT_VERSION = 1

        fun fromJson(body: Any): SchoolPortalFrameMessage? {
            val obj = when (body) {
                is JSONObject -> body
                is String -> try { JSONObject(body) } catch (_: Exception) { return null }
                is Map<*, *> -> JSONObject(body)
                else -> return null
            }
            return try {
                val frameObj = obj.optJSONObject("frame") ?: return null
                val rowsJson = obj.optJSONArray("rows") ?: return null
                val rows = mutableListOf<List<SchoolPortalTableCell>>()
                for (r in 0 until rowsJson.length()) {
                    val rowJson = rowsJson.optJSONArray(r) ?: return null
                    val row = mutableListOf<SchoolPortalTableCell>()
                    for (c in 0 until rowJson.length()) {
                        val cell = rowJson.optJSONObject(c) ?: return null
                        row.add(
                            SchoolPortalTableCell(
                                text = cell.optString("text"),
                                rowSpan = cell.optInt("rowSpan", 1),
                                colSpan = cell.optInt("colSpan", 1)
                            )
                        )
                    }
                    rows.add(row)
                }
                val message = SchoolPortalFrameMessage(
                    version = obj.optInt("version"),
                    kind = obj.optString("kind"),
                    requestID = obj.optString("requestID"),
                    frame = SchoolPortalFrameIdentity(
                        url = frameObj.optString("url"),
                        securityOrigin = frameObj.optString("securityOrigin"),
                        isMainFrame = frameObj.optBoolean("isMainFrame")
                    ),
                    title = obj.optString("title"),
                    innerText = obj.optString("innerText"),
                    html = obj.optString("html"),
                    rows = rows,
                    truncated = if (obj.has("truncated") && !obj.isNull("truncated")) obj.optBoolean("truncated") else null
                )
                if (message.isExtractionMessage) message else null
            } catch (_: Exception) {
                null
            }
        }
    }
}

data class SchoolScheduleDraft(
    val source: String,
    var courseCode: String? = null,
    var classCode: String? = null,
    var title: String,
    var teacher: String,
    var location: String,
    var weekday: Int? = null,
    var weeks: List<Int>? = null,
    var startMinutes: Int? = null,
    var endMinutes: Int? = null,
    var term: String? = null,
    var pendingReason: String? = null,
    var notes: String,
    var sourceURL: String? = null,
    var rawText: String,
    var startPeriod: Int? = null,
    var endPeriod: Int? = null
) {
    val isPending: Boolean
        get() = weekday == null || weeks == null || startMinutes == null || endMinutes == null

    val identityKey: String
        get() {
            val weekKey = weeks?.joinToString(",") ?: "?"
            return listOf(
                courseCode ?: title,
                classCode ?: "",
                teacher,
                (weekday ?: 0).toString(),
                (startMinutes ?: -1).toString(),
                (endMinutes ?: -1).toString(),
                (startPeriod ?: -1).toString(),
                (endPeriod ?: -1).toString(),
                location,
                weekKey,
                if (isPending) rawText else ""
            ).joinToString("|")
        }
}

data class SchoolScheduleParseResult(
    val source: String,
    val sourceURL: String?,
    val frameCount: Int,
    val tableCount: Int,
    val drafts: List<SchoolScheduleDraft>,
    val warnings: List<String>,
    val timetableText: String? = null
) {
    val canReview: Boolean get() = drafts.isNotEmpty() || !(timetableText ?: "").isEmpty()
}

object SchoolPortalSecurity {
    val allowedHosts = setOf("iam.zgysyjy.org.cn", "access.zgysyjy.org.cn", "wxt.zgysyjy.org.cn")

    fun allows(scheme: String, host: String, allowed: Set<String> = allowedHosts): Boolean {
        return scheme.equals("https", true) && allowed.contains(host.lowercase())
    }

    fun sanitizedURL(value: String?): String? {
        if (value.isNullOrEmpty()) return null
        val cut = value.substringBefore('#').substringBefore('?')
        return try {
            val uri = URI(cut)
            val scheme = uri.scheme ?: return cut
            val host = uri.host ?: return cut
            if (!uri.userInfo.isNullOrEmpty()) return cut
            val port = uri.port
            val path = uri.path ?: ""
            val portPart = if (port == -1) "" else ":$port"
            "$scheme://$host$portPart$path"
        } catch (_: Exception) {
            cut
        }
    }
}

fun toJsonValue(value: Any?): Any {
    return when (value) {
        null -> JSONObject.NULL
        is JSONObject, is JSONArray -> value
        is Map<*, *> -> {
            val obj = JSONObject()
            value.forEach { (k, v) -> if (k is String) obj.put(k, toJsonValue(v)) }
            obj
        }
        is Collection<*> -> {
            val array = JSONArray()
            value.forEach { array.put(toJsonValue(it)) }
            array
        }
        else -> value
    }
}

fun SchoolScheduleDraft.toChannelCourse(): Map<String, Any?> {
    val meeting = hashMapOf<String, Any?>(
        "location" to location,
        "sourceReference" to rawText,
        "raw" to mapOf(
            "sourceURL" to (sourceURL ?: ""),
            "sourceText" to rawText,
            "startPeriod" to startPeriod,
            "endPeriod" to endPeriod
        ),
        "weekday" to weekday,
        "weeks" to weeks,
        "startMinute" to startMinutes,
        "endMinute" to endMinutes
    )
    return hashMapOf(
        "name" to title,
        "teacher" to teacher,
        "meetings" to listOf(meeting),
        "courseCode" to courseCode,
        "section" to classCode,
        "pendingReason" to pendingReason
    )
}

fun SchoolScheduleParseResult.toChannelMap(): Map<String, Any?> {
    return hashMapOf(
        "courses" to drafts.map { it.toChannelCourse() },
        "warnings" to warnings,
        "timetableText" to timetableText
    )
}

fun encodeTimetableCells(tables: List<List<List<SchoolPortalTableCell>>>): ByteArray {
    val root = JSONArray()
    for (table in tables) {
        val tableJson = JSONArray()
        for (row in table) {
            val rowJson = JSONArray()
            for (cell in row) {
                rowJson.put(
                    JSONObject()
                        .put("text", cell.text)
                        .put("rowSpan", cell.rowSpan)
                        .put("colSpan", cell.colSpan)
                )
            }
            tableJson.put(rowJson)
        }
        root.put(tableJson)
    }
    return root.toString().toByteArray(Charsets.UTF_8)
}
