import Foundation

/// Conservative parser for portal table payloads. It only emits a confirmed
/// meeting when weekday, weeks and a valid time range can be recovered.
struct SchoolScheduleParser {
    private static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    private static let weekdayShortNames = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]

    static func parse(message: SchoolPortalFrameMessage) -> SchoolScheduleParseResult {
        parse(tables: [message], source: "school-portal", frameCount: 1, sourceURL: message.frame.url)
    }

    static func parse(tables: [SchoolPortalFrameMessage], source: String = "school-portal", frameCount: Int? = nil, sourceURL: String? = nil) -> SchoolScheduleParseResult {
        let usable = tables.filter { $0.isExtractionMessage }
        var all: [SchoolScheduleDraft] = []
        var warnings: [String] = []
        for table in usable {
            let parsed = parseTable(table, source: source, sourceURL: safeURL(sourceURL ?? table.frame.url))
            all.append(contentsOf: parsed.drafts)
            warnings.append(contentsOf: parsed.warnings)
        }
        let deduped = deduplicate(all)
        if deduped.isEmpty && !usable.isEmpty { warnings.append("未找到可确认的课程安排；缺少字段的行会保留为待定项。") }
        let material = timetableMaterial(usable)
        warnings.append(contentsOf: material.warnings)
        return SchoolScheduleParseResult(
            source: source,
            sourceURL: safeURL(sourceURL ?? usable.first?.frame.url),
            frameCount: frameCount ?? Set(usable.map { $0.frame.url }).count,
            tableCount: usable.count,
            drafts: deduped,
            warnings: Array(NSOrderedSet(array: warnings)) as? [String] ?? warnings,
            timetableText: material.text
        )
    }

    /// Adapts yiqishangke's LoginWebViewSession.captureVisibleSchedule text
    /// fallback: retain source tables BEFORE parsing, including unparsed rows.
    /// Unlike its HTML/innerText fallback, only the checked cell schema crosses
    /// the bridge. URLs, frame metadata and page text never enter the AI input.
    private static func timetableMaterial(_ tables: [SchoolPortalFrameMessage]) -> (text: String?, warnings: [String]) {
        var sourceTables: [[[SchoolPortalTableCell]]] = []
        for table in tables {
            guard let header = table.rows.firstIndex(where: { row in
                let text = row.map(\.text).joined(separator: " ")
                let list = text.range(of: "课程名称|课程名|科目|教学科目", options: .regularExpression) != nil
                    && text.range(of: "上课|时间|地点|安排|周次", options: .regularExpression) != nil
                let grid = text.range(of: "周一|星期一", options: .regularExpression) != nil
                    && text.range(of: "周二|星期二", options: .regularExpression) != nil
                return list || grid
            }), table.rows.count > header + 1 else { continue }
            // Do not quietly give AI only the beginning of a large timetable.
            guard table.truncated != true else {
                return (nil, ["网页课表未完整读取，请分页面读取或使用完整课表截图；本次无法发送原文给 AI。"])
            }
            let rows = Array(table.rows.dropFirst(header))
            if !sourceTables.contains(rows) { sourceTables.append(rows) }
        }
        guard !sourceTables.isEmpty else { return (nil, []) }
        let texts = sourceTables.flatMap { $0 }.flatMap { $0 }.map(\.text).joined(separator: "\n")
        guard texts.range(of: "<[^>]+>|https?://|(?:password|passwd|cookie|authorization|samlresponse|学号|密码|验证码|身份证|手机号)", options: [.regularExpression, .caseInsensitive]) == nil else {
            return (nil, ["课表中混有登录信息或链接，本次不提供 AI 原文识别；请打开独立课表页后重试。"])
        }
        guard let data = try? JSONEncoder().encode(sourceTables), data.count <= 64_000,
              let text = String(data: data, encoding: .utf8) else {
            return (nil, ["课表原文过长，本次不发送给 AI；请分页面读取或分批导入截图。"])
        }
        return (text, [])
    }

    static func parseHTML(_ html: String, sourceURL: URL? = nil, source: String = "school-portal-html") -> SchoolScheduleParseResult {
        let slices = HTMLTableExtractor.extract(html: html)
        let messages = slices.enumerated().map { index, slice in
            SchoolPortalFrameMessage(
                version: SchoolPortalFrameMessage.currentVersion,
                kind: "scheduleTables",
                requestID: "html-\(index)",
                frame: SchoolPortalFrameIdentity(url: sourceURL?.absoluteString ?? "", securityOrigin: sourceURL?.host ?? "", isMainFrame: true),
                title: "",
                innerText: slice.rows.flatMap { $0 }.map(\.text).joined(separator: "\n"),
                html: slice.html,
                rows: slice.rows
            )
        }
        return parse(tables: messages, source: source, frameCount: 1, sourceURL: sourceURL?.absoluteString)
    }

    static func parseExtractionJSON(_ data: Data, source: String = "school-portal-json") -> SchoolScheduleParseResult? {
        let decoder = JSONDecoder()
        if let message = try? decoder.decode(SchoolPortalFrameMessage.self, from: data) {
            return parse(message: message)
        }
        struct Envelope: Decodable {
            let tables: [SchoolPortalFrameMessage]
            let frameCount: Int?
            let url: String?
        }
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            return parse(tables: envelope.tables, source: source, frameCount: envelope.frameCount, sourceURL: envelope.url)
        }
        return nil
    }

    private static func parseTable(_ table: SchoolPortalFrameMessage, source: String, sourceURL: String?) -> (drafts: [SchoolScheduleDraft], warnings: [String]) {
        let rows = expand(table.rows).map { $0.map { normalize($0) } }
        guard !rows.isEmpty else { return ([], ["表格没有数据行。"] ) }
        let header = rows.firstIndex(where: isLikelyHeader)
        if let header {
            let indices = columnIndices(rows[header])
            let body = rows.dropFirst(header + 1)
            let drafts = body.flatMap { parseListRow($0, indices: indices, source: source, sourceURL: sourceURL) }
            if !drafts.isEmpty { return (drafts, []) }
        }
        return parseWeeklyGrid(rows, originalCells: table.rows, source: source, sourceURL: sourceURL)
    }

    private static func isLikelyHeader(_ row: [String]) -> Bool {
        let blob = row.joined(separator: "|")
        return (blob.contains("课程名称") || blob.contains("课程")) && (blob.contains("上课") || blob.contains("时间") || blob.contains("地点"))
    }

    private struct ColumnIndices {
        var code: Int?
        var classCode: Int?
        var title: Int?
        var teacher: Int?
        var meeting: Int?
        var location: Int?
        var weeks: Int?
        var weekday: Int?
    }

    private static func columnIndices(_ header: [String]) -> ColumnIndices {
        func find(_ values: [String]) -> Int? {
            if let exact = header.firstIndex(where: { cell in values.contains(where: { cell == $0 }) }) { return exact }
            return header.firstIndex { cell in
                values.filter { $0.count > 1 }.contains(where: { cell.contains($0) })
            }
        }
        return ColumnIndices(
            code: find(["课程编号", "课程编码", "课程号"]),
            classCode: find(["教学班", "班号"]),
            title: find(["课程名称", "课程名", "课程"]),
            teacher: find(["任课教师", "教师", "老师"]),
            meeting: find(["上课时间", "上课周次", "时间", "安排"]),
            location: find(["上课地点", "地点", "教室"]),
            weeks: find(["周次"]),
            weekday: find(["星期"])
        )
    }

    private static func parseListRow(_ row: [String], indices: ColumnIndices, source: String, sourceURL: String?) -> [SchoolScheduleDraft] {
        func value(_ index: Int?) -> String { guard let index, index < row.count else { return "" }; return row[index] }
        let title = value(indices.title)
        guard title.count >= 2, !title.contains("课程名称") else { return [] }
        var weeks = value(indices.weeks)
        if !weeks.isEmpty && !weeks.contains("周") { weeks += "周" }
        let raw = value(indices.meeting)
        let pieces = splitMeetings(raw)
        return pieces.map { part in
            let text = part + " " + weeks + " " + value(indices.weekday)
            let time = parseTimeRange(text)
            let periods = parsePeriods(text)
            let knownWeeks = parseWeeks(text)
            let day = dayNumber(in: text)
            return SchoolScheduleDraft(source: source,
                courseCode: value(indices.code).isEmpty ? nil : value(indices.code),
                classCode: value(indices.classCode).isEmpty ? nil : value(indices.classCode),
                title: title, teacher: value(indices.teacher), location: value(indices.location),
                weekday: day, weeks: knownWeeks, startMinutes: time?.0, endMinutes: time?.1,
                term: nil, pendingReason: time == nil || knownWeeks == nil || day == nil ? "缺少可确认的星期、周次或钟点；节次需按作息核对" : nil,
                notes: part, sourceURL: sourceURL, rawText: row.joined(separator: " | ") + " | " + part,
                startPeriod: periods?.0, endPeriod: periods?.1)
        }
    }

    /// Separate explicit arrangement groups without inventing a Cartesian product
    /// of different rooms, clocks or weeks. Unknown pieces survive for review.
    private static func splitMeetings(_ text: String) -> [String] {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ";；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? [text] : parts.flatMap { part -> [String] in
            let days = matches(#"(?:周|星期)[一二三四五六日天]"#, part)
            guard days.count > 1 else {
                let clocks = matches(#"\d{1,2}[:：]\d{2}\s*[-~至到]\s*\d{1,2}[:：]\d{2}"#, part)
                guard clocks.count > 1 else { return [part] }
                let prefix = (part as NSString).substring(to: clocks[0].range.location)
                return clocks.indices.map { i in
                    let end = i + 1 < clocks.count ? clocks[i + 1].range.location : (part as NSString).length
                    return prefix + (part as NSString).substring(with: NSRange(location: clocks[i].range.location, length: end - clocks[i].range.location))
                }
            }
            // Without separators, each weekday starts an arrangement. Prefix data
            // belongs only to the first; missing fields stay explicitly unknown.
            var result: [String] = []
            for index in days.indices {
                let start = index == 0 ? 0 : days[index].range.location
                let end = index + 1 < days.count ? days[index + 1].range.location : (part as NSString).length
                result.append((part as NSString).substring(with: NSRange(location: start, length: end - start)))
            }
            return result
        }
    }

    private static func parseWeeks(_ text: String) -> [Int]? {
        // A trailing 周 marker is mandatory. Clock ranges and 第1-2节 never match.
        let groups = matches(#"(?<![\d:：])(?:第\s*)?(\d{1,2}(?:\s*[-~至到]\s*\d{1,2})?(?:\s*[,，、]\s*\d{1,2}(?:\s*[-~至到]\s*\d{1,2})?)*)\s*周"#, text)
        guard !groups.isEmpty else { return nil }
        var values = Set<Int>()
        for group in groups {
            let sequence = (text as NSString).substring(with: group.range(at: 1))
            for part in sequence.components(separatedBy: CharacterSet(charactersIn: ",，、")) {
                let numbers = matches(#"\d+"#, part).compactMap { Int((part as NSString).substring(with: $0.range)) }
                guard let first = numbers.first, (1...60).contains(first) else { return nil }
                let last = numbers.last ?? first
                guard (first...60).contains(last) else { return nil }
                values.formUnion(first...last)
            }
        }
        if text.contains("单周") || text.contains("(单)") || text.contains("（单）") { values = Set(values.filter { $0 % 2 == 1 }) }
        if text.contains("双周") || text.contains("(双)") || text.contains("（双）") { values = Set(values.filter { $0 % 2 == 0 }) }
        return values.isEmpty ? nil : values.sorted()
    }

    private static func parseTimeRange(_ text: String) -> (Int, Int)? {
        let found = matches(#"(?<!\d)(\d{1,2})\s*[:：]\s*(\d{2})\s*[-~至到]\s*(\d{1,2})\s*[:：]\s*(\d{2})(?!\d)"#, text)
        guard found.count == 1, let match = found.first,
              let h1 = intCapture(match, at: 1, in: text), let m1 = intCapture(match, at: 2, in: text), let h2 = intCapture(match, at: 3, in: text), let m2 = intCapture(match, at: 4, in: text),
              (0...23).contains(h1), (0...23).contains(h2), (0...59).contains(m1), (0...59).contains(m2) else { return nil }
        let start = h1 * 60 + m1, end = h2 * 60 + m2
        return end > start ? (start, end) : nil
    }

    private static func parsePeriods(_ text: String) -> (Int, Int)? {
        guard let match = matches(#"第\s*(\d{1,2})(?:\s*[-~至到]\s*(\d{1,2}))?\s*节"#, text).first,
              let first = intCapture(match, at: 1, in: text) else { return nil }
        let last = intCapture(match, at: 2, in: text) ?? first
        guard (1...30).contains(first), (first...30).contains(last) else { return nil }
        return (first, last)
    }

    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern).matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))) ?? []
    }

    static func expand(_ rows: [[SchoolPortalTableCell]]) -> [[String]] {
        var grid = Array(repeating: Array<String?>(repeating: nil, count: 32), count: min(rows.count + 128, 256))
        var width = 0
        for (r, row) in rows.prefix(128).enumerated() {
            var c = 0
            for cell in row.prefix(32) {
                while c < 32 && grid[r][c] != nil { c += 1 }
                guard c < 32 else { break }
                let spanWidth = min(max(cell.colSpan, 1), 32 - c)
                let spanHeight = min(max(cell.rowSpan, 1), grid.count - r)
                for rr in r..<(r + spanHeight) {
                    for cc in c..<(c + spanWidth) where grid[rr][cc] == nil { grid[rr][cc] = cell.text }
                }
                c += spanWidth
                width = max(width, c)
            }
        }
        return grid.prefix(min(rows.count,128)).map { Array($0.prefix(width)).map { $0 ?? "" } }
    }

    private static func safeURL(_ value: String?) -> String? {
        SchoolPortalSecurity.sanitizedURL(value.flatMap(URL.init(string:)))
    }

    private static func parseWeeklyGrid(_ rows: [[String]], originalCells: [[SchoolPortalTableCell]], source: String, sourceURL: String?) -> (drafts: [SchoolScheduleDraft], warnings: [String]) {
        guard let headerIndex = rows.firstIndex(where: { row in
            row.filter { cell in weekdayNames.contains(where: { cell.contains($0) }) || weekdayShortNames.contains(where: { cell.contains($0) }) }.count >= 2
        }) else {
            return ([], ["未识别列表表头或周课表表头。"])
        }
        let mergedRows = Set(originalCells.flatMap { $0 }.filter { $0.rowSpan > 1 }.map { normalize($0.text) })
        let mergedColumns = Set(originalCells.flatMap { $0 }.filter { $0.colSpan > 1 }.map { normalize($0.text) })
        let header = rows[headerIndex]
        var dayColumns: [Int: Int] = [:]
        for (index, cell) in header.enumerated() {
            if let day = dayNumber(in: cell) { dayColumns[index] = day }
        }
        guard dayColumns.count >= 2 else { return ([], ["周课表缺少星期列。"]) }
        var drafts: [SchoolScheduleDraft] = []
        for row in rows.dropFirst(headerIndex + 1) {
            guard let periodText = row.first, !periodText.isEmpty else { continue }
            for column in dayColumns.keys.sorted() {
                let day = dayColumns[column]!
                guard column < row.count else { continue }
                let cell = row[column]
                guard !cell.isEmpty, !isHeaderLike(cell) else { continue }
                let lines = cell.components(separatedBy: .newlines).filter { !$0.isEmpty }
                let firstLine = lines.first ?? cell
                let metadata = matches(#"(?:第)?\d{1,2}(?:[-~至到,，、]\d{1,2})*周|\d{1,2}[:：]\d{2}|课程编号[：:]|教师[：:]|地点[：:]"#, firstLine).first
                let title = metadata.map { (firstLine as NSString).substring(to: $0.range.location).trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } ?? firstLine
                for part in splitMeetings(lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : cell) {
                    // A cell spanning timetable rows does not justify assigning a
                    // single row's clock to the entire course. Keep explicit cell
                    // clocks, otherwise let the user resolve the merged duration.
                    let text = (mergedRows.contains(cell) ? "" : periodText) + " " + part
                    let resolvedDay = mergedColumns.contains(cell) ? dayNumber(in: part) : day
                    let time = parseTimeRange(text)
                    let weeks = parseWeeks(text)
                    let periods = parsePeriods(text)
                    drafts.append(SchoolScheduleDraft(
                        source: source, courseCode: nil, classCode: nil, title: title,
                        teacher: "", location: "", weekday: resolvedDay, weeks: weeks,
                        startMinutes: time?.0, endMinutes: time?.1,
                        term: nil, pendingReason: time == nil || weeks == nil || resolvedDay == nil ? "周课表单元缺少明确周次、星期或钟点" : nil,
                        notes: periodText, sourceURL: sourceURL, rawText: cell,
                        startPeriod: periods?.0, endPeriod: periods?.1))
                }
            }
        }
        return (drafts, [])
    }

    private static func deduplicate(_ drafts: [SchoolScheduleDraft]) -> [SchoolScheduleDraft] {
        var result: [SchoolScheduleDraft] = []
        var indexes: [String: Int] = [:]
        for draft in drafts where !draft.title.isEmpty {
            let key = draft.identityKey
            if let index = indexes[key] {
                var merged = result[index]
                if merged.teacher.isEmpty { merged.teacher = draft.teacher }
                if merged.location.isEmpty { merged.location = draft.location }
                if merged.notes.isEmpty { merged.notes = draft.notes }
                result[index] = merged
            } else {
                indexes[key] = result.count
                result.append(draft)
            }
        }
        return result
    }

    private static func dayNumber(in text: String) -> Int? {
        if text.contains("周天") || text.contains("星期天") { return 7 }
        for day in 1...7 where text.contains(weekdayNames[day - 1]) || text.contains(weekdayShortNames[day - 1]) { return day }
        return nil
    }

    private static func isHeaderLike(_ text: String) -> Bool {
        text == "课程名称" || weekdayNames.contains(text) || weekdayShortNames.contains(text)
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: .newlines).map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func intCapture(_ match: NSTextCheckingResult, at index: Int, in text: String) -> Int? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return Int(text[swiftRange])
    }
}

