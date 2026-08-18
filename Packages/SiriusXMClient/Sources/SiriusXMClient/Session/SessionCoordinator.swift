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
    private let residueCleaner: any AuthenticationResidueCleaner
    private let clock: any SessionClock
    private let diagnostics: any SessionDiagnostics

    private var attemptLease: AttemptLease?
    private var transientCredential: AuthenticationCredential?
    private var pendingVerification: PendingVerification?
    private var state: SessionState = .signedOut
    private var lastEntitlement: EntitlementAvailability = .unavailable
    private var cleanupTask: Task<SignOutOutcome, Never>?

    init(
        credentialSource: any CredentialSource,
        authenticationVerifier: any NativeAuthenticationVerifying,
        entitlementVerifier: any NativeEntitlementVerifying,
        credentialStore: any CredentialStore,
        residueCleaner: any AuthenticationResidueCleaner = NoopResidueCleaner(),
        clock: any SessionClock,
        diagnostics: any SessionDiagnostics
    ) {
        self.credentialSource = credentialSource
        self.authenticationVerifier = authenticationVerifier
        self.entitlementVerifier = entitlementVerifier
        self.credentialStore = credentialStore
        self.residueCleaner = residueCleaner
        self.clock = clock
        self.diagnostics = diagnostics
    }

    var snapshot: SessionState {
        state
    }

    var entitlementAvailability: EntitlementAvailability {
        lastEntitlement
    }

    func attemptSession() async -> SessionAttemptOutcome {
        guard attemptLease == nil else {
            return .attemptInProgress
        }

        let lease = AttemptLease()
        attemptLease = lease
        lastEntitlement = .unavailable
        defer {
            if isCurrent(lease) {
                attemptLease = nil
                transientCredential = nil
                pendingVerification = nil
                if case .active = state {
                    // An active session is already an immutable, fully verified value.
                } else {
                    state = .signedOut
                }
            }
        }

        guard let credential = await credentialSource.credential(), isCurrent(lease) else {
            await diagnostics.record(.cancelled)
            return .authentication(.cancelled)
        }
        transientCredential = credential

        guard isCurrent(lease), !Task.isCancelled else {
            await diagnostics.record(.cancelled)
            return .authentication(.cancelled)
        }

        pendingVerification = .authentication
        state = .verifyingAuthentication
        let authenticationResponse = await authenticationVerifier.verifyAuthentication(using: credential)

        guard isCurrent(lease), !Task.isCancelled else {
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

        guard isCurrent(lease), !Task.isCancelled else {
            await diagnostics.record(.cancelled)
            return .authentication(.cancelled)
        }

        let entitlement = AuthenticationFlowAdapter.classifyEntitlement(entitlementResponse)
        guard entitlement == .entitled else {
            let outcome = entitlement.publicOutcome
            lastEntitlement = outcome
            await diagnostics.record(.entitlement(outcome))
            return .entitlement(outcome)
        }

        guard isCurrent(lease) else {
            await diagnostics.record(.cancelled)
            return .authentication(.cancelled)
        }

        let activeSession = ActiveSession(establishedAt: clock.now())
        state = .active(activeSession)
        lastEntitlement = .entitled

        do {
            try await credentialStore.save(credential)
        } catch {
            await diagnostics.record(.credentialPersistenceFailed)
        }
        return .active
    }

    /// Retires all actor-owned material before attempting each app-owned cleaner once.
    func signOut() async -> SignOutOutcome {
        if let cleanupTask {
            return await cleanupTask.value
        }

        attemptLease = nil
        transientCredential = nil
        pendingVerification = nil
        state = .signedOut
        lastEntitlement = .unavailable
        let cleanupTask: Task<SignOutOutcome, Never> = Task.detached { [credentialStore, residueCleaner] in
            async let keychainFailed: Bool = {
                do {
                    try await credentialStore.erase()
                    return false
                } catch {
                    return true
                }
            }()
            async let residueFailed: Bool = {
                await residueCleaner.removeAuthenticationResidue() == .cleanupFailed
            }()

            switch await (keychainFailed, residueFailed) {
            case (false, false):
                return .signedOut
            case (true, false):
                return .cleanupFailed(.keychain)
            case (false, true):
                return .cleanupFailed(.browserResidue)
            case (true, true):
                return .cleanupFailed(.both)
            }
        }
        self.cleanupTask = cleanupTask
        let outcome = await cleanupTask.value
        self.cleanupTask = nil
        return outcome
    }

    private func isCurrent(_ lease: AttemptLease) -> Bool {
        attemptLease?.id == lease.id
    }
}

private struct NoopResidueCleaner: AuthenticationResidueCleaner {
    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome {
        .removed
    }
}
