import Foundation

/// Internal transport seam for deterministic session verification tests.
protocol SessionTransport: Sendable {
    func send(
        _ operation: SiriusXMRequestContract,
        using credential: AuthenticationCredential
    ) async throws -> NativeTransportResponse
}
