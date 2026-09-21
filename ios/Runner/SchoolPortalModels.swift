import Foundation

/// Credentials are intentionally in-memory only. They are never Codable and are never
/// accepted as part of a frame message.
struct SchoolPortalCredentials {
    let username: String
    let password: String

    var isComplete: Bool { !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty }
}

struct SchoolPortalConfiguration {
    let loginURL: URL
    let sessionBootstrapURL: URL?
    let allowedHosts: Set<String>
    let extractionMessageName: String

    init(loginURL: URL, allowedHosts: Set<String>, extractionMessageName: String = "sanqianSchoolSchedule", sessionBootstrapURL: URL? = nil) {
        self.loginURL = loginURL
        self.sessionBootstrapURL = sessionBootstrapURL
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        self.extractionMessageName = extractionMessageName
    }

    /// The concrete campus endpoints are deliberately supplied by the caller. The
    /// integration does not claim that any endpoint has been verified online.
    static let unconfigured = SchoolPortalConfiguration(
        loginURL: URL(string: "https://invalid.local/")!,
        allowedHosts: []
    )
}

enum SchoolPortalPhase: String, Codable, Equatable {
    case idle
    case loading
    case needsManualAuthentication
    case ready
    case extracting
    case parsed
    case failed
}

struct SchoolPortalSessionState: Codable, Equatable {
    let phase: SchoolPortalPhase
    let currentURL: String?
    let isLoggedIn: Bool
    let extractionID: String?
    let errorMessage: String?

    static let idle = SchoolPortalSessionState(
        phase: .idle, currentURL: nil, isLoggedIn: false, extractionID: nil, errorMessage: nil
    )
}

struct SchoolPortalTableCell: Codable, Equatable {
    let text: String
    let rowSpan: Int
    let colSpan: Int

    init(text: String, rowSpan: Int = 1, colSpan: Int = 1) {
        self.text = text
        self.rowSpan = max(1, rowSpan)
        self.colSpan = max(1, colSpan)
    }
}

struct SchoolPortalFrameIdentity: Codable, Equatable {
    let url: String
    let securityOrigin: String
    let isMainFrame: Bool
}

/// The only message accepted from JavaScript. It carries table material, never
/// username, password, cookies, hidden inputs, or SSO query parameters.
struct SchoolPortalFrameMessage: Codable, Equatable {
    static let currentVersion = 1
    let version: Int
    let kind: String
    let requestID: String
    let frame: SchoolPortalFrameIdentity
    let title: String
    let innerText: String
    let html: String
    let rows: [[SchoolPortalTableCell]]
    var truncated: Bool? = nil

    var isExtractionMessage: Bool { kind == "scheduleTables" && version == Self.currentVersion }
}

struct SchoolScheduleDraft: Codable, Equatable, Hashable {
    let source: String
    var courseCode: String?
    var classCode: String?
    var title: String
    var teacher: String
    var location: String
    var weekday: Int?
    var weeks: [Int]?
    var startMinutes: Int?
    var endMinutes: Int?
    var term: String?
    var pendingReason: String?
    var notes: String
    var sourceURL: String?
    var rawText: String
    var startPeriod: Int? = nil
    var endPeriod: Int? = nil

    var isPending: Bool {
        weekday == nil || weeks == nil || startMinutes == nil || endMinutes == nil
    }

    var identityKey: String {
        let weekKey = weeks?.map(String.init).joined(separator: ",") ?? "?"
        return [courseCode ?? title, classCode ?? "", teacher, String(weekday ?? 0), String(startMinutes ?? -1), String(endMinutes ?? -1), String(startPeriod ?? -1), String(endPeriod ?? -1), location, weekKey, isPending ? rawText : ""]
            .joined(separator: "|")
    }
}

struct SchoolScheduleParseResult: Codable, Equatable {
    let source: String
    let sourceURL: String?
    let frameCount: Int
    let tableCount: Int
    let drafts: [SchoolScheduleDraft]
    let warnings: [String]
    /// Original timetable cells only. Kept in memory for explicitly confirmed
    /// AI recognition, independently of whether the local parser made drafts.
    var timetableText: String? = nil

    var hasConfirmedDrafts: Bool { drafts.contains(where: { !$0.isPending }) }
    var canReview: Bool { !drafts.isEmpty || !(timetableText ?? "").isEmpty }
}

extension SchoolPortalFrameMessage {
    /// Decode the Foundation object delivered by WKScriptMessage without allowing
    /// arbitrary values to become a credential-bearing message.
    init?(body: Any) {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: []) else { return nil }
        guard let decoded = try? JSONDecoder().decode(Self.self, from: data), decoded.isExtractionMessage else { return nil }
        self = decoded
    }
}

/// URL and origin checks are shared with the offline security regression tests.
enum SchoolPortalSecurity {
    static func allows(scheme: String, host: String, allowedHosts: Set<String>) -> Bool {
        scheme.lowercased() == "https" && allowedHosts.contains(host.lowercased())
    }

    static func sanitizedURL(_ url: URL?) -> String? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url?.absoluteString
    }
}
