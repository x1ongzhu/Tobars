import Foundation

public enum UsageFormatting {
    public static func amountDetail(used: Double, limit: Double) -> String {
        "$\(trim(used)) / $\(trim(limit))"
    }

    public static func usd(_ value: Double) -> String {
        "$\(trim(value))"
    }

    public static func trim(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        if value < 0.01 {
            return String(format: "%.4f", value)
        }
        return String(format: "%.2f", value)
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// "3h 12m" / "2d 4h" / "45m"
    public static func countdown(to date: Date, now: Date = Date()) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes >= 1440 {
            let days = minutes / 1440
            let hours = (minutes % 1440) / 60
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h"
        }
        return "\(max(1, minutes))m"
    }

    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }
}
