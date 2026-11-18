import Foundation

/// 这些供应商的接口都没有公开契约（或只有部分公开），字段类型会漂移：
/// 同一个数值可能是 Int、Double 或字符串，时间可能是 ISO8601 或 epoch。
/// 用一个宽松的 JSON 包装器解析，避免为每个漂移点写一堆 Codable 兼容代码。
public struct JSON {
    public let raw: Any

    public init(raw: Any) {
        self.raw = raw
    }

    public init(data: Data) throws {
        do {
            self.raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ProviderError.malformed("JSON 无效：\(error.localizedDescription)")
        }
    }

    public subscript(key: String) -> JSON? {
        guard let dict = raw as? [String: Any], let value = dict[key], !(value is NSNull) else {
            return nil
        }
        return JSON(raw: value)
    }

    public func array(_ key: String) -> [JSON]? {
        guard let values = self[key]?.raw as? [Any] else { return nil }
        return values.map(JSON.init(raw:))
    }

    public var array: [JSON]? {
        guard let values = raw as? [Any] else { return nil }
        return values.map(JSON.init(raw:))
    }

    public var string: String? {
        switch raw {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    public var double: Double? {
        switch raw {
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }

    public var bool: Bool? {
        switch raw {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String: return ["true", "1", "yes"].contains(value.lowercased())
        default: return nil
        }
    }

    /// epoch（秒或毫秒）与 ISO8601（带/不带小数秒）都接受。
    public var date: Date? {
        if let number = raw as? NSNumber {
            let value = number.doubleValue
            guard value > 0 else { return nil }
            return Date(timeIntervalSince1970: value > 1_000_000_000_000 ? value / 1000 : value)
        }
        guard let text = string, !text.isEmpty else { return nil }
        if let number = Double(text), number > 1_000_000_000 {
            return Date(timeIntervalSince1970: number > 1_000_000_000_000 ? number / 1000 : number)
        }
        return ISO8601DateFormatter.tobars.date(from: text)
    }
}

extension ISO8601DateFormatter {
    static let tobars: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let tobarsNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension JSON {
    public var isoDate: Date? {
        guard let text = string, !text.isEmpty else { return date }
        return ISO8601DateFormatter.tobars.date(from: text)
            ?? ISO8601DateFormatter.tobarsNoFraction.date(from: text)
            ?? date
    }
}

/// 让 `json?["a"]?["b"]` 这种可选链可以继续取标量，而不必层层 unwrap。
/// 这些属性与 `JSON` 上的同名属性一一对应；`self?.x` 调用的是 `Wrapped` 的实现。
public extension Optional where Wrapped == JSON {
    var string: String? { self?.string }
    var double: Double? { self?.double }
    var bool: Bool? { self?.bool }
    var date: Date? { self?.date }
    var isoDate: Date? { self?.isoDate }
}
