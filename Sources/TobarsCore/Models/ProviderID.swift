import Foundation

/// 已支持的用量服务商。新增服务商时同时更新 `ProviderRegistry` 与设置界面。
public enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case openCodeGo = "opencode-go"
    case commandCode = "command-code"
    case openDesign = "open-design"

    public var id: String { rawValue }

    /// 菜单与设置里显示的名字。刻意保留官方英文名，方便与账单页面核对。
    public var displayName: String {
        switch self {
        case .openCodeGo: return "OpenCode Go"
        case .commandCode: return "Command Code"
        case .openDesign: return "Open Design"
        }
    }

    public var shortName: String {
        switch self {
        case .openCodeGo: return "Go"
        case .commandCode: return "CMD"
        case .openDesign: return "OD"
        }
    }

    public var consoleURL: URL {
        switch self {
        case .openCodeGo: return URL(string: "https://opencode.ai/console/go")!
        case .commandCode: return URL(string: "https://commandcode.ai/usage")!
        case .openDesign: return URL(string: "https://open-design.ai/cloud/dashboard")!
        }
    }
}
