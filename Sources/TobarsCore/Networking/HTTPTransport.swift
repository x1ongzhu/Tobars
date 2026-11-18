import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    public let data: Data
    public let headers: [String: String]

    public init(status: Int, data: Data, headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = headers
    }

    public var bodyText: String? {
        String(data: data, encoding: .utf8)
    }
}

public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

/// 默认实现。刻意不跟随重定向之外的特殊处理，也不缓存，方便排查供应商侧行为。
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 20) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 10
        config.httpAdditionalHeaders = ["User-Agent": "Tobars/0.1 (macOS)"]
        self.session = URLSession(configuration: config)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderError.network("响应不是 HTTP")
            }
            var mapped: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    mapped[key] = value
                }
            }
            return HTTPResponse(status: http.statusCode, data: data, headers: mapped)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }
    }
}

extension HTTPResponse {
    /// 统一处理 401/403/非 2xx，避免每个 provider 重复写。
    func validated(provider: ProviderID) throws -> JSON {
        switch status {
        case 200...299:
            do {
                return try JSON(data: data)
            } catch {
                throw ProviderError.malformed("\(provider.displayName) 返回了非 JSON 内容")
            }
        case 401:
            throw ProviderError.unauthorized
        case 403:
            let reason = (try? JSON(data: data))?["error"]?.string
                ?? (try? JSON(data: data))?["message"]?.string
            throw ProviderError.forbidden(reason)
        default:
            throw ProviderError.http(status: status, body: bodyText)
        }
    }
}
