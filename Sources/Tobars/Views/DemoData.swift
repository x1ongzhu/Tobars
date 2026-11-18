import Foundation
import TobarsCore

enum DemoData {
    static let accounts: [Account] = [
        Account(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            provider: .openCodeGo,
            label: "个人"
        ),
        Account(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111112")!,
            provider: .openCodeGo,
            label: "团队"
        ),
        Account(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            provider: .commandCode,
            label: "工作"
        ),
        Account(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            provider: .openDesign,
            label: "设计团队"
        )
    ]

    static func usage() -> [UUID: ProviderUsage] {
        let now = Date()
        return [
            accounts[0].id: ProviderUsage(
                provider: .openCodeGo,
                windows: [
                    UsageWindow(
                        kind: .session,
                        id: "rolling",
                        label: "5 小时",
                        usedPercent: 42,
                        resetsAt: now.addingTimeInterval(3 * 3600 + 12 * 60)
                    ),
                    UsageWindow(
                        kind: .weekly,
                        id: "weekly",
                        label: "每周",
                        usedPercent: 28,
                        resetsAt: now.addingTimeInterval(2 * 86400 + 4 * 3600)
                    ),
                    UsageWindow(
                        kind: .monthly,
                        id: "monthly",
                        label: "每月",
                        usedPercent: 11,
                        resetsAt: now.addingTimeInterval(18 * 86400)
                    )
                ]
            ),
            accounts[1].id: ProviderUsage(
                provider: .openCodeGo,
                accountLabel: "team@example.com",
                windows: [
                    UsageWindow(
                        kind: .session,
                        id: "rolling",
                        label: "5 小时",
                        usedPercent: 15,
                        resetsAt: now.addingTimeInterval(4 * 3600 + 20 * 60)
                    ),
                    UsageWindow(
                        kind: .weekly,
                        id: "weekly",
                        label: "每周",
                        usedPercent: 9,
                        resetsAt: now.addingTimeInterval(6 * 86400)
                    ),
                    UsageWindow(
                        kind: .monthly,
                        id: "monthly",
                        label: "每月",
                        usedPercent: 4,
                        resetsAt: now.addingTimeInterval(22 * 86400)
                    )
                ]
            ),
            accounts[2].id: ProviderUsage(
                provider: .commandCode,
                planName: "GOAT",
                accountLabel: "drew",
                windows: [
                    UsageWindow(
                        kind: .session,
                        id: "fiveHour",
                        label: "5 小时",
                        usedPercent: 63,
                        resetsAt: now.addingTimeInterval(2 * 3600 + 5 * 60),
                        detail: "$12.60 / $20"
                    ),
                    UsageWindow(
                        kind: .weekly,
                        id: "weekly",
                        label: "每周",
                        usedPercent: 34,
                        resetsAt: now.addingTimeInterval(4 * 86400),
                        detail: "$17 / $50"
                    ),
                    UsageWindow(
                        kind: .monthly,
                        id: "monthly",
                        label: "本月",
                        usedPercent: 71,
                        resetsAt: now.addingTimeInterval(12 * 86400),
                        detail: "$56.80 / $80"
                    )
                ]
            ),
            accounts[3].id: ProviderUsage(
                provider: .openDesign,
                planName: "Go",
                accountLabel: "designer@example.com",
                windows: [
                    UsageWindow(
                        kind: .session,
                        id: "od-18000",
                        label: "5 小时",
                        usedPercent: 88,
                        resetsAt: now.addingTimeInterval(47 * 60)
                    ),
                    UsageWindow(
                        kind: .weekly,
                        id: "od-604800",
                        label: "7 天",
                        usedPercent: 52,
                        resetsAt: now.addingTimeInterval(5 * 86400 + 3 * 3600)
                    )
                ],
                balance: "钱包 $0.00"
            )
        ]
    }
}
