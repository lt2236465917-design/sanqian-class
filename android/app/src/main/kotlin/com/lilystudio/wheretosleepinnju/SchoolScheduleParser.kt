package com.lilystudio.wheretosleepinnju

object SchoolScheduleParser {
    private val weekdayNames = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    private val weekdayShortNames = listOf("星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日")
    private val sensitiveMaterial = Regex(
        """<[^>]+>|https?://|(?:password|passwd|cookie|authorization|samlresponse|学号|密码|验证码|身份证|手机号)""",
        RegexOption.IGNORE_CASE
    )

    fun parse(
        tables: List<SchoolPortalFrameMessage>,
        source: String = "school-portal",
        frameCount: Int? = null,
        sourceURL: String? = null
    ): SchoolScheduleParseResult {
        val usable = tables.filter { it.isExtractionMessage }
        val all = mutableListOf<SchoolScheduleDraft>()
        val warnings = mutableListOf<String>()
        for (table in usable) {
            val parsed = parseTable(table, source, SchoolPortalSecurity.sanitizedURL(sourceURL ?: table.frame.url))
            all.addAll(parsed.first)
            warnings.addAll(parsed.second)
        }
        val deduped = deduplicate(all)
        if (deduped.isEmpty() && usable.isNotEmpty()) {
            warnings.add("未找到可确认的课程安排；缺少字段的行会保留为待定项。")
        }
        val material = timetableMaterial(usable)
        warnings.addAll(material.second)
        return SchoolScheduleParseResult(
            source = source,
            sourceURL = SchoolPortalSecurity.sanitizedURL(sourceURL ?: usable.firstOrNull()?.frame?.url),
            frameCount = frameCount ?: usable.map { it.frame.url }.toSet().size,
            tableCount = usable.size,
            drafts = deduped,
            warnings = warnings.distinct(),
            timetableText = material.first
        )
    }

    fun parse(message: SchoolPortalFrameMessage): SchoolScheduleParseResult {
        return parse(listOf(message), source = "school-portal", frameCount = 1, sourceURL = message.frame.url)
    }

    fun parseHTML(html: String, sourceURL: String? = null, source: String = "school-portal-html"): SchoolScheduleParseResult {
        val slices = HTMLTableExtractor.extract(html)
        val messages = slices.mapIndexed { index, slice ->
            SchoolPortalFrameMessage(
                version = SchoolPortalFrameMessage.CURRENT_VERSION,
                kind = "scheduleTables",
                requestID = "html-$index",
                frame = SchoolPortalFrameIdentity(
                    url = sourceURL ?: "",
                    securityOrigin = sourceURL?.let { runCatching { java.net.URI(it).host }.getOrNull() } ?: "",
                    isMainFrame = true
                ),
                title = "",
                innerText = slice.rows.flatten().joinToString("\n") { it.text },
                html = slice.html,
                rows = slice.rows
            )
        }
        return parse(messages, source = source, frameCount = 1, sourceURL = sourceURL)
    }

    private fun timetableMaterial(tables: List<SchoolPortalFrameMessage>): Pair<String?, List<String>> {
        val sourceTables = mutableListOf<List<List<SchoolPortalTableCell>>>()
        for (table in tables) {
            val header = table.rows.indexOfFirst { row ->
                val text = row.joinToString(" ") { it.text }
                val list = Regex("课程名称|课程名|科目|教学科目").containsMatchIn(text) &&
                    Regex("上课|时间|地点|安排|周次").containsMatchIn(text)
                val grid = Regex("周一|星期一").containsMatchIn(text) && Regex("周二|星期二").containsMatchIn(text)
                list || grid
            }
            if (header < 0 || table.rows.size <= header + 1) continue
            if (table.truncated == true) {
                return null to listOf("网页课表未完整读取，请分页面读取或使用完整课表截图；本次无法发送原文给 AI。")
            }
            val rows = table.rows.drop(header)
            if (sourceTables.none { it == rows }) sourceTables.add(rows)
        }
        if (sourceTables.isEmpty()) return null to emptyList()
        val texts = sourceTables.flatten().flatten().joinToString("\n") { it.text }
        if (sensitiveMaterial.containsMatchIn(texts)) {
            return null to listOf("课表中混有登录信息或链接，本次不提供 AI 原文识别；请打开独立课表页后重试。")
        }
        val data = encodeTimetableCells(sourceTables)
        if (data.size > 64_000) {
            return null to listOf("课表原文过长，本次不发送给 AI；请分页面读取或分批导入截图。")
        }
        return String(data, Charsets.UTF_8) to emptyList()
    }

