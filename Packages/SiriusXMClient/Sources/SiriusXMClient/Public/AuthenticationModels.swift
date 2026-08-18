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

/// Semantic result of an authentication attempt.
public enum AuthenticationOutcome: Sendable, Equatable {
    case waitingForAuthenticationComposition
    case authenticatedPendingEntitlement
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
}

/// Semantic catalog availability.
public enum CatalogAvailability: Sendable, Equatable {
    case unavailable
}

/// Semantic metadata availability.
public enum MetadataAvailability: Sendable, Equatable {
    case unavailable
}

/// Semantic live-stream resolution availability.
public enum LiveStreamResolutionAvailability: Sendable, Equatable {
    case unavailable
}
