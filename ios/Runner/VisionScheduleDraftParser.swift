import Foundation

/// Conservative grid adapter. It only assigns columns/rows when explicit
/// weekday headers and complete clock ranges are present on this same image.
/// No inferred seven-column order or institution-specific period clock table.
public enum VisionScheduleDraftParser {
    public static func parse(pages: [VisionTimetablePage]) -> [String: Any] {
        var courses: [[String: Any]] = []
        var signatures: [String: Int] = [:]
        for page in pages {
            let tokens = page.tokens.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let headers = tokens.filter { weekday($0.text) != nil && isHeader($0.text) }.sorted { centerX($0) < centerX($1) }
            let clocks = tokens.filter { clock($0.text) != nil && isClockOnly($0.text) }.sorted { centerY($0) < centerY($1) }
            // More than one header for the same weekday means multiple grids;
            // this adapter intentionally keeps those candidates pending.
            let reliableHeaders = Set(headers.compactMap { weekday($0.text) }).count == headers.count && !headers.isEmpty
            let grid = reliableHeaders && !clocks.isEmpty
            var groups: [String: [VisionTimetableToken]] = [:]
            var groupOrder: [String] = []
            for (index, token) in tokens.enumerated() {
                guard !isHeader(token.text), !isClockOnly(token.text), !isNavigation(token.text) else { continue }
                let key: String
                if grid, let header = nearestColumn(token, headers: headers), let row = nearestRow(token, clocks: clocks),
                   token.boundingBox.y > headers.map({ $0.boundingBox.y + $0.boundingBox.height }).max()! {
                    key = "grid:\(header):\(row)"
                } else {
                    // Preserve a multi-line observation as one candidate. With
                    // missing anchors, separate observations are never assigned
                    // to an invented cell or joined merely by proximity.
                    key = "unanchored:\(index)"
                }
                if groups[key] == nil { groups[key] = []; groupOrder.append(key) }
                groups[key, default: []].append(token)
            }
            var preparedOrder: [String] = []
            var ambiguousTitles: [String: String] = [:]
            for key in groupOrder {
                let names = Array(Set(groups[key]!.flatMap { $0.text.components(separatedBy: .newlines) }.compactMap { title([$0.trimmingCharacters(in: .whitespacesAndNewlines)]) })).sorted()
                if names.count > 1 {
                    for (index, name) in names.enumerated() {
                        let candidateKey = key + ":candidate:\(index)"
                        groups[candidateKey] = groups[key]
                        ambiguousTitles[candidateKey] = name
                        preparedOrder.append(candidateKey)
                    }
                } else { preparedOrder.append(key) }
            }
            for key in preparedOrder {
                let group = groups[key]!.sorted { centerY($0) < centerY($1) }
                let rawText = group.map(\.text).joined(separator: "\n")
                let lines = rawText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                guard let title = ambiguousTitles[key] ?? title(lines) else { continue }
                let explicitClock = clock(rawText)
                var weeks = parseWeeks(rawText)
                var day = weekday(rawText)
                var times = explicitClock
                var usedAnchors: [VisionTimetableToken] = []
                if key.hasPrefix("grid:") {
                    let indexes = key.split(separator: ":").dropFirst().compactMap { Int($0) }
                    day = day ?? weekday(headers[indexes[0]].text)
                    times = times ?? clock(clocks[indexes[1]].text)
                    usedAnchors = [headers[indexes[0]], clocks[indexes[1]]]
                }
                // Low confidence anchors cannot generate a certain occurrence.
                if usedAnchors.contains(where: { $0.confidence < 0.5 }) { day = nil; times = nil }
                let location = capture("(?:教室|地点|上课地点)\\s*[:：]\\s*([^\\n]+)", rawText)
                let teacher = capture("(?:教师|老师|任课教师)\\s*[:：]\\s*([^\\n]+)", rawText)
                let code = capture("(?:课程编码|课程代码|课程号)\\s*[:：]\\s*([A-Za-z0-9_-]+)", rawText)
                let section = capture("(?:教学班|班号)\\s*[:：]\\s*([^\\n]+)", rawText)
                var reasons: [String] = []
                if ambiguousTitles[key] != nil {
                    day = nil; times = nil; weeks = nil
                    reasons.append("同一格包含多个课程候选，需核对各自安排")
                }
                if day == nil { reasons.append("未识别到明确星期表头") }
                if times == nil { reasons.append("未识别到完整钟点范围") }
                if weeks == nil { reasons.append("周次待核对") }
                let evidence = (group + usedAnchors).map { token in
                    ["imageIndex": token.imageIndex, "text": token.text, "confidence": token.confidence,
                     "boundingBox": ["x": token.boundingBox.x, "y": token.boundingBox.y, "width": token.boundingBox.width, "height": token.boundingBox.height]] as [String: Any]
                }
                let meeting: [String: Any] = ["weekday": day as Any? ?? NSNull(), "weeks": weeks as Any? ?? NSNull(),
                    "startMinute": times?.0 as Any? ?? NSNull(), "endMinute": times?.1 as Any? ?? NSNull(),
                    "location": location as Any? ?? NSNull(), "sourceReference": "image:\(page.imageIndex):\(key)", "raw": ["tokens": evidence]]
                var course: [String: Any] = ["name": title, "courseCode": code as Any? ?? NSNull(), "section": section as Any? ?? NSNull(),
                    "teacher": teacher as Any? ?? NSNull(), "meetings": [meeting],
                    "pendingReason": reasons.isEmpty ? NSNull() : reasons.joined(separator: "；") as Any,
                    "raw": ["sourceLine": rawText, "sources": evidence, "parser": "conservative-vision-grid"]]
                // No fuzzy or same-name merge: only exactly matching content
                // and arrangements are deduplicated; provenance is combined.
                let signatureObject: [Any] = [title, code as Any? ?? NSNull(), section as Any? ?? NSNull(), teacher as Any? ?? NSNull(),
                    day as Any? ?? NSNull(), weeks as Any? ?? NSNull(), times?.0 as Any? ?? NSNull(), times?.1 as Any? ?? NSNull(), location as Any? ?? NSNull()]
                let signature = String(data: try! JSONSerialization.data(withJSONObject: signatureObject, options: [.sortedKeys]), encoding: .utf8)!
                if let priorIndex = signatures[signature] {
                    var prior = courses[priorIndex]
                    var raw = prior["raw"] as! [String: Any]
                    raw["sources"] = (raw["sources"] as! [[String: Any]]) + evidence
                    prior["raw"] = raw
                    courses[priorIndex] = prior
                } else {
                    signatures[signature] = courses.count
                    course["raw"] = ["sourceLine": rawText, "sources": evidence, "parser": "conservative-vision-grid"]
                    courses.append(course)
                }
            }
        }
        return ["courses": courses, "warnings": ["本机文字识别结果需逐项核对；未明确的星期、周次或钟点保持待定。"]]
    }

