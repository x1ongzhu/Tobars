import Foundation

/// OpenCode Go 的官方额度接口（2026-08 起可用，未出现在公开 API 文档首页）：
///   GET https://opencode.ai/zen/go/v1/usage
///   Authorization: Bearer <普通 API key>
/// 返回 rolling / weekly / monthly 三个百分比窗口。
/// 响应头与字段曾在上线一小时内改版，因此这里对每个窗口独立容错。
public struct OpenCodeGoProvider: UsageProviding {
    public let id: ProviderID = .openCodeGo
    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchUsage(credential: ProviderCredential) async throws -> ProviderUsage {
        let key = credential.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ProviderError.missingCredential }

        let url = URL(string: "https://opencode.ai/zen/go/v1/usage")!
        let response = try await transport.get(url, headers: ["Authorization": "Bearer \(key)"])
        let json = try response.validated(provider: id)

        guard let usage = json["usage"] ?? json["data"] else {
            throw ProviderError.malformed("缺少 usage 字段")
        }

        let definitions: [(String, String, UsageWindow.Kind)] = [
            ("rolling", "5 小时", .session),
            ("weekly", "每周", .weekly),
            ("monthly", "每月", .monthly)
        ]

        let windows: [UsageWindow] = definitions.compactMap { key, label, kind in
            guard let entry = usage[key] else { return nil }
            guard let percent = entry["percent"].double else { return nil }
            let reset = entry["resetsAt"].isoDate ?? entry["resets_at"].isoDate
            var detail: String?
            if let status = entry["status"].string, status.lowercased() != "ok" {
                detail = status
            }
            return UsageWindow(
                kind: kind,
                id: key,
                label: label,
                usedPercent: percent,
                resetsAt: reset,
                detail: detail
            )
        }

        guard !windows.isEmpty else {
            throw ProviderError.malformed("未找到 rolling/weekly/monthly 任一窗口")
        }

        return ProviderUsage(provider: id, windows: windows)
    }
}
