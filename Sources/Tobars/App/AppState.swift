import Foundation
import SwiftUI
import TobarsCore

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// 账号列表是唯一的数据源；同一服务商可以出现多次。
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var usage: [UUID: ProviderUsage] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var configured: Set<UUID> = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published var settingsError: String?

    private let credentials = CredentialStore()
    private let accountStore = AccountStore()
    private let cache = UsageCache()
    private let providers: [any UsageProviding]
    private var timer: Timer?
    /// 运行期内存缓存，避免设置页每次重绘都读凭据文件。
    private var credentialCache: [UUID: ProviderCredential] = [:]
    /// 仅 `--render-snapshot` 使用：让设置页在无凭据数据时也能渲染已配置状态。
    private var previewCredentials: [UUID: ProviderCredential] = [:]

    init(providers: [any UsageProviding]? = nil) {
        self.providers = providers ?? ProviderRegistry.all()
    }

    // MARK: - 生命周期

    func start() async {
        accounts = AccountBootstrap.loadAccounts()

        // 一次性把旧 Keychain 条目搬到 0600 文件；之后运行期不再访问 Keychain。
        if !accounts.isEmpty {
            let result = credentials.migrateFromKeychain(accountIDs: accounts.map(\.id))
            if result.migrated > 0 {
                NSLog("Tobars: 已从钥匙串迁移 \(result.migrated) 个账号的凭据")
            }
        }

        reloadCredentialCache()
        configured = Set(
            accounts
                .filter { credentialCache[$0.id]?.isEmpty == false }
                .map(\.id)
        )

        if let snapshot = await cache.load() {
            // 先展示缓存；已删除账号的缓存直接丢弃。
            let ids = Set(accounts.map(\.id))
            usage = snapshot.usage.filter { ids.contains($0.key) }
            lastRefresh = snapshot.updatedAt
        }

        await refresh()
        scheduleTimer()
    }

    private func reloadCredentialCache() {
        credentialCache = [:]
        for account in accounts {
            if let credential = credentials.load(accountID: account.id), !credential.isEmpty {
                credentialCache[account.id] = credential
            }
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - 账号管理

    @discardableResult
    func addAccount(provider: ProviderID) -> Account {
        let account = Account(provider: provider, label: nextLabel(for: provider))
        accounts.append(account)
        accountStore.save(accounts)
        return account
    }

    func rename(_ accountID: UUID, to label: String) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].label = trimmed.isEmpty ? accounts[index].provider.displayName : trimmed
        accountStore.save(accounts)
    }

    func removeAccount(_ accountID: UUID) {
        credentials.delete(accountID: accountID)
        accounts.removeAll { $0.id == accountID }
        usage[accountID] = nil
        errors[accountID] = nil
        credentialCache[accountID] = nil
        configured.remove(accountID)
        accountStore.save(accounts)
        Task { await persistCache() }
    }

    private func nextLabel(for provider: ProviderID) -> String {
        let count = accounts.filter { $0.provider == provider }.count
        return count == 0 ? provider.displayName : "\(provider.displayName) \(count + 1)"
    }

    // MARK: - 刷新

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // 在主线程取好凭据，子任务里不再触碰存储。
        let snapshot = accounts.map { ($0, credential(for: $0)) }
        let providers = self.providers

        let results = await withTaskGroup(of: (UUID, Result<ProviderUsage, Error>?).self) { group in
            for (account, credential) in snapshot {
                group.addTask {
                    guard let credential, !credential.isEmpty else {
                        return (account.id, nil)
                    }
                    let provider = providers.first { $0.id == account.provider }
                        ?? ProviderRegistry.provider(for: account.provider)
                    do {
                        return (account.id, .success(try await provider.fetchUsage(credential: credential)))
                    } catch {
                        return (account.id, .failure(error))
                    }
                }
            }
            var collected: [(UUID, Result<ProviderUsage, Error>?)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var nextUsage = usage
        var nextErrors: [UUID: String] = [:]
        var nextConfigured = configured

        for (id, result) in results {
            guard let result else {
                // 账号刚添加、还没填凭据：不显示，也不报错。
                nextUsage[id] = nil
                nextConfigured.remove(id)
                continue
            }
            switch result {
            case .success(let value):
                nextUsage[id] = value
                nextConfigured.insert(id)
            case .failure(let error):
                if case ProviderError.missingCredential = error {
                    nextConfigured.remove(id)
                    nextUsage[id] = nil
                } else {
                    nextConfigured.insert(id)
                    nextErrors[id] = error.localizedDescription
                    // 有旧数据时保留，但把失败原因写进 note，避免静默展示过期数字。
                    if let stale = nextUsage[id] {
                        nextUsage[id] = ProviderUsage(
                            provider: stale.provider,
                            planName: stale.planName,
                            accountLabel: stale.accountLabel,
                            windows: stale.windows,
                            balance: stale.balance,
                            note: "刷新失败：\(error.localizedDescription)",
                            fetchedAt: stale.fetchedAt
                        )
                    }
                }
            }
        }

        usage = nextUsage
        errors = nextErrors
        configured = nextConfigured
        lastRefresh = Date()
        await persistCache()
    }

    /// 设置页「保存并连接」：先用草稿凭据验证，成功后才写入 Keychain。
    func test(_ credential: ProviderCredential, for account: Account) async throws {
        guard !credential.isEmpty else { throw ProviderError.missingCredential }
        let provider = providers.first { $0.id == account.provider }
            ?? ProviderRegistry.provider(for: account.provider)
        let value = try await provider.fetchUsage(credential: credential)
        usage[account.id] = value
        errors[account.id] = nil
        configured.insert(account.id)
        lastRefresh = Date()
        await persistCache()
    }

    /// 设置页「测试连接」：用已保存的凭据重新拉取单个账号。
    func refresh(_ accountID: UUID) async throws {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            throw ProviderError.malformed("账号不存在")
        }
        guard let credential = credential(for: account), !credential.isEmpty else {
            throw ProviderError.missingCredential
        }
        let provider = providers.first { $0.id == account.provider }
            ?? ProviderRegistry.provider(for: account.provider)
        let value = try await provider.fetchUsage(credential: credential)
        usage[accountID] = value
        errors[accountID] = nil
        configured.insert(accountID)
        lastRefresh = Date()
        await persistCache()
    }

    private func persistCache() async {
        let cacheable = usage.filter { errors[$0.key] == nil }
        await cache.save(.init(usage: cacheable, updatedAt: Date()))
    }

    // MARK: - 凭据

    func credential(for account: Account) -> ProviderCredential? {
        if let preview = previewCredentials[account.id] { return preview }
        if let cached = credentialCache[account.id] { return cached }
        if let loaded = credentials.load(accountID: account.id), !loaded.isEmpty {
            credentialCache[account.id] = loaded
            return loaded
        }
        return nil
    }

    func applyPreviewData(
        accounts: [Account],
        usage: [UUID: ProviderUsage],
        credentials: [UUID: ProviderCredential]
    ) {
        self.accounts = accounts
        self.usage = usage
        self.previewCredentials = credentials
        self.configured = Set(credentials.keys)
        self.lastRefresh = Date().addingTimeInterval(-45)
    }

    func save(_ credential: ProviderCredential, for account: Account) throws {
        try credentials.save(credential, accountID: account.id)
        if credential.isEmpty {
            credentialCache[account.id] = nil
            configured.remove(account.id)
            usage[account.id] = nil
        } else {
            credentialCache[account.id] = credential
            configured.insert(account.id)
        }
    }

    func importLocalKey(for provider: ProviderID) -> String? {
        LocalCredentialImporter.key(for: provider)
    }

    func hasLocalKey(for provider: ProviderID) -> Bool {
        LocalCredentialImporter.key(for: provider) != nil
    }

    // MARK: - 菜单栏

    var menuBarText: String {
        let values = usage.values.compactMap(\.peakPercent)
        guard let peak = values.max() else {
            return isRefreshing ? "…" : "—"
        }
        return UsageFormatting.percent(peak)
    }
}
