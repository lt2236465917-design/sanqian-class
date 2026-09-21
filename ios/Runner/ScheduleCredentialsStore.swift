import Foundation
import Security
import CryptoKit

/// Safe metadata can cross the Flutter bridge. It deliberately has no password.
public struct SchoolAccountMetadata {
    public let account: String
    public let accountLocalId: String
}

/// Keychain only. The API key and school login occupy distinct items.
/// No values are printed, synchronized to iCloud, or written to shared storage.
public final class ScheduleCredentialsStore {
    public static let shared = ScheduleCredentialsStore()
    public let service: String
    private let account: String
    private let lock = NSRecursiveLock()
    private var schoolItem: String { account + ".school.active" }

    public init(service: String = "com.sanqian.schedule.credentials", account: String = "deepseek.apiKey") {
        self.service = service
        self.account = account
    }

    public func saveDeepSeekAPIKey(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ScheduleCredentialsStoreError.invalidValue }
        try save(Data(value.utf8), item: account)
    }
    public func loadDeepSeekAPIKey() throws -> String? {
        guard let data = try load(item: account) else { return nil }
        guard let key = String(data: data, encoding: .utf8), !key.isEmpty else { throw ScheduleCredentialsStoreError.invalidValue }
        return key
    }
    public func hasDeepSeekAPIKey() throws -> Bool { try load(item: account) != nil }
    public func deleteDeepSeekAPIKey() throws { try delete(item: account) }

    /// A random per-account local ID remains stable if the active account is
    /// switched or cleared. The identity map contains no password.
    @discardableResult
    public func saveSchoolCredentials(account username: String, password: String) throws -> SchoolAccountMetadata {
        lock.lock(); defer { lock.unlock() }
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else { throw ScheduleCredentialsStoreError.invalidValue }
        let digest = SHA256.hash(data: Data(username.utf8)).map { String(format: "%02x", $0) }.joined()
        let identityItem = account + ".school.identity." + digest
        let localId: String
        if let bytes = try load(item: identityItem), let saved = String(data: bytes, encoding: .utf8), UUID(uuidString: saved) != nil {
            localId = saved
        } else {
            localId = UUID().uuidString
            try save(Data(localId.utf8), item: identityItem)
        }
        let bytes = try JSONSerialization.data(withJSONObject: ["account": username, "password": password, "accountLocalId": localId])
        try save(bytes, item: schoolItem)
        return SchoolAccountMetadata(account: username, accountLocalId: localId)
    }

    public func schoolAccountMetadata() throws -> SchoolAccountMetadata? {
        guard let value = try schoolCredentials() else { return nil }
        return SchoolAccountMetadata(account: value.account, accountLocalId: value.accountLocalId)
    }

    public func deleteSchoolCredentials() throws { try delete(item: schoolItem) }

    /// Native-only login injection callback. Never expose its password argument
    /// in a MethodChannel return value. The portal must verify the IAM origin
    /// and the explicitly requested login page before invoking this callback.
    func withSchoolCredentials(_ fill: (_ account: String, _ password: String) throws -> Void) throws {
        guard let value = try schoolCredentials() else { throw ScheduleCredentialsStoreError.notFound }
        try fill(value.account, value.password)
    }

    private func schoolCredentials() throws -> (account: String, password: String, accountLocalId: String)? {
        guard let data = try load(item: schoolItem) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let username = json["account"], !username.isEmpty,
              let password = json["password"], !password.isEmpty,
              let id = json["accountLocalId"], UUID(uuidString: id) != nil else {
            throw ScheduleCredentialsStoreError.invalidValue
        }
        return (username, password, id)
    }

    private func query(_ item: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: item, kSecAttrSynchronizable as String: false]
    }
    private func save(_ data: Data, item: String) throws {
        lock.lock(); defer { lock.unlock() }
        // Accessibility is reapplied on update as well as insert.
        let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query(item) as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query(item)
            values.forEach { insert[$0.key] = $0.value }
            status = SecItemAdd(insert as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(query(item) as CFDictionary, values as CFDictionary) }
        }
        guard status == errSecSuccess else { throw ScheduleCredentialsStoreError.status(status) }
    }
    private func load(item: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        var values = query(item)
        values[kSecReturnData as String] = true
        values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(values as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ScheduleCredentialsStoreError.status(status) }
        guard let data = result as? Data else { throw ScheduleCredentialsStoreError.invalidValue }
        return data
    }
    private func delete(item: String) throws {
        lock.lock(); defer { lock.unlock() }
        let status = SecItemDelete(query(item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ScheduleCredentialsStoreError.status(status) }
    }
}

public enum ScheduleCredentialsStoreError: Error, Equatable {
    case invalidValue
    case notFound
    case status(OSStatus)
}
extension ScheduleCredentialsStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidValue: return "凭据为空或格式无效"
        case .notFound: return "未保存学校账号"
        case .status(let status): return "无法访问安全凭据存储（\(status)）"
        }
    }
}
