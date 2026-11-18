import Foundation

/// 一个可独立配置的账号。同一服务商可以有多个账号（个人 / 工作 / 团队…）。
/// 账号元数据（名称、服务商）存 JSON；密钥按账号 UUID 单独存 Keychain。
public struct Account: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var provider: ProviderID
    public var label: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        provider: ProviderID,
        label: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.label = label
        self.createdAt = createdAt
    }

    public var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.displayName : trimmed
    }
}