    private fun parseTable(
        table: SchoolPortalFrameMessage,
        source: String,
        sourceURL: String?
    ): Pair<List<SchoolScheduleDraft>, List<String>> {
        val rows = expand(table.rows).map { row -> row.map { normalize(it) } }
        if (rows.isEmpty()) return emptyList<SchoolScheduleDraft>() to listOf("表格没有数据行。")
        val header = rows.indexOfFirst { isLikelyHeader(it) }
        if (header >= 0) {
            val indices = columnIndices(rows[header])
            val body = rows.drop(header + 1)
            val drafts = body.flatMap { parseListRow(it, indices, source, sourceURL) }
            if (drafts.isNotEmpty()) return drafts to emptyList()
        }
        return parseWeeklyGrid(rows, table.rows, source, sourceURL)
    }

    private fun isLikelyHeader(row: List<String>): Boolean {
        val blob = row.joinToString("|")
        return (blob.contains("课程名称") || blob.contains("课程")) &&
            (blob.contains("上课") || blob.contains("时间") || blob.contains("地点"))
    }

    private data class ColumnIndices(
        val code: Int?,
        val classCode: Int?,
        val title: Int?,
        val teacher: Int?,
        val meeting: Int?,
        val location: Int?,
        val weeks: Int?,
        val weekday: Int?
    )

    private fun columnIndices(header: List<String>): ColumnIndices {
        fun find(values: List<String>): Int? {
            header.indexOfFirst { cell -> values.any { cell == it } }.takeIf { it >= 0 }?.let { return it }
            return header.indexOfFirst { cell -> values.filter { it.length > 1 }.any { cell.contains(it) } }
                .takeIf { it >= 0 }
        }
        return ColumnIndices(
            code = find(listOf("课程编号", "课程编码", "课程号")),
            classCode = find(listOf("教学班", "班号")),
            title = find(listOf("课程名称", "课程名", "课程")),
            teacher = find(listOf("任课教师", "教师", "老师")),
            meeting = find(listOf("上课时间", "上课周次", "时间", "安排")),
            location = find(listOf("上课地点", "地点", "教室")),
            weeks = find(listOf("周次")),
            weekday = find(listOf("星期"))
        )
    }

    private fun parseListRow(
        row: List<String>,
        indices: ColumnIndices,
        source: String,
        sourceURL: String?
    ): List<SchoolScheduleDraft> {
        fun value(index: Int?): String = if (index != null && index < row.size) row[index] else ""
        val title = value(indices.title)
        if (title.length < 2 || title.contains("课程名称")) return emptyList()
        var weeks = value(indices.weeks)
        if (weeks.isNotEmpty() && !weeks.contains("周")) weeks += "周"
        val raw = value(indices.meeting)
        return splitMeetings(raw).map { part ->
            val text = "$part $weeks ${value(indices.weekday)}"
            val time = parseTimeRange(text)
            val periods = parsePeriods(text)
            val knownWeeks = parseWeeks(text)
            val day = dayNumber(text)
            SchoolScheduleDraft(
                source = source,
                courseCode = value(indices.code).ifEmpty { null },
                classCode = value(indices.classCode).ifEmpty { null },
                title = title,
                teacher = value(indices.teacher),
                location = value(indices.location),
                weekday = day,
                weeks = knownWeeks,
                startMinutes = time?.first,
                endMinutes = time?.second,
                pendingReason = if (time == null || knownWeeks == null || day == null) "缺少可确认的星期、周次或钟点；节次需按作息核对" else null,
                notes = part,
                sourceURL = sourceURL,
                rawText = row.joinToString(" | ") + " | " + part,
                startPeriod = periods?.first,
                endPeriod = periods?.second
            )
        }
    }

