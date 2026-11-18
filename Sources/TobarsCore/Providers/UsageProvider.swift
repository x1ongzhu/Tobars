import Foundation

public protocol UsageProviding: Sendable {
    var id: ProviderID { get }
    func fetchUsage(credential: ProviderCredential) async throws -> ProviderUsage
}

public enum ProviderRegistry {
    public static func provider(
        for id: ProviderID,
        transport: HTTPTransport = URLSessionTransport()
    ) -> any UsageProviding {
        switch id {
        case .openCodeGo: return OpenCodeGoProvider(transport: transport)
        case .commandCode: return CommandCodeProvider(transport: transport)
        case .openDesign: return OpenDesignProvider(transport: transport)
        }
    }

    public static func all(transport: HTTPTransport = URLSessionTransport()) -> [any UsageProviding] {
        ProviderID.allCases.map { provider(for: $0, transport: transport) }
    }
}
