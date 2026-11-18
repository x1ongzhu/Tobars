import XCTest
import TobarsCore

final class OpenDesignProviderTests: XCTestCase {
    private let windowsBody = """
    {
      "eligible": true,
      "tier": "go",
      "windows": [
        { "durationSeconds": 18000,   "usedCredits": "16000", "limitCredits": "50000", "resetsAt": "2026-11-18T21:00:00.000Z" },
        { "durationSeconds": 604800,  "usedCredits": "78000", "limitCredits": "150000", "resetsAt": "2026-11-24T09:00:00.000Z" }
      ]
    }
    """

    func testParsesControlPlaneAndWallet() async throws {
        let recorder = RequestRecorder()
        let transport = MockTransport { url, headers in
            recorder.record(url, headers)
            switch url.path {
            case "/api/v1/workspaces/current":
                return .json(#"{ "workspaceId": "ws_1", "name": "Design Team", "tier": "go" }"#)
            case "/api/v1/workspaces/ws_1/billing/coding-plan-usage":
                return .json(self.windowsBody)
            case "/api/v1/workspaces/ws_1/wallet/balance":
                return .json(#"{ "balanceUsd": 12.5 }"#)
            case "/api/v1/me":
                return .json(#"{ "email": "designer@example.com", "name": "Designer" }"#)
            default:
                return .json("{}", status: 404)
            }
        }

        let usage = try await OpenDesignProvider(transport: transport)
            .fetchUsage(credential: .init(apiKey: "vela_ctrl_abc"))

        XCTAssertEqual(usage.planName, "Go")
        XCTAssertEqual(usage.accountLabel, "designer@example.com")
        XCTAssertEqual(usage.windows.count, 2)
        XCTAssertEqual(usage.windows[0].label, "5 小时")
        XCTAssertEqual(usage.windows[0].usedPercent, 32, accuracy: 0.001)
        XCTAssertEqual(usage.windows[1].label, "7 天")
        XCTAssertEqual(usage.windows[1].usedPercent, 52, accuracy: 0.001)
        XCTAssertEqual(usage.balance, "钱包 $12.50")

        let usageRequest = try XCTUnwrap(
            recorder.requests.first { $0.0.path.hasSuffix("coding-plan-usage") }
        )
        XCTAssertEqual(usageRequest.1["Authorization"], "Bearer vela_ctrl_abc")
        XCTAssertEqual(usageRequest.1["X-Vela-Workspace-Id"], "ws_1")
    }

    func testExplicitWorkspaceSkipsDiscovery() async throws {
        let recorder = RequestRecorder()
        let transport = MockTransport { url, _ in
            recorder.record(url, [:])
            switch url.path {
            case "/api/v1/workspaces/ws_explicit/billing/coding-plan-usage":
                return .json(self.windowsBody)
            default:
                return .json("{}", status: 404)
            }
        }

        _ = try await OpenDesignProvider(transport: transport)
            .fetchUsage(credential: .init(apiKey: "k", workspaceID: "ws_explicit"))

        XCTAssertFalse(recorder.requests.contains { $0.0.path.hasSuffix("workspaces/current") })
    }

    func testFallsBackToPreflightWhenBearerRejected() async throws {
        let transport = MockTransport { url, _ in
            if url.path.hasSuffix("coding-plan-usage") {
                return .json(#"{"error":"workspace_billing_scope_forbidden"}"#, status: 403)
            }
            if url.path.hasSuffix("billing/preflight") {
                return .json("""
                {
                  "codingPlan": {
                    "eligible": true,
                    "tier": "go-plus",
                    "windows": [
                      { "durationSeconds": 604800, "usedCredits": 30000, "limitCredits": 40000, "resetsAt": "2026-11-24T09:00:00Z" }
                    ]
                  },
                  "balanceUsd": "0.00"
                }
                """)
            }
            return .json("{}", status: 404)
        }

        let usage = try await OpenDesignProvider(transport: transport)
            .fetchUsage(credential: .init(apiKey: "k", workspaceID: "ws"))
        XCTAssertEqual(usage.planName, "Go Plus")
        XCTAssertEqual(usage.windows.count, 1)
        XCTAssertEqual(usage.windows[0].usedPercent, 75, accuracy: 0.001)
        XCTAssertEqual(usage.note, "额度经由 preflight 回退获取")
    }

    func testIneligibleSubscriptionThrows() async {
        let transport = MockTransport { url, _ in
            if url.path.hasSuffix("workspaces/current") {
                return .json(#"{ "workspaceId": "ws" }"#)
            }
            return .json(#"{ "eligible": false, "tier": "free", "windows": [] }"#)
        }
        do {
            _ = try await OpenDesignProvider(transport: transport)
                .fetchUsage(credential: .init(apiKey: "k"))
            XCTFail("应当抛错")
        } catch {
            XCTAssertEqual(error as? ProviderError, .noSubscription)
        }
    }

    func testCookieCredentialSendsNoBearer() async throws {
        let recorder = RequestRecorder()
        let transport = MockTransport { url, headers in
            recorder.record(url, headers)
            if url.path.hasSuffix("workspaces/current") {
                return .json(#"{ "workspaceId": "ws" }"#)
            }
            if url.path.hasSuffix("coding-plan-usage") {
                return .json(self.windowsBody)
            }
            return .json("{}", status: 404)
        }

        _ = try await OpenDesignProvider(transport: transport)
            .fetchUsage(credential: .init(cookie: "__Secure-better-auth.session_token=abc"))

        let request = try XCTUnwrap(recorder.requests.first { $0.0.path.hasSuffix("coding-plan-usage") })
        XCTAssertEqual(request.1["Cookie"], "__Secure-better-auth.session_token=abc")
        XCTAssertNil(request.1["Authorization"])
    }
}