private struct HTMLTableSlice {
    let html: String
    let rows: [[SchoolPortalTableCell]]
}

private enum HTMLTableExtractor {
    static func extract(html: String) -> [HTMLTableSlice] {
        guard let tableRegex = try? NSRegularExpression(pattern: #"(?is)<table\b[^>]*>.*?</table>"#) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return tableRegex.matches(in: html, range: range).compactMap { match in
            guard let r = Range(match.range, in: html) else { return nil }
            let source = String(html[r])
            let rows = extractRows(source)
            return rows.isEmpty ? nil : HTMLTableSlice(html: source, rows: rows)
        }
    }

    private static func extractRows(_ html: String) -> [[SchoolPortalTableCell]] {
        guard let rowRegex = try? NSRegularExpression(pattern: #"(?is)<tr\b[^>]*>.*?</tr>"#), let cellRegex = try? NSRegularExpression(pattern: #"(?is)<(?:td|th)\b([^>]*)>(.*?)</(?:td|th)>"#) else { return [] }
        var rows: [[SchoolPortalTableCell]] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for rowMatch in rowRegex.matches(in: html, range: range) {
            guard let rowRange = Range(rowMatch.range, in: html) else { continue }
            let rowHTML = String(html[rowRange])
            let rowNSRange = NSRange(rowHTML.startIndex..<rowHTML.endIndex, in: rowHTML)
            var cells: [SchoolPortalTableCell] = []
            for cellMatch in cellRegex.matches(in: rowHTML, range: rowNSRange) {
                guard let attrRange = Range(cellMatch.range(at: 1), in: rowHTML), let textRange = Range(cellMatch.range(at: 2), in: rowHTML) else { continue }
                let attrs = String(rowHTML[attrRange])
                let text = decodeEntities(stripTags(String(rowHTML[textRange])))
                cells.append(SchoolPortalTableCell(text: text, rowSpan: attribute(attrs, name: "rowspan") ?? 1, colSpan: attribute(attrs, name: "colspan") ?? 1))
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        return rows
    }

    private static func stripTags(_ text: String) -> String {
        var value = text
        for pattern in [#"(?is)<(?:script|style|textarea|select|form)\b[^>]*>.*?</(?:script|style|textarea|select|form)>"#, #"(?is)<[^>]+\b(?:hidden|aria-hidden=[\"']true[\"'])[^>]*>.*?</[^>]+>"#] {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        value = value.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        return value.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func attribute(_ attrs: String, name: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\b\(name)\\s*=\\s*[\\\"']?(\\d+)") else { return nil }
        guard let match = regex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..<attrs.endIndex, in: attrs)), let range = Range(match.range(at: 1), in: attrs) else { return nil }
        return Int(attrs[range])
    }
}