    fun splitMeetings(text: String): List<String> {
        val parts = text.split(Regex("[;；\n]")).map { it.trim() }.filter { it.isNotEmpty() }
        val groups = parts.ifEmpty { listOf(text) }
        return groups.flatMap { part ->
            val days = matches("""(?:周|星期)[一二三四五六日天]""", part)
            if (days.size <= 1) {
                val clocks = matches("""\d{1,2}[:：]\d{2}\s*[-~至到]\s*\d{1,2}[:：]\d{2}""", part)
                if (clocks.size <= 1) listOf(part)
                else {
                    val prefix = part.substring(0, clocks[0].range.first)
                    clocks.indices.map { i ->
                        val end = if (i + 1 < clocks.size) clocks[i + 1].range.first else part.length
                        prefix + part.substring(clocks[i].range.first, end)
                    }
                }
            } else {
                days.indices.map { index ->
                    val start = if (index == 0) 0 else days[index].range.first
                    val end = if (index + 1 < days.size) days[index + 1].range.first else part.length
                    part.substring(start, end)
                }
            }
        }
    }

    fun parseWeeks(text: String): List<Int>? {
        val groups = matches(
            """(?<![\d:：])(?:第\s*)?(\d{1,2}(?:\s*[-~至到]\s*\d{1,2})?(?:\s*[,，、]\s*\d{1,2}(?:\s*[-~至到]\s*\d{1,2})?)*)\s*周""",
            text
        )
        if (groups.isEmpty()) return null
        var values = mutableSetOf<Int>()
        for (group in groups) {
            val sequence = group.group(1) ?: return null
            for (part in sequence.split(Regex("[,，、]"))) {
                val numbers = matches("""\d+""", part).mapNotNull { it.value.toIntOrNull() }
                val first = numbers.firstOrNull() ?: return null
                if (first !in 1..60) return null
                val last = numbers.lastOrNull() ?: first
                if (last !in first..60) return null
                values.addAll(first..last)
            }
        }
        if (text.contains("单周") || text.contains("(单)") || text.contains("（单）")) {
            values = values.filter { it % 2 == 1 }.toMutableSet()
        }
        if (text.contains("双周") || text.contains("(双)") || text.contains("（双）")) {
            values = values.filter { it % 2 == 0 }.toMutableSet()
        }
        return if (values.isEmpty()) null else values.sorted()
    }

    fun parseTimeRange(text: String): Pair<Int, Int>? {
        val found = matches(
            """(?<!\d)(\d{1,2})\s*[:：]\s*(\d{2})\s*[-~至到]\s*(\d{1,2})\s*[:：]\s*(\d{2})(?!\d)""",
            text
        )
        if (found.size != 1) return null
        val match = found.first()
        val h1 = match.group(1)?.toIntOrNull() ?: return null
        val m1 = match.group(2)?.toIntOrNull() ?: return null
        val h2 = match.group(3)?.toIntOrNull() ?: return null
        val m2 = match.group(4)?.toIntOrNull() ?: return null
        if (h1 !in 0..23 || h2 !in 0..23 || m1 !in 0..59 || m2 !in 0..59) return null
        val start = h1 * 60 + m1
        val end = h2 * 60 + m2
        return if (end > start) start to end else null
    }

    fun parsePeriods(text: String): Pair<Int, Int>? {
        val match = matches("""第\s*(\d{1,2})(?:\s*[-~至到]\s*(\d{1,2}))?\s*节""", text).firstOrNull() ?: return null
        val first = match.group(1)?.toIntOrNull() ?: return null
        val last = match.group(2)?.toIntOrNull() ?: first
        if (first !in 1..30 || last !in first..30) return null
        return first to last
    }

