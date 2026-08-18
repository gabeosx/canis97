import Foundation

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

    /// Composes the sole supported WebView-token/native-request authentication path.
    ///
    /// The app owns the credential source, persistence adapter, and browser-residue
    /// cleanup. The client owns the ephemeral native requests and derives every
    /// authentication and entitlement result from their responses.
    public init(
        credentialSource: any CredentialSource,
        credentialStore: any CredentialStore,
        residueCleaner: any AuthenticationResidueCleaner
    ) {
        let diagnostics = OSLogSessionDiagnostics()
        let verifier = NativeRequestVerifier(transport: EphemeralURLSessionTransport())
        sessionCoordinator = SessionCoordinator(
            credentialSource: credentialSource,
            authenticationVerifier: verifier,
            entitlementVerifier: verifier,
            credentialStore: credentialStore,
            residueCleaner: residueCleaner,
            clock: SystemSessionClock(),
            diagnostics: diagnostics
        )
    }

    /// Returns the fail-closed Phase 1 state without contacting a provider.
    public func authenticationAvailability() -> AuthenticationAvailability {
        .waitingForAuthenticationComposition
    }

    /// Consumes one opaque WebView credential and completes native authentication
    /// followed by native entitlement verification.
    public func authenticate() async -> AuthenticationOutcome {
        guard let sessionCoordinator else {
            return .waitingForAuthenticationComposition
        }

        switch await sessionCoordinator.attemptSession() {
        case .active, .entitlement:
            // Entitlement remains separately observable through `entitlement()`.
            return .authenticatedPendingEntitlement
        case let .authentication(outcome):
            return outcome
        case .attemptInProgress:
            return .waitingForAuthenticationComposition
        }
    }

    /// Reports the entitlement derived from the most recent native transaction.
    public func entitlement() async -> EntitlementAvailability {
        guard let sessionCoordinator else {
            return .unavailable
        }
        return await sessionCoordinator.entitlementAvailability
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

private final class NativeRequestVerifier: NativeAuthenticationVerifying, NativeEntitlementVerifying, @unchecked Sendable {
    private let transport: any SessionTransport

    init(transport: any SessionTransport) {
        self.transport = transport
    }

    func verifyAuthentication(using credential: AuthenticationCredential) async -> NativeTransportResponse {
        await response(for: .authentication, using: credential)
    }

    func verifyEntitlement(using credential: AuthenticationCredential) async -> NativeTransportResponse {
        await response(for: .entitlement, using: credential)
    }

    private func response(
        for operation: SiriusXMRequestContract,
        using credential: AuthenticationCredential
    ) async -> NativeTransportResponse {
        do {
            return try await transport.send(operation, using: credential)
        } catch {
            // Transport errors expose no provider detail and classify as unsupported.
            return NativeTransportResponse(
                statusCode: 500,
                contentType: nil,
                body: Data(),
                transportFailed: true
            )
        }
    }
}

private struct SystemSessionClock: SessionClock {
    func now() -> Date { Date() }
}
