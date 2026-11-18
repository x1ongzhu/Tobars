import Foundation

/// Open Design Cloud 的额度数据（控制面接口，与官网控制台同源）：
///   GET https://amr-api.open-design.ai/api/v1/workspaces/current
///   GET https://amr-api.open-design.ai/api/v1/workspaces/{id}/billing/coding-plan-usage
///       X-Vela-Workspace-Id: {id}
///   GET https://amr-api.open-design.ai/api/v1/workspaces/{id}/wallet/balance
///
/// 认证只接受 **Control Key（vela_ctrl_…）** 或浏览器会话 Cookie；
/// `sk-amr-…` 推理密钥会被 401/403 拒绝。部分账号的 coding-plan-usage 只认 Cookie，
/// 所以 Bearer 失败时会自动回退到 `billing/preflight`（窗口数据嵌在 codingPlan 下）。
public struct OpenDesignProvider: UsageProviding {
    public let id: ProviderID = .openDesign
    private let transport: HTTPTransport
    private let baseURL = URL(string: "https://amr-api.open-design.ai")!

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchUsage(credential: ProviderCredential) async throws -> ProviderUsage {
        guard !credential.isEmpty else { throw ProviderError.missingCredential }

        var headers = authHeaders(credential)
        let workspace = try await resolveWorkspace(credential: credential, headers: headers)
        headers["X-Vela-Workspace-Id"] = workspace.id

        var note: String?
        var usedPreflight = false

        var response = try await transport.get(
            url("/api/v1/workspaces/\(workspace.id)/billing/coding-plan-usage"),
            headers: headers
        )

        // 只对认证失败回退一次；200 但结构异常时不重试。
        if (response.status == 401 || response.status == 403), !credential.hasCookie {
            usedPreflight = true
            response = try await transport.get(
                url("/api/v1/workspaces/\(workspace.id)/billing/preflight"),
                headers: headers
            )
        }

        let json = try response.validated(provider: id)
        let container = json["codingPlan"] ?? json
        let eligible = container["eligible"].bool ?? json["eligible"].bool ?? true
        let rawWindows = container.array("windows") ?? json.array("windows") ?? []

        let windows = rawWindows.compactMap(Self.window(from:))
        if windows.isEmpty {
            if !eligible { throw ProviderError.noSubscription }
            throw ProviderError.malformed("缺少 windows 数组")
        }
        if usedPreflight {
            note = "额度经由 preflight 回退获取"
        }

        let tier = container["tier"].string ?? json["tier"].string
        let planName = tier.map(Self.displayTier)

        // 钱包与账号身份独立读取；失败不影响额度展示。
        async let walletTask = try? transport.get(
            url("/api/v1/workspaces/\(workspace.id)/wallet/balance"),
            headers: headers
        )
        async let meTask = try? transport.get(url("/api/v1/me"), headers: headers)
        let (wallet, me) = await (walletTask, meTask)

        var balance: String?
        if let wallet, (200...299).contains(wallet.status), let json = try? JSON(data: wallet.data) {
            let candidate = json["balanceUsd"] ?? json["balance"] ?? json["amount"] ?? json["data"]?["balanceUsd"]
            if let value = candidate?.double {
                balance = "钱包 \(UsageFormatting.usd(value))"
            } else if let text = candidate?.string, !text.isEmpty {
                balance = "钱包 \(text)"
            }
        }

        var accountLabel = workspace.name
        if let me, (200...299).contains(me.status), let json = try? JSON(data: me.data) {
            accountLabel = json["email"].string ?? json["name"].string ?? accountLabel
        }

        return ProviderUsage(
            provider: id,
            planName: planName,
            accountLabel: accountLabel,
            windows: windows,
            balance: balance,
            note: note
        )
    }

    // MARK: - 工作区

    private struct Workspace {
        let id: String
        let name: String?
    }

