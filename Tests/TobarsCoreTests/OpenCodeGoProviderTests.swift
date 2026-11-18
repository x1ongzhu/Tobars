import XCTest
import TobarsCore

final class OpenCodeGoProviderTests: XCTestCase {
    func testParsesThreeWindows() async throws {
        let recorder = RequestRecorder()
        let transport = MockTransport { url, headers in
            recorder.record(url, headers)
            return .json("""
            {
              "usage": {
                "rolling": { "status": "ok", "percent": 4,  "resetsAt": "2026-08-13T16:27:38.287Z" },
                "weekly":  { "status": "ok", "percent": 3,  "resetsAt": "2026-08-17T00:00:00.000Z" },
                "monthly": { "status": "limited", "percent": 100, "resetsAt": "2026-09-13T06:06:01.287Z" }
              }
            }
            """)
        }

        let provider = OpenCodeGoProvider(transport: transport)
        let usage = try await provider.fetchUsage(credential: .init(apiKey: "test-key"))

        XCTAssertEqual(usage.windows.count, 3)
        XCTAssertEqual(usage.windows[0].label, "5 小时")
        XCTAssertEqual(usage.windows[0].usedPercent, 4)
        XCTAssertEqual(usage.windows[1].usedPercent, 3)
        XCTAssertEqual(usage.windows[2].usedPercent, 100)
        XCTAssertEqual(usage.windows[2].detail, "limited")
        XCTAssertNotNil(usage.windows[0].resetsAt)
        XCTAssertEqual(usage.peakPercent, 100)

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.0.absoluteString, "https://opencode.ai/zen/go/v1/usage")
        XCTAssertEqual(request.1["Authorization"], "Bearer test-key")
    }

    func testAcceptsNumericPercentAndSnakeCaseReset() async throws {
        let transport = MockTransport { _, _ in
            .json("""
            { "usage": { "rolling": { "percent": "12.5", "resets_at": "2026-08-13T16:27:38Z" } } }
            """)
        }
        let usage = try await OpenCodeGoProvider(transport: transport)
            .fetchUsage(credential: .init(apiKey: "k"))
        XCTAssertEqual(usage.windows.count, 1)
        XCTAssertEqual(usage.windows[0].usedPercent, 12.5, accuracy: 0.001)
        XCTAssertNotNil(usage.windows[0].resetsAt)
    }

    func testMissingCredentialFailsBeforeNetwork() async {
        let transport = MockTransport { _, _ in
            XCTFail("不应发起请求")
            return .json("{}")
        }
        do {
            _ = try await OpenCodeGoProvider(transport: transport)
                .fetchUsage(credential: .init(apiKey: "  "))
            XCTFail("应当抛错")
        } catch {
            XCTAssertEqual(error as? ProviderError, .missingCredential)
        }
    }

    func testUnauthorizedMapsToProviderError() async {
        let transport = MockTransport { _, _ in .json(#"{"type":"error"}"#, status: 401) }
        do {
            _ = try await OpenCodeGoProvider(transport: transport)
                .fetchUsage(credential: .init(apiKey: "bad"))
            XCTFail("应当抛错")
        } catch {
            XCTAssertEqual(error as? ProviderError, .unauthorized)
        }
    }
}