    fun expand(rows: List<List<SchoolPortalTableCell>>): List<List<String>> {
        val grid = Array(minOf(rows.size + 128, 256)) { arrayOfNulls<String>(32) }
        var width = 0
        for ((r, row) in rows.take(128).withIndex()) {
            var c = 0
            for (cell in row.take(32)) {
                while (c < 32 && grid[r][c] != null) c++
                if (c >= 32) break
                val spanWidth = minOf(maxOf(cell.colSpan, 1), 32 - c)
                val spanHeight = minOf(maxOf(cell.rowSpan, 1), grid.size - r)
                for (rr in r until (r + spanHeight)) {
                    for (cc in c until (c + spanWidth)) {
                        if (grid[rr][cc] == null) grid[rr][cc] = cell.text
                    }
                }
                c += spanWidth
                width = maxOf(width, c)
            }
        }
        return grid.take(minOf(rows.size, 128)).map { row ->
            row.take(width).map { it ?: "" }
        }
    }

    private fun parseWeeklyGrid(
        rows: List<List<String>>,
        originalCells: List<List<SchoolPortalTableCell>>,
        source: String,
        sourceURL: String?
    ): Pair<List<SchoolScheduleDraft>, List<String>> {
        val headerIndex = rows.indexOfFirst { row ->
            row.count { cell ->
                weekdayNames.any { cell.contains(it) } || weekdayShortNames.any { cell.contains(it) }
            } >= 2
        }
        if (headerIndex < 0) return emptyList<SchoolScheduleDraft>() to listOf("未识别列表表头或周课表表头。")
        val mergedRows = originalCells.flatten().filter { it.rowSpan > 1 }.map { normalize(it.text) }.toSet()
        val mergedColumns = originalCells.flatten().filter { it.colSpan > 1 }.map { normalize(it.text) }.toSet()
        val header = rows[headerIndex]
        val dayColumns = linkedMapOf<Int, Int>()
        header.forEachIndexed { index, cell ->
            dayNumber(cell)?.let { dayColumns[index] = it }
        }
        if (dayColumns.size < 2) return emptyList<SchoolScheduleDraft>() to listOf("周课表缺少星期列。")
        val drafts = mutableListOf<SchoolScheduleDraft>()
        for (row in rows.drop(headerIndex + 1)) {
            val periodText = row.firstOrNull() ?: continue
            if (periodText.isEmpty()) continue
            for (column in dayColumns.keys.sorted()) {
                val day = dayColumns[column]!!
                if (column >= row.size) continue
                val cell = row[column]
                if (cell.isEmpty() || isHeaderLike(cell)) continue
                val lines = cell.split('\n').filter { it.isNotEmpty() }
                val firstLine = lines.firstOrNull() ?: cell
                val metadata = matches(
                    """(?:第)?\d{1,2}(?:[-~至到,，、]\d{1,2})*周|\d{1,2}[:：]\d{2}|课程编号[：:]|教师[：:]|地点[：:]""",
                    firstLine
                ).firstOrNull()
                val title = metadata?.let {
                    firstLine.substring(0, it.range.first).trim().ifEmpty { null }
                } ?: firstLine
                val meetingSource = if (lines.size > 1) lines.drop(1).joinToString("\n") else cell
                for (part in splitMeetings(meetingSource)) {
                    val text = (if (mergedRows.contains(cell)) "" else periodText) + " " + part
                    val resolvedDay = if (mergedColumns.contains(cell)) dayNumber(part) else day
                    val time = parseTimeRange(text)
                    val weeks = parseWeeks(text)
                    val periods = parsePeriods(text)
                    drafts.add(
                        SchoolScheduleDraft(
                            source = source,
                            title = title,
                            teacher = "",
                            location = "",
                            weekday = resolvedDay,
                            weeks = weeks,
                            startMinutes = time?.first,
                            endMinutes = time?.second,
                            pendingReason = if (time == null || weeks == null || resolvedDay == null) "周课表单元缺少明确周次、星期或钟点" else null,
                            notes = periodText,
                            sourceURL = sourceURL,
                            rawText = cell,
                            startPeriod = periods?.first,
                            endPeriod = periods?.second
                        )
                    )
                }
            }
        }
        return drafts to emptyList()
    }

