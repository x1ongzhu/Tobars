import XCTest
import TobarsCore

final class CommandCodeProviderTests: XCTestCase {
    private func transport(recorder: RequestRecorder? = nil) -> MockTransport {
        MockTransport { url, headers in
            recorder?.record(url, headers)
            switch url.path {
            case "/alpha/whoami":
                return .json("""
                { "org": { "id": "org_123", "login": "drew" }, "user": { "userName": "drew" } }
                """)
            case "/alpha/billing/credits":
                return .json("""
                {
                  "credits": {
                    "planId": "individual-goat",
                    "monthlyCredits": 20,
                    "purchasedCredits": 3,
                    "freeCredits": 0.2
                  },
                  "windowLimits": {
                    "limited": false,
                    "fiveHour": { "used": 12.6, "cap": 20, "resetAt": "2026-11-18T21:00:00.000Z" },
                    "weekly":   { "used": 17.0, "cap": 50, "resetAt": "2026-11-22T09:00:00.000Z" }
                  }
                }
                """)
            case "/alpha/billing/subscriptions":
                return .json("""
                {
                  "data": {
                    "planId": "individual-goat",
                    "status": "active",
                    "currentPeriodStart": "2026-11-06T00:00:00.000Z",
                    "currentPeriodEnd": "2026-12-06T00:00:00.000Z"
                  }
                }
                """)
            case "/alpha/usage/summary":
                return .json(#"{ "totalCost": 56.8 }"#)
            default:
                return .json(#"{"error":"not found"}"#, status: 404)
            }
        }
    }

    func testBuildsWindowsAndPassesOrgID() async throws {
        let recorder = RequestRecorder()
        let usage = try await CommandCodeProvider(transport: transport(recorder: recorder))
            .fetchUsage(credential: .init(apiKey: "cmd-key"))

        XCTAssertEqual(usage.provider, .commandCode)
        XCTAssertEqual(usage.planName, "GOAT")
        XCTAssertEqual(usage.accountLabel, "drew")
        XCTAssertEqual(usage.windows.count, 3)

        let session = try XCTUnwrap(usage.windows.first { $0.kind == .session })
        XCTAssertEqual(session.usedPercent, 63, accuracy: 0.001)
        XCTAssertEqual(session.detail, "$12.60 / $20")

        let weekly = try XCTUnwrap(usage.windows.first { $0.kind == .weekly })
        XCTAssertEqual(weekly.usedPercent, 34, accuracy: 0.001)

        // 56.8 spent + (20 + 3 + 0.2) remaining = 80 pool → 71%
        let monthly = try XCTUnwrap(usage.windows.first { $0.kind == .monthly })
        XCTAssertEqual(monthly.usedPercent, 71, accuracy: 0.001)

        XCTAssertEqual(usage.balance, "额外额度 $3.20")
        let credited = recorder.requests.filter { $0.0.path.contains("billing") || $0.0.path.contains("usage") }
        XCTAssertFalse(credited.isEmpty)
        for request in credited {
            XCTAssertEqual(request.0.query, "orgId=org_123")
            XCTAssertEqual(request.1["Authorization"], "Bearer cmd-key")
        }
    }

    func testPartialFailureStillShowsWindowLimits() async throws {
        let transport = MockTransport { url, _ in
            switch url.path {
            case "/alpha/whoami":
                return .json(#"{ "org": { "id": "o" } }"#)
            case "/alpha/billing/credits":
                return .json("""
                {
                  "credits": {},
                  "windowLimits": {
                    "limited": true,
                    "fiveHour": { "used": 20, "cap": 20, "resetAt": 1763500000 }
                  }
                }
                """)
            default:
                return .json("{}", status: 500)
            }
        }

        let usage = try await CommandCodeProvider(transport: transport)
            .fetchUsage(credential: .init(apiKey: "k"))
        XCTAssertEqual(usage.windows.count, 1)
        XCTAssertEqual(usage.windows[0].usedPercent, 100)
        XCTAssertEqual(usage.note, "已触发窗口限额")
        XCTAssertNotNil(usage.windows[0].resetsAt)
    }

    func testPlanDisplayNames() {
        XCTAssertEqual(CommandCodeProvider.displayPlan("individual-goat"), "GOAT")
        XCTAssertEqual(CommandCodeProvider.displayPlan("individual-go-v1"), "Go")
        XCTAssertEqual(CommandCodeProvider.displayPlan("teams-pro"), "Teams Pro")
    }
}
