import Foundation

/// 存储于 Keychain 的凭据。整个结构序列化成一个 Keychain item，避免密钥落盘。
public struct ProviderCredential: Codable, Sendable, Equatable {
    /// API key / Control Key。空字符串代表未配置。
    public var apiKey: String
    /// Open Design 需要工作区 ID；为空时自动发现。
    public var workspaceID: String?
    /// 备用：直接粘贴浏览器 Cookie 头（Open Design 的额度端点有时只认会话）。
    public var cookie: String?

    public init(apiKey: String = "", workspaceID: String? = nil, cookie: String? = nil) {
        self.apiKey = apiKey
        self.workspaceID = workspaceID
        self.cookie = cookie
    }

    public var isEmpty: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (cookie ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasCookie: Bool {
        !(cookie ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
