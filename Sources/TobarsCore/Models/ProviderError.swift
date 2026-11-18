import Foundation

public enum ProviderError: LocalizedError, Sendable, Equatable {
    case missingCredential
    case unauthorized
    case forbidden(String?)
    case http(status: Int, body: String?)
    case malformed(String)
    case noSubscription
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "未配置 API key"
        case .unauthorized:
            return "凭据被拒绝（401），请在设置中更新"
        case .forbidden(let reason):
            return reason.map { "无权访问（403）：\($0)" } ?? "无权访问（403）"
        case .http(let status, let body):
            if let body, !body.isEmpty {
                return "服务返回 HTTP \(status)：\(body.prefix(180))"
            }
            return "服务返回 HTTP \(status)"
        case .malformed(let reason):
            return "无法解析响应：\(reason)"
        case .noSubscription:
            return "该账号当前没有生效的订阅"
        case .network(let reason):
            return "网络错误：\(reason)"
        }
    }
}
