import Foundation

/// The only runtime authority allowed to create an active client session.
///
/// It consumes a supplied volatile credential once, verifies authentication and
/// entitlement separately, and publishes an immutable session only after both
/// verifications have succeeded.
actor SessionCoordinator {
    private struct AttemptLease: Sendable {
        let id = UUID()
    }

    private enum PendingVerification: Sendable {
        case authentication
        case entitlement
    }

    private let credentialSource: any CredentialSource
    private let authenticationVerifier: any NativeAuthenticationVerifying
    private let entitlementVerifier: any NativeEntitlementVerifying
    private let credentialStore: any CredentialStore
    private let clock: any SessionClock
    private let diagnostics: any SessionDiagnostics

    private var attemptLease: AttemptLease?
    private var transientCredential: AuthenticationCredential?
    private var pendingVerification: PendingVerification?
    private var state: SessionState = .signedOut

    init(
        credentialSource: any CredentialSource,
        authenticationVerifier: any NativeAuthenticationVerifying,
        entitlementVerifier: any NativeEntitlementVerifying,
        credentialStore: any CredentialStore,
        clock: any SessionClock,
        diagnostics: any SessionDiagnostics
    ) {
        self.credentialSource = credentialSource
        self.authenticationVerifier = authenticationVerifier
        self.entitlementVerifier = entitlementVerifier
        self.credentialStore = credentialStore
        self.clock = clock
        self.diagnostics = diagnostics
    }

    var snapshot: SessionState {
        state
    }

    func attemptSession() async -> SessionAttemptOutcome {
        guard attemptLease == nil else {
            return .attemptInProgress
        }

        attemptLease = AttemptLease()
        defer {
            attemptLease = nil
            transientCredential = nil
            pendingVerification = nil
            if case .active = state {
                // An active session is already an immutable, fully verified value.
            } else {
                state = .signedOut
            }
        }

        guard let credential = await credentialSource.credential() else {
            await diagnostics.record(.cancelled)
            return .authentication(.cancelled)
        }
        transientCredential = credential

        guard !Task.isCancelled else {
            await diagnostics.record(.cancelled)
            return .authentication(.cancelled)
        }

        pendingVerification = .authentication
        state = .verifyingAuthentication
        let authenticationResponse = await authenticationVerifier.verifyAuthentication(using: credential)

        guard !Task.isCancelled else {
            await diagnostics.record(.cancelled)
            return .authentication(.cancelled)
        }

        let authentication = AuthenticationFlowAdapter.classifyAuthentication(authenticationResponse)
        guard authentication == .authenticatedPendingEntitlement else {
            let outcome = authentication.publicOutcome
            await diagnostics.record(.authentication(outcome))
            return .authentication(outcome)
        }

        pendingVerification = .entitlement
        state = .verifyingEntitlement
        let entitlementResponse = await entitlementVerifier.verifyEntitlement(using: credential)

        guard !Task.isCancelled else {
            await diagnostics.record(.cancelled)
            return .authentication(.cancelled)
        }

        let entitlement = AuthenticationFlowAdapter.classifyEntitlement(entitlementResponse)
        guard entitlement == .entitled else {
            let outcome = entitlement.publicOutcome
            await diagnostics.record(.entitlement(outcome))
            return .entitlement(outcome)
        }

        let activeSession = ActiveSession(establishedAt: clock.now())
        state = .active(activeSession)

        do {
            try await credentialStore.save(credential)
        } catch {
            await diagnostics.record(.credentialPersistenceFailed)
        }
        return .active
    }
}
