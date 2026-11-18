import XCTest
import TobarsCore

final class UsageWindowTests: XCTestCase {
    func testPercentIsClamped() {
        XCTAssertEqual(UsageWindow(kind: .session, id: "a", label: "a", usedPercent: 140).usedPercent, 100)
        XCTAssertEqual(UsageWindow(kind: .session, id: "a", label: "a", usedPercent: -5).usedPercent, 0)
    }

    func testFailableInitRejectsNonPositiveLimit() {
        XCTAssertNil(UsageWindow(kind: .session, id: "a", label: "a", used: 5, limit: 0, resetsAt: nil))
        XCTAssertNil(UsageWindow(kind: .session, id: "a", label: "a", used: nil, limit: 10, resetsAt: nil))
        let window = UsageWindow(kind: .weekly, id: "w", label: "周", used: 3, limit: 12, resetsAt: nil)
        XCTAssertEqual(window?.usedPercent, 25)
        XCTAssertEqual(window?.detail, "$3 / $12")
    }

    func testJSONAcceptsEpochSecondsMillisecondsAndISO() {
        XCTAssertEqual(JSON(raw: 1_763_500_000).date?.timeIntervalSince1970, 1_763_500_000)
        XCTAssertEqual(JSON(raw: 1_763_500_000_000).date?.timeIntervalSince1970, 1_763_500_000)
        XCTAssertNotNil(JSON(raw: "2026-11-18T21:00:00.000Z").isoDate)
        XCTAssertNotNil(JSON(raw: "2026-11-18T21:00:00Z").isoDate)
    }

    func testCountdownFormatting() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(3 * 3600 + 12 * 60), now: now), "3h 12m")
        XCTAssertEqual(UsageFormatting.countdown(to: now.addingTimeInterval(2 * 86400 + 4 * 3600), now: now), "2d 4h")
        XCTAssertNil(UsageFormatting.countdown(to: now.addingTimeInterval(-1), now: now))
    }
}

final class UsageCacheTests: XCTestCase {
    func testRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tobars-tests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("cache.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = UsageCache(fileURL: file)
        let accountID = UUID()
        let usage = ProviderUsage(
            provider: .commandCode,
            planName: "GOAT",
            windows: [
                UsageWindow(kind: .session, id: "fiveHour", label: "5 小时", usedPercent: 42, resetsAt: Date(timeIntervalSince1970: 1_763_500_000))
            ],
            balance: "额外额度 $3.20",
            fetchedAt: Date(timeIntervalSince1970: 1_763_400_000)
        )
        await cache.save(.init(usage: [accountID: usage], updatedAt: Date(timeIntervalSince1970: 1_763_400_100)))

        let loaded = await cache.load()
        XCTAssertEqual(loaded?.usage[accountID]?.planName, "GOAT")
        XCTAssertEqual(loaded?.usage[accountID]?.windows.first?.usedPercent, 42)
        XCTAssertEqual(loaded?.usage[accountID]?.balance, "额外额度 $3.20")
        XCTAssertEqual(loaded?.updatedAt.timeIntervalSince1970, 1_763_400_100)
    }

    func testMissingFileReturnsNil() async {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("tobars-missing-\(UUID().uuidString).json")
        let loaded = await UsageCache(fileURL: file).load()
        XCTAssertNil(loaded)
    }
}

final class AccountStoreTests: XCTestCase {
    func testRoundTripKeepsMetadataOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tobars-accounts-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("accounts.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AccountStore(fileURL: file)
        let accounts = [
            Account(provider: .openCodeGo, label: "个人"),
            Account(provider: .openCodeGo, label: "团队"),
            Account(provider: .commandCode, label: "工作")
        ]
        store.save(accounts)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map(\.id), accounts.map(\.id))
        XCTAssertEqual(loaded.map(\.label), ["个人", "团队", "工作"])
        XCTAssertEqual(loaded.filter { $0.provider == .openCodeGo }.count, 2)
        XCTAssertFalse(try String(contentsOf: file).contains("apiKey"))
    }

    func testDisplayNameFallsBackToProvider() {
        XCTAssertEqual(Account(provider: .openDesign, label: "  ").displayName, "Open Design")
        XCTAssertEqual(Account(provider: .openDesign, label: "设计组").displayName, "设计组")
    }
}
