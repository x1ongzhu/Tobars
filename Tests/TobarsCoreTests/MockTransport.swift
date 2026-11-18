import Foundation
import TobarsCore

struct MockTransport: HTTPTransport {
    let handler: @Sendable (URL, [String: String]) async throws -> HTTPResponse

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await handler(url, headers)
    }

}

extension HTTPResponse {
    static func json(_ body: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, data: Data(body.utf8))
    }
}

final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(URL, [String: String])] = []

    func record(_ url: URL, _ headers: [String: String]) {
        lock.lock()
        storage.append((url, headers))
        lock.unlock()
    }

    var requests: [(URL, [String: String])] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