    private func resolveWorkspace(credential: ProviderCredential, headers: [String: String]) async throws -> Workspace {
        if let explicit = credential.workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return Workspace(id: explicit, name: nil)
        }

        let current = try await transport.get(url("/api/v1/workspaces/current"), headers: headers)
        if (200...299).contains(current.status), let json = try? JSON(data: current.data) {
            let id = json["workspaceId"].string
                ?? json["id"].string
                ?? json["data"]?["workspaceId"].string
                ?? json["data"]?["id"].string
            if let id, !id.isEmpty {
                let name = json["workspaceName"].string
                    ?? json["name"].string
                    ?? json["displayName"].string
                    ?? json["data"]?["name"].string
                return Workspace(id: id, name: name)
            }
        }

        let list = try await transport.get(url("/api/v1/workspaces"), headers: headers)
        let json = try list.validated(provider: id)
        let items = json.array("items") ?? json["data"]?.array("items") ?? []
        guard let first = items.first,
              let id = first["workspaceId"].string ?? first["id"].string,
              !id.isEmpty else {
            throw ProviderError.malformed("找不到工作区，请在设置里手动填写 workspace ID")
        }
        return Workspace(id: id, name: first["name"].string)
    }

    // MARK: - 响应解析

    private static func window(from entry: JSON) -> UsageWindow? {
        let duration = entry["durationSeconds"].double
            ?? entry["duration_seconds"].double
            ?? entry["windowSeconds"].double

        let kind: UsageWindow.Kind
        let label: String
        if duration == 18_000 {
            kind = .session; label = "5 小时"
        } else if duration == 604_800 {
            kind = .weekly; label = "7 天"
        } else if duration == 86_400 {
            kind = .daily; label = "每日"
        } else if let duration, (2_419_200.0...2_678_400.0).contains(duration) {
            kind = .monthly; label = "每月"
        } else {
            kind = .other
            if let duration, duration > 0 {
                label = "\(Int((duration / 3600).rounded())) 小时"
            } else {
                label = "额度窗口"
            }
        }

        let used = entry["usedCredits"].double ?? entry["used_credits"].double
        let limit = entry["limitCredits"].double ?? entry["limit_credits"].double
        let remaining = entry["remainingCredits"].double ?? entry["remaining_credits"].double
        let resolvedUsed = used ?? (limit.flatMap { limit in remaining.map { limit - $0 } })
        let resets = entry["resetsAt"].isoDate
            ?? entry["resets_at"].isoDate
            ?? entry["resetAt"].date

        guard let resolvedUsed, let limit, limit > 0 else { return nil }
        return UsageWindow(
            kind: kind,
            id: duration.map { "od-\(Int($0))" } ?? "od-unknown",
            label: label,
            usedPercent: resolvedUsed / limit * 100,
            resetsAt: resets,
            detail: nil
        )
    }

    public static func displayTier(_ tier: String) -> String {
        switch tier.lowercased() {
        case "go": return "Go"
        case "go-plus": return "Go Plus"
        case "go-pro", "pro": return "Pro"
        case "go-max", "max": return "Max"
        default:
            return tier.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }
    }

    // MARK: - 请求工具

    private func url(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL) ?? baseURL.appendingPathComponent(path)
    }

    private func authHeaders(_ credential: ProviderCredential) -> [String: String] {
        if let cookie = credential.cookie?.trimmingCharacters(in: .whitespacesAndNewlines), !cookie.isEmpty {
            let value = cookie.hasPrefix("Cookie:") ? String(cookie.dropFirst("Cookie:".count)).trimmingCharacters(in: .whitespaces) : cookie
            // 控制台自己请求 amr-api 时会带这两个头，部分账号会校验。
            return [
                "Cookie": value,
                "Origin": "https://open-design.ai",
                "Referer": "https://open-design.ai/cloud/dashboard"
            ]
        }
        return ["Authorization": "Bearer \(credential.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))"]
    }
}