    private fun deduplicate(drafts: List<SchoolScheduleDraft>): List<SchoolScheduleDraft> {
        val result = mutableListOf<SchoolScheduleDraft>()
        val indexes = mutableMapOf<String, Int>()
        for (draft in drafts) {
            if (draft.title.isEmpty()) continue
            val key = draft.identityKey
            val index = indexes[key]
            if (index != null) {
                val merged = result[index]
                if (merged.teacher.isEmpty()) merged.teacher = draft.teacher
                if (merged.location.isEmpty()) merged.location = draft.location
                if (merged.notes.isEmpty()) merged.notes = draft.notes
            } else {
                indexes[key] = result.size
                result.add(draft)
            }
        }
        return result
    }

    fun dayNumber(text: String): Int? {
        if (text.contains("周天") || text.contains("星期天")) return 7
        for (day in 1..7) {
            if (text.contains(weekdayNames[day - 1]) || text.contains(weekdayShortNames[day - 1])) return day
        }
        return null
    }

    private fun isHeaderLike(text: String): Boolean {
        return text == "课程名称" || weekdayNames.contains(text) || weekdayShortNames.contains(text)
    }

    fun normalize(text: String): String {
        return text.replace("\u00a0", " ")
            .replace("\r", "")
            .split('\n')
            .joinToString("\n") { line -> line.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ") }
            .trim()
    }

    private data class RxMatch(val value: String, val range: IntRange, private val groups: List<String?>) {
        fun group(index: Int): String? = groups.getOrNull(index)
    }

    private fun matches(pattern: String, text: String): List<RxMatch> {
        return Regex(pattern).findAll(text).map { match ->
            RxMatch(
                value = match.value,
                range = match.range,
                groups = match.groupValues
            )
        }.toList()
    }
}

private data class HTMLTableSlice(val html: String, val rows: List<List<SchoolPortalTableCell>>)

private object HTMLTableExtractor {
    fun extract(html: String): List<HTMLTableSlice> {
        val tableRegex = Regex("""<table\b[^>]*>.*?</table>""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        return tableRegex.findAll(html).mapNotNull { match ->
            val source = match.value
            val rows = extractRows(source)
            if (rows.isEmpty()) null else HTMLTableSlice(source, rows)
        }.toList()
    }

    private fun extractRows(html: String): List<List<SchoolPortalTableCell>> {
        val rowRegex = Regex("""<tr\b[^>]*>.*?</tr>""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        val cellRegex = Regex("""<(?:td|th)\b([^>]*)>(.*?)</(?:td|th)>""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        val rows = mutableListOf<List<SchoolPortalTableCell>>()
        for (rowMatch in rowRegex.findAll(html)) {
            val rowHTML = rowMatch.value
            val cells = mutableListOf<SchoolPortalTableCell>()
            for (cellMatch in cellRegex.findAll(rowHTML)) {
                val attrs = cellMatch.groupValues.getOrNull(1) ?: ""
                val text = decodeEntities(stripTags(cellMatch.groupValues.getOrNull(2) ?: ""))
                cells.add(
                    SchoolPortalTableCell(
                        text = text,
                        rowSpan = attribute(attrs, "rowspan") ?: 1,
                        colSpan = attribute(attrs, "colspan") ?: 1
                    )
                )
            }
            if (cells.isNotEmpty()) rows.add(cells)
        }
        return rows
    }

    private fun stripTags(text: String): String {
        var value = text
        val drop = listOf(
            """<(?:script|style|textarea|select|form)\b[^>]*>.*?</(?:script|style|textarea|select|form)>""",
            """<[^>]+\b(?:hidden|aria-hidden=["']true["'])[^>]*>.*?</[^>]+>"""
        )
        for (pattern in drop) {
            value = Regex(pattern, setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)).replace(value, "")
        }
        value = Regex("""<br\s*/?>""", RegexOption.IGNORE_CASE).replace(value, "\n")
        return Regex("""<[^>]+>""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)).replace(value, " ")
    }

    private fun decodeEntities(text: String): String {
        return text.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    }

    private fun attribute(attrs: String, name: String): Int? {
        val match = Regex("""\b$name\s*=\s*["']?(\d+)""", RegexOption.IGNORE_CASE).find(attrs) ?: return null
        return match.groupValues.getOrNull(1)?.toIntOrNull()
    }
}
