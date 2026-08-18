/// Compatibility spelling retained for the walking skeleton's presentation model.
public typealias AuthenticationAvailability = AuthenticationOutcome

/// A semantic client for the supported SiriusXM subscriber experience.
public actor SiriusXMClient {
    private let sessionCoordinator: SessionCoordinator?

    public init() {
        self.sessionCoordinator = nil
    }

    init(sessionCoordinator: SessionCoordinator) {
        self.sessionCoordinator = sessionCoordinator
    }

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
    public func signOut() async -> SignOutOutcome {
        guard let sessionCoordinator else {
            return .alreadySignedOut
        }
        return await sessionCoordinator.signOut()
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
