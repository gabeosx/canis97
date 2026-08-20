import Foundation

/// An opaque, in-memory credential handoff for the app-owned authentication bridge.
///
/// The value intentionally cannot be encoded or rendered with its material.
public struct AuthenticationCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let material: Data

    /// Creates a volatile handoff value for a caller that has already performed an authorized extraction.
    public init(volatileMaterial: Data) {
        self.material = volatileMaterial
    }

    public var description: String { "AuthenticationCredential(redacted)" }
    public var debugDescription: String { "AuthenticationCredential(redacted)" }

    /// Performs work with the short-lived material for the app's approved integration boundary.
    ///
    /// This SPI exists solely for the app-owned Keychain adapter. It is not part of the
    /// ordinary client-consumer API and does not provide a persistent credential accessor.
    @_spi(AppIntegration)
    public func withVolatileMaterial<Result: Sendable>(_ operation: (Data) throws -> Result) rethrows -> Result {
        try operation(material)
    }
}

/// Supplies an opaque credential to the client without exposing integration mechanics.
public protocol CredentialSource: Sendable {
    func credential() async -> AuthenticationCredential?
}

/// Persists only client-approved opaque credential material at the app boundary.
public protocol CredentialStore: Sendable {
    func save(_ credential: AuthenticationCredential) async throws
    func erase() async throws
}

/// Removes app-owned browser residue without exposing browser APIs to the client.
public protocol AuthenticationResidueCleaner: Sendable {
    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome
}

/// Semantic completion state for one injected browser-residue cleanup operation.
public enum AuthenticationResidueCleanupOutcome: Sendable, Equatable {
    case removed
    case cleanupFailed
}

/// Semantic result of an authentication attempt.
public enum AuthenticationOutcome: Sendable, Equatable {
    case waitingForAuthenticationComposition
    case authenticatedPendingEntitlement
    case credentialPersistenceFailed
    case rejected
    case challengeRequired
    case unsupported
    case cancelled
}

/// Semantic entitlement availability for the current client state.
public enum EntitlementAvailability: Sendable, Equatable {
    case unavailable
    case entitled
    case authenticatedButNotEntitled
    case rejected
    case challengeRequired
    case unsupported
    case cancelled
}

/// Semantic result of ending a client session.
public enum SignOutOutcome: Sendable, Equatable {
    case alreadySignedOut
    case signedOut
    case cleanupFailed(SignOutCleanupFailure)
}

/// Safe aggregate classification for local cleanup that did not complete.
public enum SignOutCleanupFailure: Sendable, Equatable {
    case keychain
    case browserResidue
    case both
}
