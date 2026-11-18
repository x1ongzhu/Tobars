import Foundation

/// 从本机已登录的 CLI 读取现成凭据，省去让用户再复制一次 key。
/// 只读、只在用户点「导入」时调用；不修改这些文件。
public enum LocalCredentialImporter {
    public static func key(for id: ProviderID) -> String? {
        switch id {
        case .openCodeGo: return openCodeGoKey()
        case .commandCode: return commandCodeKey()
        case .openDesign: return openDesignControlKey()
        }
    }

    /// OpenCode 1.x 把登录信息写在 auth.json；2.x 改到 opencode.db（未支持）。
    /// 结构示例：{ "opencode-go": { "type": "api", "key": "..." } }
    static func openCodeGoKey(home: URL = homeDirectory) -> String? {
        let url = home
            .appendingPathComponent(".local/share/opencode/auth.json")
        guard let json = readJSON(url) else { return nil }
        let entry = json["opencode-go"] ?? json["opencode"]
        return entry?["key"].string
            ?? entry?["apiKey"].string
            ?? entry?["access"].string
    }

    /// OpenDesign 桌面版 / vela CLI 登录后把控制面 key 写在 ~/.amr/config.json。
    /// 网页 API Keys 页面生成的是 sk-amr-… 推理 key，读不了额度。
    static func openDesignControlKey(home: URL = homeDirectory) -> String? {
        let url = home.appendingPathComponent(".amr/config.json")
        guard let json = readJSON(url) else { return nil }
        return json["profiles"]?["prod"]?["controlKey"].string
            ?? json["profiles"]?["prod"]?["control_key"].string
    }

    static func commandCodeKey(home: URL = homeDirectory) -> String? {
        let url = home.appendingPathComponent(".commandcode/auth.json")
        guard let json = readJSON(url) else { return nil }
        return json["apiKey"].string ?? json["key"].string
    }

    static var homeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static func readJSON(_ url: URL) -> JSON? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSON(data: data)
    }
}
