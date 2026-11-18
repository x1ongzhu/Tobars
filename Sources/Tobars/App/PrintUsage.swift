import Foundation
import TobarsCore

/// 无 UI 的调试入口，方便 agent / 脚本核对真实数据：
///   .build/debug/Tobars --print-usage
///   .build/debug/Tobars --print-usage --demo
enum PrintUsage {
    private struct Dump: Encodable {
        let provider: String
        let label: String
        let plan: String?
        let account: String?
        let windows: [Window]
        let balance: String?
        let note: String?
        let error: String?
    }

    private struct Window: Encodable {
        let kind: String
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
        let detail: String?
    }

    static func run(demo: Bool) {
        Task {
            let dumps = demo ? demos() : await live()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(dumps), let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            exit(0)
        }
        RunLoop.main.run()
    }

    private static func demos() -> [Dump] {
        let usage = DemoData.usage()
        return DemoData.accounts.map { account in
            guard let value = usage[account.id] else {
                return Dump(
                    provider: account.provider.rawValue,
                    label: account.displayName,
                    plan: nil, account: nil, windows: [], balance: nil, note: nil,
                    error: "缺少演示数据"
                )
            }
            return dump(account: account, usage: value)
        }
    }

    private static func live() async -> [Dump] {
        let accounts = AccountBootstrap.loadAccounts()
        guard !accounts.isEmpty else { return [] }

        let store = CredentialStore()
        let providers = ProviderRegistry.all()

        let results = await withTaskGroup(of: (UUID, Result<ProviderUsage, Error>).self) { group in
            for account in accounts {
                group.addTask {
                    guard let credential = store.load(accountID: account.id), !credential.isEmpty else {
                        return (account.id, .failure(ProviderError.missingCredential))
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
            var collected: [(UUID, Result<ProviderUsage, Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.0, $0.1) })

        return accounts.map { account in
            switch byID[account.id] {
            case .success(let usage):
                return dump(account: account, usage: usage)
            case .failure(let error):
                return Dump(
                    provider: account.provider.rawValue,
                    label: account.displayName,
                    plan: nil, account: nil, windows: [], balance: nil, note: nil,
                    error: error.localizedDescription
                )
            case nil:
                return Dump(
                    provider: account.provider.rawValue,
                    label: account.displayName,
                    plan: nil, account: nil, windows: [], balance: nil, note: nil,
                    error: "没有返回结果"
                )
            }
        }
    }

    private static func dump(account: Account, usage: ProviderUsage) -> Dump {
        Dump(
            provider: account.provider.rawValue,
            label: account.displayName,
            plan: usage.planName,
            account: usage.accountLabel,
            windows: usage.windows.map {
                Window(
                    kind: $0.kind.rawValue,
                    label: $0.label,
                    usedPercent: $0.usedPercent,
                    resetsAt: $0.resetsAt,
                    detail: $0.detail
                )
            },
            balance: usage.balance,
            note: usage.note,
            error: nil
        )
    }
}

/// 一次性把旧 Keychain 凭据迁到 0600 文件：
///   .build/debug/Tobars --migrate-credentials
enum CredentialMigration {
    static func run() {
        let accounts = AccountBootstrap.loadAccounts()
        guard !accounts.isEmpty else {
            print("没有账号需要迁移")
            exit(0)
        }
        let result = CredentialStore().migrateFromKeychain(accountIDs: accounts.map(\.id))
        print("migrated=\(result.migrated) failed=\(result.failed)")
        exit(0)
    }
}
