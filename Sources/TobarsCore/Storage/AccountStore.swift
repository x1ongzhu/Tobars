import Foundation

/// 账号元数据落盘。只存 UUID / 服务商 / 显示名，绝不含密钥。
public struct AccountStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.fileURL = support
                .appendingPathComponent("Tobars", isDirectory: true)
                .appendingPathComponent("accounts.json")
        }
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func load() -> [Account] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Account].self, from: data)) ?? []
    }

    public func save(_ accounts: [Account]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(accounts).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Tobars: 账号列表写入失败 \(error.localizedDescription)")
        }
    }
}
