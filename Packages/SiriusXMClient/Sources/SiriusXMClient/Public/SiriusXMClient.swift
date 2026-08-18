/// Compatibility spelling retained for the walking skeleton's presentation model.
public typealias AuthenticationAvailability = AuthenticationOutcome

/// A semantic client for the supported SiriusXM subscriber experience.
public actor SiriusXMClient {
    public init() {}

    /// Returns the fail-closed Phase 1 state without contacting a provider.
    public func authenticationAvailability() -> AuthenticationAvailability {
        .waitingForAuthenticationComposition
    }

    /// Fails closed until the native authentication bridge is composed in a later plan.
    public func authenticate(using _: AuthenticationCredential) -> AuthenticationOutcome {
        .waitingForAuthenticationComposition
    }

    /// Reports that entitlement verification is unavailable before authentication composition.
    public func entitlement() -> EntitlementAvailability {
        .unavailable
    }

    /// Ends the empty in-memory session without scheduling retry work.
    public func signOut() -> SignOutOutcome {
        .alreadySignedOut
    }

    /// Keeps catalog work unavailable until the authorized content phase.
    public func catalog() -> CatalogAvailability {
        .unavailable
    }

    /// Keeps metadata work unavailable until the authorized content phase.
    public func metadata() -> MetadataAvailability {
        .unavailable
    }

    /// Keeps live-stream resolution unavailable until the authorized content phase.
    public func resolveLiveStream() -> LiveStreamResolutionAvailability {
        .unavailable
    }
}
