import Foundation

/// 一条额度窗口（5 小时 / 每周 / 每月 …）。
public struct UsageWindow: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case session
        case weekly
        case monthly
        case daily
        case other
    }

    public let kind: Kind
    /// 供应商自己用的窗口名，用于稳定排序与去重（如 "rolling"、"fiveHour"）。
    public let id: String
    public let label: String
    /// 已用百分比，始终 clamp 到 0...100。
    public let usedPercent: Double
    public let resetsAt: Date?
    /// 金额或原始额度，例如 "$12.40 / $20.00"；仅有百分比时为 nil。
    public let detail: String?

    public init(
        kind: Kind,
        id: String,
        label: String,
        usedPercent: Double,
        resetsAt: Date? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
        self.detail = detail
    }

    /// 百分比未知时返回 nil，避免把「解析失败」画成 0%。
    public init?(kind: Kind, id: String, label: String, used: Double?, limit: Double?, resetsAt: Date?) {
        guard let used, let limit, limit > 0 else { return nil }
        self.init(
            kind: kind,
            id: id,
            label: label,
            usedPercent: used / limit * 100,
            resetsAt: resetsAt,
            detail: UsageFormatting.amountDetail(used: used, limit: limit)
        )
    }
}

/// 单个服务商一次拉取的完整结果。
public struct ProviderUsage: Codable, Sendable, Identifiable {
    public let provider: ProviderID
    public let planName: String?
    public let accountLabel: String?
    public let windows: [UsageWindow]
    /// 钱包 / 额外余额等附加信息，已格式化。
    public let balance: String?
    /// 供应商返回但不足以构成错误的信息，例如「无生效订阅」。
    public let note: String?
    public let fetchedAt: Date

    public var id: ProviderID { provider }

    public init(
        provider: ProviderID,
        planName: String? = nil,
        accountLabel: String? = nil,
        windows: [UsageWindow],
        balance: String? = nil,
        note: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.provider = provider
        self.planName = planName
        self.accountLabel = accountLabel
        self.windows = windows
        self.balance = balance
        self.note = note
        self.fetchedAt = fetchedAt
    }

    /// 所有窗口里最高的已用百分比，菜单栏图标用它做数字。
    public var peakPercent: Double? {
        windows.map(\.usedPercent).max()
    }
}
