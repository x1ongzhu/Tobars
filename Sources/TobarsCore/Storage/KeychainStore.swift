import Foundation
import Security

/// 只把凭据写进登录钥匙串；现在仅用于一次性迁移，运行期不再读取。
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = "ai.tobars.credentials") {
        self.service = service
    }

    public func save(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound {
            throw KeychainError(status: status)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    /// 只查属性、不取数据，正常不会触发密码弹窗。
    public func contains(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    public func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public struct KeychainError: LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "Keychain 错误 \(status)：\(message)"
        }
        return "Keychain 错误 \(status)"
    }
}

/// 运行期凭据存储：`~/Library/Application Support/Tobars/credentials.json`，权限 0600。
///
/// 不用 Keychain 的原因：本应用是 ad-hoc 签名，重建后代码签名变化会让 Keychain 每次
/// 启动都弹密码。与 command-code、opencode、vela 等 CLI 一样，改为 0600 本地文件；
/// 文件不进 git、不打印、不写日志。设置页可一次性从旧 Keychain 条目迁移。
public final class CredentialStore: @unchecked Sendable {
    public struct MigrationResult: Sendable {
        public let migrated: Int
        public let failed: Int
    }

    public let fileURL: URL
    private let keychain: KeychainStore
    private let lock = NSLock()

    public init(fileURL: URL? = nil, keychain: KeychainStore = KeychainStore()) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.fileURL = support
                .appendingPathComponent("Tobars", isDirectory: true)
                .appendingPathComponent("credentials.json")
        }
        self.keychain = keychain
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func load(accountID: UUID) -> ProviderCredential? {
        lock.lock()
        defer { lock.unlock() }
        return readFile()[Self.key(for: accountID)]
    }

    public func save(_ credential: ProviderCredential, accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var contents = readFile()
        contents[Self.key(for: accountID)] = credential
        try writeFile(contents)
    }

    public func delete(accountID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var contents = readFile()
        contents.removeValue(forKey: Self.key(for: accountID))
        try? writeFile(contents)
    }

    /// 把 Keychain 里的旧条目搬到文件。只在文件里缺该账号时读取，尽量少触发系统弹窗。
    @discardableResult
    public func migrateFromKeychain(accountIDs: [UUID]) -> MigrationResult {
        lock.lock()
        defer { lock.unlock() }

        var contents = readFile()
        var migrated = 0
        var failed = 0

        for id in accountIDs {
            let key = Self.key(for: id)
            guard contents[key] == nil, keychain.contains(account: key) else { continue }
            guard let raw = keychain.read(account: key), let credential = Self.decode(raw) else {
                failed += 1
                continue
            }
            contents[key] = credential
            migrated += 1
        }

        if migrated > 0 {
            do {
                try writeFile(contents)
            } catch {
                return MigrationResult(migrated: 0, failed: migrated + failed)
            }
        }
        return MigrationResult(migrated: migrated, failed: failed)
    }

    // MARK: - 文件

    private static func key(for accountID: UUID) -> String {
        "account.\(accountID.uuidString)"
    }

    private static func decode(_ raw: String) -> ProviderCredential? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProviderCredential.self, from: data)
    }

    private func readFile() -> [String: ProviderCredential] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: ProviderCredential].self, from: data)) ?? [:]
    }

    private func writeFile(_ contents: [String: ProviderCredential]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(contents)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
