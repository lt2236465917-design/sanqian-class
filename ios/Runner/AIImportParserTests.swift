#if AI_IMPORT_TESTS
import Foundation
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
    static func main() async throws {
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
        check(meeting["startMinute"] as? Int == 810 && meeting["endMinute"] as? Int == 990, "afternoon clocks retained")
        check(meeting["sourceReference"] as? String == "3,4,6-7周一下午", "source retained")
        check((referenceCourses[2]["meetings"] as! [Any]).isEmpty, "reference pending retained")
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
            check((body["thinking"] as? [String: String])?["type"] == "disabled", "thinking disabled")
            check((body["response_format"] as? [String: String])?["type"] == "json_object", "JSON mode")
            return (200, try envelope(valid))
        }
        _ = try await client.recognize(images: [AIImportImage(data: tiny, mimeType: "image/png"), AIImportImage(data: tiny, mimeType: "image/png")])
        check(capturedContent.count == 3 && capturedContent.filter { $0["type"] as? String == "text" }.count == 1, "default images have no OCR context")
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
        let hugeOCR = [VisionTimetablePage(imageIndex: 0, tokens: [VisionTimetableToken(imageIndex: 0,
            text: String(repeating: "字", count: 30000), boundingBox: AIImportBoundingBox(x: 0, y: 0, width: 1, height: 1), confidence: 1)])]
        await expectAsync(.ocrContextTooLarge(limit: DeepSeekTimetableClient.maxOCRContextBytes), "oversized OCR rejected without truncation or request") {
            _ = try await client.recognize(images: [AIImportImage(data: tiny, mimeType: "image/png")], ocrPages: hugeOCR)
        }
        check(requests == beforeRejected, "invalid OCR never starts a paid request")
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
        OfflineDeepSeekProtocol.handler = { _ in preconditionFailure("pre-cancelled request sent") }
        let preCancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await client.recognize(text: "英语课表") }
        await expectAsync(.cancelled, "cancel before request") { _ = try await preCancelled.value }
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
        print("AIImportOfflineTests PASS: \(assertions) assertions; URLProtocol only, no real network, no Keychain writes")
    }
}
#endif
