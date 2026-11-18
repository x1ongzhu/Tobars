import Foundation

/// Command Code 的用量数据来自 Studio 的 alpha 接口（CLI `/usage` 用的同一组）：
///   GET /alpha/whoami?limits=1
///   GET /alpha/billing/credits?orgId=…
///   GET /alpha/billing/subscriptions?orgId=…
///   GET /alpha/usage/summary?orgId=…&since=…
/// 全部使用 `Authorization: Bearer <API key>`。
public struct CommandCodeProvider: UsageProviding {
    public let id: ProviderID = .commandCode
    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchUsage(credential: ProviderCredential) async throws -> ProviderUsage {
        let key = credential.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ProviderError.missingCredential }
        let headers = ["Authorization": "Bearer \(key)"]

        let whoami = try await get("/alpha/whoami?limits=1", headers: headers)
        let orgID = whoami["org"]?["id"].string
        let orgLogin = whoami["org"]?["login"].string
        let userName = whoami["user"]?["userName"].string

        let query = orgID.map { id -> String in
            let encoded = id.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? id
            return "?orgId=\(encoded)"
        } ?? ""

        // 三项独立请求：任一失败不应吞掉其他已经拿到的窗口。
        async let creditsTask = try? get("/alpha/billing/credits\(query)", headers: headers)
        async let subscriptionTask = try? get("/alpha/billing/subscriptions\(query)", headers: headers)
        async let summaryTask = try? get("/alpha/usage/summary\(query)", headers: headers)
        let (credits, subscription, summary) = await (creditsTask, subscriptionTask, summaryTask)

        guard credits != nil || subscription != nil || summary != nil else {
            throw ProviderError.malformed("whoami 之外的用量接口全部失败")
        }

        let planID = subscription?["data"]?["planId"].string
            ?? credits?["credits"]?["planId"].string
        let planName = planID.map(Self.displayPlan)
        var windows: [UsageWindow] = []
        var note: String?

        // 5 小时 / 每周窗口：$ 用量 + 上限。
        // 真实响应里 windowLimits 在顶层（与 credits 同级）；旧样本里可能在 credits 内，
        // 两种形状都接受。
        let limits = credits?["windowLimits"] ?? credits?["credits"]?["windowLimits"]
        if let fiveHour = limits?["fiveHour"] {
            let used = fiveHour["used"].double
            let cap = fiveHour["cap"].double
            if let window = UsageWindow(
                kind: .session,
                id: "fiveHour",
                label: "5 小时",
                used: used,
                limit: cap,
                resetsAt: fiveHour["resetAt"].date ?? fiveHour["resetsAt"].isoDate
            ) {
                windows.append(window)
            }
        }
        if let weekly = limits?["weekly"] {
            let used = weekly["used"].double
            let cap = weekly["cap"].double
            if let window = UsageWindow(
                kind: .weekly,
                id: "weekly",
                label: "每周",
                used: used,
                limit: cap,
                resetsAt: weekly["resetAt"].date ?? weekly["resetsAt"].isoDate
            ) {
                windows.append(window)
            }
        }
        if limits?["limited"].bool == true {
            note = "已触发窗口限额"
        }

        // 月度额度：spent + remaining 反推总池，避免依赖各套餐的硬编码额度。
        let creditsBody = credits?["credits"]
        let remaining = (creditsBody?["monthlyCredits"].double ?? 0)
            + (creditsBody?["purchasedCredits"].double ?? 0)
            + (creditsBody?["freeCredits"].double ?? 0)
        let spent = summary?["totalCost"].double ?? summary?["total_cost"].double
        let pool = (spent ?? 0) + remaining
        if let spent, pool > 0, let window = UsageWindow(
            kind: .monthly,
            id: "monthly",
            label: "本月",
            used: spent,
            limit: pool,
            resetsAt: subscription?["data"]?["currentPeriodEnd"].isoDate
        ) {
            windows.append(window)
        }

        guard !windows.isEmpty else {
            throw ProviderError.malformed("未找到任何额度窗口")
        }

        var balance: String?
        let extra = (creditsBody?["purchasedCredits"].double ?? 0) + (creditsBody?["freeCredits"].double ?? 0)
        if extra > 0 {
            balance = "额外额度 \(UsageFormatting.usd(extra))"
        }

        return ProviderUsage(
            provider: id,
            planName: planName,
            accountLabel: userName ?? orgLogin,
            windows: windows,
            balance: balance,
            note: note
        )
    }

    private func get(_ path: String, headers: [String: String]) async throws -> JSON {
        guard let url = URL(string: "https://api.commandcode.ai\(path)") else {
            throw ProviderError.malformed("URL 拼装失败：\(path)")
        }
        let response = try await transport.get(url, headers: headers)
        return try response.validated(provider: id)
    }

    /// CLI 侧的 planId → 展示名映射。
    public static func displayPlan(_ planID: String) -> String {
        let normalized = planID.lowercased().replacingOccurrences(of: "_", with: "-")
        let table: [(String, String)] = [
            ("individual-goat", "GOAT"),
            ("individual-provider", "Provider"),
            ("individual-ultra", "Ultra"),
            ("individual-max", "Max"),
            ("individual-pro", "Pro"),
            ("individual-go", "Go"),
            ("teams-pro", "Teams Pro")
        ]
        for (prefix, name) in table where normalized.hasPrefix(prefix) {
            return name
        }
        return planID
    }
}
