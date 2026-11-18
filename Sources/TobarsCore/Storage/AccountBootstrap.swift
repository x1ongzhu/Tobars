import Foundation

/// 账号列表的加载入口。账号元数据与凭据分开存在
/// `accounts.json` / `credentials.json`，都不含对 Keychain 的运行时依赖。
public enum AccountBootstrap {
    public static func loadAccounts(store: AccountStore = AccountStore()) -> [Account] {
        store.exists ? store.load() : []
    }
}