    private static func centerX(_ token: VisionTimetableToken) -> Double { token.boundingBox.x + token.boundingBox.width / 2 }
    private static func centerY(_ token: VisionTimetableToken) -> Double { token.boundingBox.y + token.boundingBox.height / 2 }
    private static func nearestColumn(_ token: VisionTimetableToken, headers: [VisionTimetableToken]) -> Int? {
        let x = centerX(token)
        // Horizontal content must align with an explicitly observed header.
        guard let index = headers.indices.min(by: { abs(centerX(headers[$0]) - x) < abs(centerX(headers[$1]) - x) }) else { return nil }
        let tolerance = headers.count > 1 ? zip(headers, headers.dropFirst()).map { abs(centerX($0.0) - centerX($0.1)) / 2 }.min()! : max(headers[0].boundingBox.width, 0.08)
        return abs(centerX(headers[index]) - x) <= tolerance ? index : nil
    }
    private static func nearestRow(_ token: VisionTimetableToken, clocks: [VisionTimetableToken]) -> Int? {
        let y = centerY(token)
        guard let index = clocks.indices.min(by: { abs(centerY(clocks[$0]) - y) < abs(centerY(clocks[$1]) - y) }) else { return nil }
        let tolerance = clocks.count > 1 ? zip(clocks, clocks.dropFirst()).map { abs(centerY($0.0) - centerY($0.1)) / 2 }.min()! : max(clocks[0].boundingBox.height * 3, 0.12)
        return abs(centerY(clocks[index]) - y) <= tolerance ? index : nil
    }
    private static func weekday(_ text: String) -> Int? {
        guard let value = capture("(?:周|星期|礼拜)([一二三四五六日天1-7])", text) else { return nil }
        return ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7][value] ?? Int(value)
    }
    private static func isHeader(_ text: String) -> Bool {
        text.range(of: "^\\s*(?:周|星期|礼拜)[一二三四五六日天1-7]\\s*$", options: .regularExpression) != nil
    }
    private static func clock(_ text: String) -> (Int, Int)? {
        guard let expression = try? NSRegularExpression(pattern: "(?<![0-9])([0-2]?[0-9])[:：]([0-5][0-9])\\s*[-–—~～至]\\s*([0-2]?[0-9])[:：]([0-5][0-9])(?![0-9])"),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let values = (1...4).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
        guard values.count == 4, values[0] <= 23, values[2] <= 23 else { return nil }
        let start = values[0] * 60 + values[1], end = values[2] * 60 + values[3]
        return end > start ? (start, end) : nil
    }
    private static func isClockOnly(_ text: String) -> Bool {
        clock(text) != nil && text.range(of: "^[\\s0-9:：–—~～至-]+$", options: .regularExpression) != nil
    }
    private static func parseWeeks(_ text: String) -> [Int]? {
        guard let raw = capture("(?:第)?([0-9]+(?:\\s*[-–—~～,，、]\\s*[0-9]+)*)\\s*周(?![一二三四五六日天])", text) else { return nil }
        let normal = raw.replacingOccurrences(of: "[–—~～]", with: "-", options: .regularExpression).replacingOccurrences(of: "[，、]", with: ",", options: .regularExpression)
        var result = Set<Int>()
        for piece in normal.split(separator: ",") {
            let edges = piece.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !edges.isEmpty, edges.count <= 2, edges.allSatisfy({ (1...60).contains($0) }) else { return nil }
            if edges.count == 2 {
                guard edges[1] >= edges[0] else { return nil }
                result.formUnion(edges[0]...edges[1])
            } else { result.insert(edges[0]) }
        }
        if text.contains("单周") { result = Set(result.filter { $0 % 2 == 1 }) }
        if text.contains("双周") { result = Set(result.filter { $0 % 2 == 0 }) }
        return result.isEmpty ? nil : result.sorted()
    }
    private static func title(_ lines: [String]) -> String? {
        if let explicit = lines.compactMap({ capture("^(?:课程名称|课程名)\\s*[:：]\\s*(.+)$", $0) }).first { return explicit }
        return lines.first { line in
            !isNavigation(line) && !isHeader(line) && !isClockOnly(line) &&
            line.range(of: "^(?:教师|老师|任课教师|地点|教室|上课地点|课程编码|课程代码|课程号|教学班|班号|周次)\\s*[:：]|^(?:第)?[0-9,，、 —–~-]+周|^[0-9]+$", options: .regularExpression) == nil &&
            line.range(of: "[\\p{L}]", options: .regularExpression) != nil
        }
    }
    private static func isNavigation(_ text: String) -> Bool {
        ["课表", "我的课表", "学期课表", "课程名称", "教师", "教室", "周次", "时间", "上午", "下午", "晚上", "上午课", "下午课", "晚上课", "返回", "首页", "上一周", "下一周"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private static func capture(_ pattern: String, _ text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
