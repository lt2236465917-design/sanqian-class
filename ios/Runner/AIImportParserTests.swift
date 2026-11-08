// Offline executable; excluded from the production build by default.
// xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios13.0-simulator -D AI_IMPORT_TESTS AIImportModels.swift DeepSeekTimetableClient.swift TimetableGridEvidence.swift VisionScheduleDraftParser.swift VisionTimetableRecognizer.swift AIImportParserTests.swift -o /tmp/ai-import-tests
#if AI_IMPORT_TESTS
import Foundation
import UIKit
import CoreGraphics
import ImageIO

private final class OfflineDeepSeekProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data)?)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            if let (status, bytes) = try Self.handler?(request) {
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: bytes)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct AIImportOfflineTests {
    static let valid = #"{"courses":[{"name":"英语","courseCode":"ENG","section":"1","teacher":null,"meetings":[{"weekday":1,"weeks":[3,4,6],"startMinute":540,"endMinute":600,"location":null}],"pendingReason":null}]}"#
    static var assertions = 0
    static func check(_ value: Bool, _ label: String) { precondition(value, label); assertions += 1 }
    static func envelope(_ content: String, reason: String? = "stop") throws -> Data {
        var choice: [String: Any] = ["message": ["content": content]]
        if let reason = reason { choice["finish_reason"] = reason }
        return try JSONSerialization.data(withJSONObject: ["choices": [choice]])
    }
    static func expect(_ error: DeepSeekTimetableClientError, _ label: String, _ operation: () throws -> Void) {
        do { try operation(); preconditionFailure(label) }
        catch let actual as DeepSeekTimetableClientError { check(actual == error, label) }
        catch { preconditionFailure("Unexpected error: \(label)") }
    }
    static func expectAsync(_ error: DeepSeekTimetableClientError, _ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); preconditionFailure(label) }
        catch let actual as DeepSeekTimetableClientError { check(actual == error, label) }
        catch { preconditionFailure("Unexpected error: \(label)") }
    }
    static func png(width: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
    static func gridEvidenceTests() throws {
        let cell: [String: Any] = ["id": "p0r1c1", "imageIndex": 0, "weekday": 1, "startMinute": 1140, "endMinute": 1290, "rowLabel": "晚上课 19:00--21:30", "texts": ["课程甲"]]
        let text = #"{"courses":[{"name":"课程甲","meetings":[{"weekday":1,"weeks":[4],"startMinute":1140,"endMinute":1170,"cellRefs":["p0r1c1"]}]}]}"#
        func parsed(_ value: String, cells: [[String: Any]] = [cell]) throws -> [String: Any] {
            let result = try DeepSeekTimetableClient.parseResponse(envelope(value), gridCells: cells)
            let obj = try JSONSerialization.jsonObject(with: Data(result.jsonText.utf8)) as! [String: Any]
            return (obj["courses"] as! [[String: Any]])[0]
        }
        func first(_ course: [String: Any]) -> [String: Any] { (course["meetings"] as! [[String: Any]])[0] }
        func warnings(_ course: [String: Any]) -> [String] {
            let raw = course["raw"] as! [String: Any]
            return (raw["recognitionWarnings"] as? [String] ?? []) + (raw["batchRecognitionWarnings"] as? [String] ?? [])
        }
        let singleRef = text.replacingOccurrences(of: #""cellRefs":["p0r1c1"]"#, with: #""cellRef":"p0r1c1""#)
        check(first(try parsed(singleRef))["endMinute"] as? Int == 1290, "single-cell output contract uses the same validated anchor")
        expect(.invalidCourseField("courses[0].meetings[0].cellRef"), "single cell ref cannot be an array") {
            _ = try parsed(text.replacingOccurrences(of: "cellRefs", with: "cellRef"))
        }
        let corrected = try parsed(text)
        check(first(corrected)["endMinute"] as? Int == 1290, "local summary corrects shortened evening")
        check((first(corrected)["raw"] as? [String: Any])?["modelEndMinute"] as? Int == 1170, "clock repair retains original")
        check(warnings(corrected).isEmpty, "valid reference is covered")
        check(first(try parsed(text, cells: []))["endMinute"] as? Int == 1170, "no request context cannot fabricate correction")
        let wrongDay = try parsed(text.replacingOccurrences(of: #""weekday":1"#, with: #""weekday":3"#))
        check(first(wrongDay)["weekday"] is NSNull, "local column conflict stays pending")
        check(!warnings(wrongDay).isEmpty, "column conflict is visible")
        let wrongRef = try parsed(text.replacingOccurrences(of: "p0r1c1", with: "invented"))
        check(first(wrongRef)["endMinute"] as? Int == 1170, "invented ref cannot change minutes")
        check(warnings(wrongRef).contains(where: { $0.contains("无效") }), "invalid reference reported")
        let explicit = try parsed(text.replacingOccurrences(of: #""cellRefs""#, with: #""sourceLine":"19:00-19:30","cellRefs""#))
        check(first(explicit)["startMinute"] is NSNull && first(explicit)["endMinute"] is NSNull, "explicit contradictory clock not overwritten")
        var other = cell; other["id"] = "p0r1c2"; other["weekday"] = 2
        let omitted = try parsed(text, cells: [cell, other])
        check(warnings(omitted).contains(where: { $0.contains("非空格子") }), "uncovered cell produces review warning")
        let crossed = try parsed(text.replacingOccurrences(of: #"["p0r1c1"]"#, with: #"["p0r1c1","p0r1c2"]"#), cells: [cell, other])
        check(first(crossed)["weekday"] is NSNull && first(crossed)["startMinute"] is NSNull, "different slots cannot be combined")
        let agreeingSource = try parsed(text.replacingOccurrences(of: #""cellRefs""#, with: #""sourceLine":"19:00–21:30","cellRefs""#))
        check(first(agreeingSource)["endMinute"] as? Int == 1290, "agreeing explicit full clock supports correction")
        var partialBlock = cell; partialBlock["texts"] = ["课程甲", "19:00-19:30"]
        check(first(try parsed(text, cells: [partialBlock]))["endMinute"] is NSNull, "course block clock prevents broad summary expansion")
        var differentWeeks = cell; differentWeeks["id"] = "p1r1c1"; differentWeeks["texts"] = ["课程甲", "第7周", "B教室"]
        check(warnings(try parsed(text, cells: [cell, differentWeeks])).contains(where: { $0.contains("非空格子") }), "same course slot does not cover different week and room")
        var copy = cell; copy["id"] = "p1r1c1"
        var response = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        var courses = response["courses"] as! [[String: Any]]
        var meetings = courses[0]["meetings"] as! [[String: Any]]
        var duplicate = meetings[0]; duplicate["cellRefs"] = ["p1r1c1"]; meetings.append(duplicate)
        courses[0]["meetings"] = meetings; response["courses"] = courses
        let duplicates = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        let combined = try parsed(duplicates, cells: [cell, copy])
        check((combined["meetings"] as! [[String: Any]]).count == 1, "dedupe preserves one complete schedule")
        check(((first(combined)["raw"] as! [String: Any])["cellRefs"] as! [String]).count == 2, "dedupe retains both cell references")
        expect(.truncatedResponse, "grid evidence never accepts truncated JSON") {
            _ = try DeepSeekTimetableClient.parseResponse(envelope(text, reason: "length"), gridCells: [cell])
        }
    }
    static func pendingListRowsTests() throws {
        func parse(_ lines: [String], meetings: [[String: Any]]) throws -> [String: Any] {
            let value: [String: Any] = ["courses": [["sourceKind": "list", "titleText": "课程甲", "name": "课程甲", "listRows": lines, "meetings": meetings]]]
            let text = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
            let result = try DeepSeekTimetableClient.parseResponse(envelope(text))
            let root = try JSONSerialization.jsonObject(with: Data(result.jsonText.utf8)) as! [String: Any]
            return (root["courses"] as! [[String: Any]])[0]
        }
        let first: [String: Any] = ["listRow": 1, "weekday": 2, "weeks": [3], "startMinute": 540, "endMinute": 720]
        let third: [String: Any] = ["listRow": 3, "weekday": 4, "weeks": [4], "startMinute": 810, "endMinute": 990]
        let mixed = try parse(["3周二上午", "请与任课教师联系", "4周四下午"], meetings: [first, third])
        let raw = mixed["raw"] as! [String: Any]
        let rows = mixed["meetings"] as! [[String: Any]]
        check(raw["listedMeetingCount"] as? Int == 2, "pending note excluded from scheduled list count")
        check((raw["recognitionWarnings"] as! [String]).isEmpty, "filtered note does not cause missing row warning")
        check((rows[1]["raw"] as! [String: Any])["listRow"] as? Int == 2, "original third row maps to second valid row")
        check(rows[1]["sourceReference"] as? String == "4周四下午", "row filtering never shifts schedule evidence")
        let pending = try parse(["2label.teachtask.courseclass.week.null-自排教室，请与任课教师联系上课时间和地点"], meetings: [])
        let pendingRaw = pending["raw"] as! [String: Any]
        check(pendingRaw["listedMeetingCount"] as? Int == 0, "placeholder is pending even with framework prefix digit")
        check((pendingRaw["recognitionWarnings"] as! [String]).isEmpty, "pending placeholder has no omission warning")
        check((pendingRaw["ignoredPendingListRows"] as! [[String: Any]]).count == 1, "ignored source remains auditable")
        let scheduled = try parse(["6-10周二上午，请与任课教师联系"], meetings: [["listRow": 1, "weekday": 2, "weeks": [6,7,8,9,10], "startMinute": 540, "endMinute": 720]])
        check((scheduled["raw"] as! [String: Any])["listedMeetingCount"] as? Int == 1, "contact note with real weeks retains meeting")
    }
    static func main() async throws {
        try gridEvidenceTests()
        try pendingListRowsTests()
        check(try DeepSeekTimetableClient.parseResponse(envelope(valid)).finishReason == "stop", "missing room remains scheduled")
        expect(.invalidJSON, "broken JSON") { _ = try DeepSeekTimetableClient.parseResponse(envelope("{broken")) }
        expect(.emptyCourses, "empty courses") { _ = try DeepSeekTimetableClient.parseResponse(envelope(#"{"courses":[]}"#)) }
        expect(.invalidCourseField("courses"), "missing courses") { _ = try DeepSeekTimetableClient.parseResponse(envelope("{}")) }
        for (old, new, field) in [
            ("\"weekday\":1", "\"weekday\":true", "weekday"),
            ("\"weekday\":1", "\"weekday\":8", "weekday"),
            ("\"weeks\":[3,4,6]", "\"weeks\":[0]", "weeks"),
            ("\"weeks\":[3,4,6]", "\"weeks\":\"3周4周\"", "weeks"),
            ("\"weeks\":[3,4,6]", "\"weeks\":\"3-99999999999999999999999999999999\"", "weeks"),
            ("\"endMinute\":600", "\"endMinute\":500", "endMinute"),
            ("\"startMinute\":540", "\"startMinute\":540.5", "startMinute"),
            ("\"location\":null", "\"location\":123", "location")
        ] {
            expect(.invalidCourseField("courses[0].meetings[0]." + field), "reject malformed field") {
                _ = try DeepSeekTimetableClient.parseResponse(envelope(valid.replacingOccurrences(of: old, with: new)))
            }
        }
        func courses(_ content: String) throws -> [[String: Any]] {
            let result = try DeepSeekTimetableClient.parseResponse(envelope(content))
            return (try JSONSerialization.jsonObject(with: Data(result.jsonText.utf8)) as! [String: Any])["courses"] as! [[String: Any]]
        }
        check(try courses("```json\n" + valid + "\n```").count == 1, "fenced JSON accepted")
        let reference = #"{"scheduled":[{"title":"艺术史","weekday":"周一","weeks":"3,4,6-7","startTime":"13:30","endTime":"16:30","room":"6406","sourceLine":"3,4,6-7周一下午"},{"title":"艺术史","weekday":"周一","weeks":"8","startTime":"19:00","endTime":"21:30","room":"6407"}],"pending":[{"title":"导师课","reason":"联系老师"}]}"#
        let referenceCourses = try courses(reference)
        check(referenceCourses.count == 3, "scheduled and pending all retained")
        let meeting = (referenceCourses[0]["meetings"] as! [[String: Any]])[0]
        check(meeting["weeks"] as? [Int] == [3,4,6,7], "range expansion preserves missing week")
        let collapsed = try courses(#"{"courses":[{"name":"英语","meetings":[{"weekday":5,"weeks":[6,11],"startMinute":810,"endMinute":990,"location":"6406","sourceLine":"6-11周一-下午课-6406","gridWeekday":1,"gridWeeks":"6-11"}]}]}"#)
        let collapsedMeeting = (collapsed[0]["meetings"] as! [[String: Any]])[0]
        check(collapsedMeeting["weeks"] as? [Int] == [6,7,8,9,10,11], "source line expands a closed week range")
        check(collapsedMeeting["weekday"] as? Int == 1, "matching list and grid repair the numeric weekday")
        let sunday = try courses(#"{"courses":[{"name":"摄影","meetings":[{"weekday":5,"weeks":[5],"startMinute":540,"endMinute":720,"location":"虚拟教室1","sourceLine":"5周日-上午课-虚拟教室1","gridWeekday":7,"gridWeeks":"5"}]}]}"#)
        check(((sunday[0]["meetings"] as! [[String: Any]])[0]["weekday"] as? Int) == 7, "周日 is weekday 7")
        let conflicting = try courses(#"{"courses":[{"name":"证据冲突","sourceKind":"list","titleText":"证据冲突","listRows":["6-12周三","14周二"],"meetings":[{"listRow":1,"weekday":3,"weeks":[6,7,8,9,10,11,12],"startMinute":540,"endMinute":720,"sourceLine":"6-12周三","gridWeekday":4,"gridWeeks":"6-10"}]}]}"#)[0]
        let conflictingRow = (conflicting["meetings"] as! [[String: Any]])[0]
        check(conflictingRow["weekday"] is NSNull && conflictingRow["weeks"] is NSNull, "conflicting grid evidence cannot lock in a wrong day or widened range")
        check((conflicting["pendingReason"] as? String)?.contains("名单有2条安排，识别为1条") == true, "missing list row is flagged")
        check((conflictingRow["raw"] as? [String: Any])?["gridWeekday"] as? Int == 4, "conflicting evidence remains available")
        let unsupported = try courses(#"{"courses":[{"name":"无网格证据","meetings":[{"weekday":4,"weeks":[6,7,8,9,10],"sourceLine":"6-12周三"}]}]}"#)[0]
        let unsupportedRow = (unsupported["meetings"] as! [[String: Any]])[0]
        check(unsupportedRow["weekday"] is NSNull && unsupportedRow["weeks"] is NSNull, "source transcription alone cannot overwrite conflicting fields")
        let repeated = try courses(#"{"courses":[{"name":"重复节次","listedMeetingCount":1,"sourceLine":"12周二","meetings":[{"weekday":4,"weeks":[3,4],"startMinute":540,"endMinute":720,"location":"A"},{"weekday":4,"weeks":[3,4],"startMinute":540,"endMinute":720,"location":"A"}]}]}"#)[0]
        let repeatedRows = repeated["meetings"] as! [[String: Any]]
        check(repeatedRows.count == 1 && repeatedRows[0]["weekday"] as? Int == 4 && repeatedRows[0]["weeks"] as? [Int] == [3,4], "exact duplicate removed without borrowing the course source line")
        check(repeated["pendingReason"] is NSNull, "count checks distinct arrangements")
        check(DeepSeekTimetableClient.schedulePrefix("6–10、12 周二")?.weeks == [6,7,8,9,10,12], "unicode ranges preserve gaps")
        check(DeepSeekTimetableClient.schedulePrefix("3-11周 三楼报告厅") == nil, "a room beginning with a weekday character is not a weekday")
        check(DeepSeekTimetableClient.schedulePrefix("3-11周四上午")?.weekday == 4, "a weekday can directly precede a time label")
        check(DeepSeekTimetableClient.schedulePrefix("1-7周二（单 周）") == nil, "spacing cannot erase alternating-week exceptions")
        let identityCases = try courses(#"{"courses":[{"name":"专题甲-2","titleText":"专题甲-2","section":"2","sectionSource":"titleSuffix","sourceKind":"grid","listedMeetingCount":9,"listRows":["伪名单"],"meetings":[{"weekday":2,"weeks":[3],"startMinute":540,"endMinute":720}]},{"name":"专题乙","titleText":"专题甲","sourceKind":"grid","meetings":[{"weekday":2,"weeks":[3],"startMinute":540,"endMinute":720}]},{"name":"设计-2","titleText":"设计-2","sourceKind":"grid","meetings":[{"weekday":2,"weeks":[3],"startMinute":540,"endMinute":720}]}]}"#)
        check(identityCases[0]["name"] as? String == "专题甲" && identityCases[0]["section"] as? String == "2", "confirmed teaching section is separated from the title")
        let gridRaw = identityCases[0]["raw"] as! [String: Any]
        check(gridRaw["listRows"] is NSNull && gridRaw["listedMeetingCount"] is NSNull, "grid-only evidence cannot claim a list count")
        check(identityCases[1]["name"] as? String == "专题乙" && ((identityCases[1]["raw"] as! [String: Any])["recognitionWarnings"] as! [String]).contains(where: { $0.contains("课名与标题原文不一致") }), "semantic title disagreement is flagged without guessing a correction")
        check(identityCases[2]["name"] as? String == "设计-2" && identityCases[2]["section"] is NSNull, "an unconfirmed numeric suffix is never stripped")
        let numbered = try courses(#"{"courses":[{"name":"设计-2","titleText":"设计-2","section":"2","sectionSource":"field","sourceKind":"list","listRows":[],"meetings":[],"pendingReason":"待定"}]}"#)[0]
        check(numbered["name"] as? String == "设计-2", "a numbered title is preserved when section comes from a separate field")
        let constructedTitle = try courses(#"{"courses":[{"name":"专题甲","titleText":"专题甲-2","section":"2","sectionSource":"field","sourceKind":"list","listRows":[],"meetings":[],"pendingReason":"待定"}]}"#)[0]
        check(((constructedTitle["raw"] as! [String: Any])["recognitionWarnings"] as! [String]).contains(where: { $0.contains("课名与标题原文不一致") }), "a separately labeled section cannot be appended to title evidence")
        let coverage = try courses(#"{"courses":[{"name":"专题甲","titleText":"专题甲","sourceKind":"list","listRows":["3周二上午A","4周三上午B"],"meetings":[{"listRow":1,"weekday":2,"weeks":[3],"startMinute":540,"endMinute":720,"location":"A"},{"listRow":1,"weekday":2,"weeks":[3],"startMinute":810,"endMinute":990,"location":"A"}]}]}"#)[0]
        check(((coverage["raw"] as! [String: Any])["recognitionWarnings"] as! [String]).contains(where: { $0.contains("名单第2行未对应") }), "equal counts cannot hide an uncovered list row")
        let alternating = try courses(#"{"courses":[{"name":"专题甲","meetings":[{"sourceLine":"1-7周二(单周)","weekday":2,"weeks":[1,3,5,7],"gridWeekday":2,"gridWeeks":[1,3,5,7],"startMinute":540,"endMinute":720}]}]}"#)[0]
        check((alternating["meetings"] as! [[String: Any]])[0]["weeks"] as? [Int] == [1,3,5,7], "a numeric prefix cannot fill excluded weeks")
        check(meeting["startMinute"] as? Int == 810 && meeting["endMinute"] as? Int == 990, "afternoon clocks retained")
        check(meeting["sourceReference"] as? String == "3,4,6-7周一下午", "source retained")
        check(referenceCourses[0]["teacher"] is NSNull, "a week line is not a teacher")
        check(referenceCourses[2]["teacher"] is NSNull, "联系老师 is not a labeled teacher")
        check((referenceCourses[2]["meetings"] as! [Any]).isEmpty, "reference pending retained")
        let meetingTeacher = try courses(#"{"courses":[{"name":"中国画","teacher":null,"meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":"6406","teacher":"葛玉清"}]}]}"#)
        check(meetingTeacher[0]["teacher"] as? String == "葛玉清", "meeting teacher is kept")
        let labeled = try courses(#"{"courses":[{"name":"中国画","teacher":null,"sourceLine":"中国画 教师：葛玉清 周一","meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":null}]}]}"#)
        check(labeled[0]["teacher"] as? String == "葛玉清", "labeled source line keeps the teacher")
        let unlabeled = try courses(#"{"courses":[{"name":"中国画","teacher":null,"sourceLine":"中国画 葛玉清 周一","meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":null}]}]}"#)
        check(unlabeled[0]["teacher"] is NSNull, "unlabeled source line is not a teacher")
        let conflictTeachers = try courses(#"{"courses":[{"name":"中国画","teacher":null,"meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":null,"teacher":"葛玉清"},{"weekday":2,"weeks":[1],"startMinute":540,"endMinute":630,"location":null,"teacher":"李老师"}]}]}"#)
        check(conflictTeachers[0]["teacher"] is NSNull, "conflicting meeting teachers stay empty")
        let aliases = try courses(#"{"courses":[{"name":"中国画","课程代码":"ART-01","教学班":"一班","教师":"葛玉清","教室":"6406","meetings":[{"weekday":1,"weeks":null,"startMinute":null,"endMinute":null,"location":null}]}]}"#)
        check(aliases[0]["courseCode"] as? String == "ART-01" && aliases[0]["section"] as? String == "一班" && aliases[0]["teacher"] as? String == "葛玉清", "Chinese field names are kept")
        let aliasMeeting = (aliases[0]["meetings"] as! [[String: Any]])[0]
        check(aliasMeeting["location"] as? String == "6406" && aliasMeeting["weeks"] is NSNull && aliasMeeting["startMinute"] is NSNull && aliasMeeting["endMinute"] is NSNull, "course room fills an empty meeting without inventing time")
        let explicitRoom = try courses(#"{"courses":[{"name":"中国画","教室":"其他","meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":"6406"}]}]}"#)
        check((explicitRoom[0]["meetings"] as! [[String: Any]])[0]["location"] as? String == "6406", "an explicit room stays")
        let placeholder = try courses(#"{"courses":[{"name":"导师课","teacher":"待定","meetings":[],"pendingReason":"联系老师"}]}"#)
        check(placeholder[0]["teacher"] is NSNull && (placeholder[0]["meetings"] as! [Any]).isEmpty, "placeholder is not a teacher name")
        let ignoredAlias = try courses(#"{"courses":[{"name":"中国画","教师":123,"meetings":[{"weekday":1,"weeks":[1],"startMinute":540,"endMinute":630,"location":null}]}]}"#)
        check(ignoredAlias[0]["teacher"] is NSNull, "a non-string alias is ignored")
        expect(.invalidCourseField("courses[0].teacher"), "non-string teacher") {
            _ = try DeepSeekTimetableClient.parseResponse(envelope(valid.replacingOccurrences(of: "\"teacher\":null", with: "\"teacher\":123")))
        }
        let incomplete = try courses(#"{"courses":[{"name":"未知安排","meetings":[{"weekday":1,"weeks":[],"startMinute":810}]}]}"#)[0]
        let partial = (incomplete["meetings"] as! [[String: Any]])[0]
        check(partial["startMinute"] is NSNull && partial["endMinute"] is NSNull, "partial clock never fabricates interval")
        check((partial["raw"] as! [String: Any])["knownStartMinute"] as? Int == 810, "known clock preserved in raw")
        check(incomplete["pendingReason"] is String && partial["weeks"] is NSNull, "unknown weeks stay pending")
        expect(.invalidJSON, "do not salvage prose") { _ = try DeepSeekTimetableClient.parseResponse(envelope("结果是" + valid)) }
        expect(.truncatedResponse, "reject length") { _ = try DeepSeekTimetableClient.parseResponse(envelope(valid, reason: "length")) }
        for reason in [nil, "content_filter", "tool_calls"] as [String?] {
            expect(.invalidResponse, "require stop") { _ = try DeepSeekTimetableClient.parseResponse(envelope(valid, reason: reason)) }
        }
        let pending = #"{"courses":[{"name":"导师课","meetings":[],"pendingReason":"时间待定"}]}"#
        check(try courses(pending)[0]["name"] as? String == "导师课", "pending preserved")
        let missingWeeks = valid.replacingOccurrences(of: "\"weeks\":[3,4,6]", with: "\"weeks\":null").replacingOccurrences(of: "\"pendingReason\":null", with: "\"pendingReason\":\"周次待核对\"")
        check(try (courses(missingWeeks)[0]["meetings"] as! [[String: Any]])[0]["weeks"] is NSNull, "explicit unknown preserved")
        let tiny = png(width: 1)
        try DeepSeekTimetableClient.validateImage(AIImportImage(data: tiny, mimeType: "image/png"), index: 0)
        assertions += 1
        expect(.invalidImage(index: 0), "mime mismatch") { try DeepSeekTimetableClient.validateImage(AIImportImage(data: tiny, mimeType: "image/jpeg"), index: 0) }
        expect(.invalidImage(index: 0), "unsupported mime") { try DeepSeekTimetableClient.validateImage(AIImportImage(data: tiny, mimeType: "image/gif"), index: 0) }
        expect(.invalidImage(index: 0), "dimension bound") { try DeepSeekTimetableClient.validateImage(AIImportImage(data: png(width: 8193), mimeType: "image/png"), index: 0) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineDeepSeekProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = DeepSeekTimetableClient(apiKey: "offline-fake-key", session: session)
        var capturedContent: [[String: Any]] = []
        var requests = 0
        OfflineDeepSeekProtocol.handler = { request in
            check(request.url == DeepSeekTimetableClient.endpoint, "fixed endpoint")
            let data: Data
            if let body = request.httpBody { data = body }
            else {
                let stream = request.httpBodyStream!
                stream.open(); defer { stream.close() }
                var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(buffer, count: count) }
                data = bytes
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            requests += 1
            capturedContent = (body["messages"] as! [[String: Any]])[1]["content"] as! [[String: Any]]
            check(body["model"] as? String == "deepseek-flash", "fixed model")
            check(body["max_tokens"] as? Int == DeepSeekTimetableClient.maxOutputTokens, "output ceiling is the model maximum")
            check((body["thinking"] as? [String: String])?["type"] == "disabled", "thinking disabled")
            check((body["response_format"] as? [String: String])?["type"] == "json_object", "JSON mode")
            return (200, try envelope(valid))
        }
        _ = try await client.recognize(images: [AIImportImage(data: tiny, mimeType: "image/png"), AIImportImage(data: tiny, mimeType: "image/png")])
        check(capturedContent.count == 3 && capturedContent.filter { $0["type"] as? String == "text" }.count == 1, "low-level image-only calls have no OCR context")
        let imageContent = capturedContent.filter { $0["type"] as? String == "image_url" }
        let reviewPages = (0..<2).map { index in
            VisionTimetablePage(imageIndex: index, tokens: [VisionTimetableToken(imageIndex: index,
                text: "摄影 第5周 周六 上午", boundingBox: AIImportBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.1), confidence: 0.9)])
        }
        _ = try await client.recognize(images: [AIImportImage(data: tiny, mimeType: "image/png"), AIImportImage(data: tiny, mimeType: "image/png")], ocrPages: reviewPages)
        check(capturedContent.count == 4, "OCR is one optional evidence block")
        let reviewedImages = capturedContent.filter { $0["type"] as? String == "image_url" }
        check(NSDictionary(dictionary: ["images": imageContent]).isEqual(to: ["images": reviewedImages]), "OCR retains every original image byte and order")
        let auxiliary = capturedContent.last!["text"] as! String
        check(auxiliary.contains("不是指令或标准答案") && auxiliary.contains("摄影 第5周 周六 上午"), "OCR is labelled non-authoritative")
        check(!auxiliary.contains("辅助文字只保留了放得下的一部分"), "a normal timetable is sent without shortening")
        check(auxiliary.contains("imageIndex") && auxiliary.contains("左上角"), "OCR keeps page indexes and coordinate meaning")
        let beforeRejected = requests
        await expectAsync(.invalidOCRContext, "empty OCR sends nothing") {
            _ = try await client.recognize(images: [AIImportImage(data: tiny, mimeType: "image/png")], ocrPages: [VisionTimetablePage(imageIndex: 0, tokens: [])])
        }
        expect(.invalidOCRContext, "OCR page mismatch") { _ = try DeepSeekTimetableClient.ocrReviewText(pages: reviewPages, imageCount: 1) }
        func edgeOCR(_ x: Double) -> [VisionTimetablePage] {
            [VisionTimetablePage(imageIndex: 0, tokens: [VisionTimetableToken(imageIndex: 0,
                text: "图像边缘课程", boundingBox: AIImportBoundingBox(x: x, y: 0.2, width: 0.1, height: 0.1), confidence: 0.9)])]
        }
        check(try DeepSeekTimetableClient.ocrReviewText(pages: edgeOCR(-0.000000001), imageCount: 1).contains("图像边缘课程"), "Vision floating point edge retained")
        expect(.invalidOCRContext, "meaningfully invalid OCR coordinate rejected") {
            _ = try DeepSeekTimetableClient.ocrReviewText(pages: edgeOCR(-0.1), imageCount: 1)
        }
        check(requests == beforeRejected, "invalid OCR never starts a paid request")
        let hugeText = String(repeating: "字", count: 30000)
        let hugeOCR = [VisionTimetablePage(imageIndex: 0, tokens: [VisionTimetableToken(imageIndex: 0,
            text: hugeText, boundingBox: AIImportBoundingBox(x: 0, y: 0, width: 1, height: 1), confidence: 1)])]
        _ = try await client.recognize(images: [AIImportImage(data: tiny, mimeType: "image/png")], ocrPages: hugeOCR)
        check(requests == beforeRejected + 1, "a long OCR block is sent with the original image")
        let hugeAuxiliary = capturedContent.last!["text"] as! String
        check(hugeAuxiliary.contains(hugeText) && !hugeAuxiliary.contains("辅助文字只保留了放得下的一部分"), "a long OCR block is sent without a length cap")
        let crowded = (0..<4000).map { index in
            VisionTimetableToken(imageIndex: 1, text: "课\(index)", boundingBox: AIImportBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.1), confidence: 0.9)
        }
        let fullPages = [
            VisionTimetablePage(imageIndex: 0, tokens: [
                VisionTimetableToken(imageIndex: 0, text: "课甲", boundingBox: AIImportBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.1), confidence: 0.9),
                VisionTimetableToken(imageIndex: 0, text: "课乙", boundingBox: AIImportBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.1), confidence: 0.9)
            ]),
            VisionTimetablePage(imageIndex: 1, tokens: crowded)
        ]
        let full = try DeepSeekTimetableClient.ocrReviewText(pages: fullPages, imageCount: 2)
        check(full.contains("课甲") && full.contains("课乙") && full.contains("课3999"), "every OCR token is kept")
        check(!full.contains("辅助文字只保留了放得下的一部分"), "crowded pages are not shortened")
        _ = try await client.recognize(text: "英语 周一 第3、4、6周 09:00-10:00")
        for (status, error) in [(401, DeepSeekTimetableClientError.unauthorized), (402, .paymentRequired), (429, .rateLimited), (503, .serverUnavailable(statusCode: 503))] {
            OfflineDeepSeekProtocol.handler = { _ in (status, Data()) }
            await expectAsync(error, "HTTP classification") { _ = try await client.recognize(text: "英语课表") }
        }
        OfflineDeepSeekProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await expectAsync(.transport, "network classification") { _ = try await client.recognize(text: "英语课表") }
        await expectAsync(.invalidTimetableText, "no HTML") { _ = try await client.recognize(text: "<input password='x'>") }
        await expectAsync(.invalidTimetableText, "no SSO url") { _ = try await client.recognize(text: "https://school/login?token=x") }
        await expectAsync(.missingAPIKey, "missing key") { _ = try await DeepSeekTimetableClient(apiKey: " ", session: session).recognize(text: "英语课表") }
        let english = #"{"courses":[{"name":"英语","teacher":null,"meetings":[{"weekday":1,"weeks":[3],"startMinute":540,"endMinute":600,"location":null}]}]}"#
        let art = #"{"courses":[{"name":"英语","teacher":"张三","meetings":[{"weekday":2,"weeks":[4],"startMinute":810,"endMinute":900,"location":"6406"}]}]}"#
        OfflineDeepSeekProtocol.handler = { _ in (200, try envelope(english, reason: "length")) }
        await expectAsync(.truncatedResponse, "one image stays truncated") {
            _ = try await client.recognize(images: [AIImportImage(data: tiny, mimeType: "image/png")])
        }
        var singlePages = 0
        OfflineDeepSeekProtocol.handler = { request in
            let data: Data
            if let body = request.httpBody { data = body }
            else {
                let stream = request.httpBodyStream!
                stream.open(); defer { stream.close() }
                var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(buffer, count: count) }
                data = bytes
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            check(body["max_tokens"] as? Int == DeepSeekTimetableClient.maxOutputTokens, "split requests keep the output ceiling")
            let content = (body["messages"] as! [[String: Any]])[1]["content"] as! [[String: Any]]
            let imageCount = content.filter { $0["type"] as? String == "image_url" }.count
            if imageCount > 1 { return (200, try envelope(english, reason: "length")) }
            singlePages += 1
            return (200, try envelope(singlePages == 1 ? english : art))
        }
        let merged = try await client.recognize(images: [AIImportImage(data: tiny, mimeType: "image/png"), AIImportImage(data: png(width: 2), mimeType: "image/png")])
        check(singlePages == 2, "two images become two requests after the combined response is truncated")
        let mergedCourses = (try JSONSerialization.jsonObject(with: Data(merged.jsonText.utf8)) as! [String: Any])["courses"] as! [[String: Any]]
        check(mergedCourses.count == 1, "split pages of the same course merge")
        check(mergedCourses[0]["teacher"] as? String == "张三", "teacher found on the second page fills the blank")
        check((mergedCourses[0]["meetings"] as! [[String: Any]]).count == 2, "distinct meetings from both pages are kept")
        func courseNames(_ result: DeepSeekTimetableResult) throws -> [[String: Any]] {
            (try JSONSerialization.jsonObject(with: Data(result.jsonText.utf8)) as! [String: Any])["courses"] as! [[String: Any]]
        }
        let ambiguousMerge = try DeepSeekTimetableClient.mergeResults(
            DeepSeekTimetableResult(jsonText: #"{"courses":[{"name":"英语","teacher":null,"meetings":[{"weekday":1,"weeks":[3],"startMinute":540,"endMinute":600,"location":null}]}]}"#, finishReason: "stop"),
            DeepSeekTimetableResult(jsonText: #"{"courses":[{"name":"英语","teacher":"张三","meetings":[{"weekday":2,"weeks":[4],"startMinute":810,"endMinute":900,"location":"6406"}]},{"name":"英语","teacher":"李四","meetings":[{"weekday":3,"weeks":[5],"startMinute":810,"endMinute":900,"location":"6407"}]}]}"#, finishReason: "stop")
        )
        let ambiguousCourses = try courseNames(ambiguousMerge)
        check(ambiguousCourses.count == 3, "a blank teacher stays separate when two classes share the name")
        let blankClass = ambiguousCourses.first { $0["teacher"] is NSNull }!
        check(((blankClass["meetings"] as! [[String: Any]])[0]["weekday"] as? Int) == 1, "the unnamed meeting is not given to the first teacher")
        let pendingMerge = try DeepSeekTimetableClient.mergeResults(
            DeepSeekTimetableResult(jsonText: #"{"courses":[{"name":"英语","teacher":"张三","meetings":[],"pendingReason":"安排待定"}]}"#, finishReason: "stop"),
            DeepSeekTimetableResult(jsonText: #"{"courses":[{"name":"英语","teacher":"张三","meetings":[{"weekday":1,"weeks":[3],"startMinute":540,"endMinute":600,"location":null}]}]}"#, finishReason: "stop")
        )
        check(try courseNames(pendingMerge).count == 2, "a pending course is not folded into a scheduled course")
        let incompleteMerge = try DeepSeekTimetableClient.mergeResults(
            DeepSeekTimetableResult(jsonText: #"{"courses":[{"name":"英语","teacher":"张三","meetings":[{"weekday":1,"weeks":[3],"startMinute":null,"endMinute":null,"location":"6406"}]}]}"#, finishReason: "stop"),
            DeepSeekTimetableResult(jsonText: #"{"courses":[{"name":"英语","teacher":"张三","meetings":[{"weekday":1,"weeks":[3],"startMinute":null,"endMinute":null,"location":"6406"}]}]}"#, finishReason: "stop")
        )
        check(((try courseNames(incompleteMerge))[0]["meetings"] as! [[String: Any]]).count == 2, "meetings without clocks are both kept")
        OfflineDeepSeekProtocol.handler = { _ in preconditionFailure("pre-cancelled request sent") }
        let preCancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await client.recognize(text: "英语课表") }
        await expectAsync(.cancelled, "cancel before request") { _ = try await preCancelled.value }
        let cancelledOCR = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VisionTimetableRecognizer().recognize(images: [UIImage()])
        }
        do {
            _ = try await cancelledOCR.value
            check(false, "cancelled local OCR must not return pages")
        } catch {
            check(error as? VisionTimetableRecognizerError == .cancelled, "local OCR honours cancellation before image work")
        }
        do {
            _ = try await VisionTimetableRecognizer().recognize(images: [UIImage()])
            check(false, "unreadable OCR image must not return pages")
        } catch {
            check(error as? VisionTimetableRecognizerError == .invalidImage, "unreadable local OCR fails before the model request")
        }
        let started = DispatchSemaphore(value: 0)
        OfflineDeepSeekProtocol.handler = { _ in started.signal(); return nil }
        let active = Task { try await client.recognize(text: "英语课表") }
        let didStart = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: started.wait(timeout: .now() + 5) == .success) }
        }
        check(didStart, "request started")
        active.cancel()
        await expectAsync(.cancelled, "cancel in flight") { _ = try await active.value }
        func token(_ text: String, x: Double, y: Double, image: Int = 0) -> VisionTimetableToken {
            VisionTimetableToken(imageIndex: image, text: text, boundingBox: AIImportBoundingBox(x: x, y: y, width: 0.12, height: 0.05), confidence: 0.95)
        }
        func page(_ image: Int, weeks: String = "3、4、6周", room: String = "6406", header: Bool = true, clock: Bool = true) -> VisionTimetablePage {
            var tokens = [token("英语\n" + weeks + "\n教室：" + room, x: 0.3, y: 0.4, image: image)]
            if header { tokens.append(token("周一", x: 0.3, y: 0.05, image: image)) }
            if clock { tokens.append(token("09:00-10:00", x: 0.02, y: 0.4, image: image)) }
            return VisionTimetablePage(imageIndex: image, tokens: tokens)
        }
        let parsed = VisionScheduleDraftParser.parse(pages: [page(0), page(1)])
        let visionCourses = parsed["courses"] as! [[String: Any]]
        check(visionCourses.count == 1, "exact multi-image duplicate")
        let visionMeeting = (visionCourses[0]["meetings"] as! [[String: Any]])[0]
        check(visionMeeting["weekday"] as? Int == 1, "explicit header column")
        check(visionMeeting["startMinute"] as? Int == 540 && visionMeeting["endMinute"] as? Int == 600, "explicit clock row")
        check(visionMeeting["weeks"] as? [Int] == [3,4,6], "missing week preserved")
        let sources = (visionCourses[0]["raw"] as! [String: Any])["sources"] as! [[String: Any]]
        check(Set(sources.compactMap { $0["imageIndex"] as? Int }) == Set([0,1]), "source image indexes retained")
        let variants = VisionScheduleDraftParser.parse(pages: [page(0), page(1, weeks: "7-8周"), page(2, room: "6407")])["courses"] as! [[String: Any]]
        check(variants.count == 3, "distinct weeks and rooms remain separate")
        for pendingPage in [page(0, header: false), page(0, clock: false)] {
            let course = (VisionScheduleDraftParser.parse(pages: [pendingPage])["courses"] as! [[String: Any]])[0]
            check(course["pendingReason"] is String, "missing grid anchors pending")
            let incomplete = (course["meetings"] as! [[String: Any]])[0]
            check(incomplete["startMinute"] is NSNull, "missing grid anchors cannot make clock")
        }
        var ambiguous = page(0).tokens
        ambiguous.append(token("摄影\n7-8周\n教室：6408", x: 0.3, y: 0.46))
        let candidates = VisionScheduleDraftParser.parse(pages: [VisionTimetablePage(imageIndex: 0, tokens: ambiguous)])["courses"] as! [[String: Any]]
        check(Set(candidates.compactMap { $0["name"] as? String }) == Set(["英语", "摄影"]), "ambiguous cell preserves both names")
        check(candidates.allSatisfy { $0["pendingReason"] is String }, "ambiguous cell cannot borrow other course times")
        let clipped = VisionTimetableRecognizer.clipToUnit(AIImportBoundingBox(x: -0.001, y: 0.2, width: 0.101, height: 0.1))
        check(clipped?.x == 0 && abs((clipped?.width ?? 0) - 0.1) < 0.000001, "near-edge Vision box stays inside the image")
        check(VisionTimetableRecognizer.clipToUnit(AIImportBoundingBox(x: -0.2, y: 0.2, width: 0.1, height: 0.1)) == nil, "box outside the image is dropped")
        print("AIImportOfflineTests PASS: \(assertions) assertions; URLProtocol only, no real network, no Keychain writes")
    }
}
#endif
