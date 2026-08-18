import Foundation

/// The semantic authentication availability visible before the native bridge is composed.
public enum AuthenticationAvailability: Sendable, Equatable {
    case waitingForComposition
}

/// A semantic client for the supported SiriusXM subscriber experience.
public actor SiriusXMClient {
    public init() {}

    /// Returns the fail-closed Phase 1 state without contacting a provider.
    public func authenticationAvailability() -> AuthenticationAvailability {
        .waitingForComposition
    }
}
