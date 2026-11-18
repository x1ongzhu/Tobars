import Foundation

/// 落盘缓存：启动时先显示上次结果，再异步刷新。缓存只包含用量与时间，不含凭据。
public actor UsageCache {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.fileURL = support
                .appendingPathComponent("Tobars", isDirectory: true)
                .appendingPathComponent("usage-cache.json")
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public struct Snapshot: Codable, Sendable {
        public var usage: [UUID: ProviderUsage]
        public var updatedAt: Date

        public init(usage: [UUID: ProviderUsage] = [:], updatedAt: Date = Date()) {
            self.usage = usage
            self.updatedAt = updatedAt
        }
    }

    public func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(Snapshot.self, from: data)
    }

    public func save(_ snapshot: Snapshot) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 缓存失败不影响主流程（菜单仍会显示本次内存结果）。
            NSLog("Tobars: 缓存写入失败 \(error.localizedDescription)")
        }
    }

    public var location: URL { fileURL }
}
