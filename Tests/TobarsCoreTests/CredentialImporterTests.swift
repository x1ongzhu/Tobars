import XCTest
@testable import TobarsCore

final class CredentialImporterTests: XCTestCase {
    func testReadsOpenDesignControlKeyFromVelaConfig() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("tobars-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let amr = home.appendingPathComponent(".amr", isDirectory: true)
        try FileManager.default.createDirectory(at: amr, withIntermediateDirectories: true)
        try Data("""
        { "profiles": { "prod": { "controlKey": "vela_ctrl_test", "runtimeKey": "sk-amr-test" } } }
        """.utf8).write(to: amr.appendingPathComponent("config.json"))

        XCTAssertEqual(LocalCredentialImporter.openDesignControlKey(home: home), "vela_ctrl_test")
    }

    func testMissingFilesReturnNil() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("tobars-home-empty-\(UUID().uuidString)", isDirectory: true)
        XCTAssertNil(LocalCredentialImporter.openDesignControlKey(home: home))
        XCTAssertNil(LocalCredentialImporter.commandCodeKey(home: home))
        XCTAssertNil(LocalCredentialImporter.openCodeGoKey(home: home))
    }

    func testCredentialFileRoundTripAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tobars-credentials-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CredentialStore(fileURL: file)
        let id = UUID()
        let credential = ProviderCredential(apiKey: "test-key", workspaceID: "ws_1")
        try store.save(credential, accountID: id)

        XCTAssertEqual(store.load(accountID: id), credential)
        XCTAssertEqual(store.load(accountID: UUID()), nil)

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        store.delete(accountID: id)
        XCTAssertNil(store.load(accountID: id))
    }
}
