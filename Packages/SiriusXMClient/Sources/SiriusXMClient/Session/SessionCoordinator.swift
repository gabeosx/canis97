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
                pendingVerification = nil
                if case .active = state {
                    // The verified credential remains actor-owned for fixed current-session
                    // operations. It is never returned through the public client API.
                } else {
                    transientCredential = nil
                    state = .signedOut
                }
            }
        }

        guard let credential = await credentialSource.credential(), isCurrent(lease) else {
            await diagnostics.record(.authentication(.credentialUnavailable))
            return .authentication(.cancelled)
        }
        transientCredential = credential

        guard isCurrent(lease), !Task.isCancelled else {
            await diagnostics.record(.authentication(.cancelled))
            return .authentication(.cancelled)
        }

        pendingVerification = .authentication
        state = .verifyingAuthentication
        let authenticationResponse = await authenticationVerifier.verifyAuthentication(using: credential)

        guard isCurrent(lease), !Task.isCancelled else {
            await diagnostics.record(.authentication(.cancelled))
            return .authentication(.cancelled)
        }

        let authentication = AuthenticationFlowAdapter.inspectAuthentication(authenticationResponse)
        await diagnostics.record(.authentication(authentication.diagnosticOutcome))
        guard authentication.result == .authenticatedPendingEntitlement else {
            let outcome = authentication.result.publicOutcome
            return .authentication(outcome)
        }

        pendingVerification = .entitlement
        state = .verifyingEntitlement
        let entitlementResponse = await entitlementVerifier.verifyEntitlement(using: credential)

        guard isCurrent(lease), !Task.isCancelled else {
            await diagnostics.record(.authentication(.cancelled))
            return .authentication(.cancelled)
        }

        let entitlement = AuthenticationFlowAdapter.inspectEntitlement(entitlementResponse)
        await diagnostics.record(.entitlement(entitlement.diagnosticOutcome))
        guard entitlement.result == .entitled else {
            let outcome = entitlement.result.publicOutcome
            lastEntitlement = outcome
            return .entitlement(outcome)
        }

        guard isCurrent(lease) else {
            await diagnostics.record(.authentication(.cancelled))
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

    /// Revalidates entitlement immediately before a fixed live operation and
    /// invokes the supplied work while keeping the credential actor-owned.
    func withCurrentEntitledCredential<Value: Sendable>(
        _ work: @Sendable (AuthenticationCredential) async -> Value
    ) async -> CurrentEntitledOperationResult<Value> {
        guard case let .active(activeSession) = state,
              lastEntitlement == .entitled,
              let credential = transientCredential
        else {
            return .failed(.authenticationUnavailable)
        }

        let response = await entitlementVerifier.verifyEntitlement(using: credential)
        guard case let .active(currentSession) = state,
              currentSession == activeSession,
              lastEntitlement == .entitled
        else {
            return .failed(.superseded)
        }

        if let transportFailure = response.transportFailure {
            return .failed(transportFailure == .cancelled ? .cancelled : .networkUnavailable)
        }
        guard response.redirectLocation == nil else {
            return .failed(.protectedControl)
        }

        let inspection = AuthenticationFlowAdapter.inspectEntitlement(response)
        let entitlement = inspection.result
        await diagnostics.record(.entitlement(inspection.diagnosticOutcome))
        guard entitlement == .entitled else {
            switch entitlement {
            case .authenticatedButNotEntitled:
                return .failed(.entitlementUnavailable)
            case .rejected:
                return .failed(.authenticationUnavailable)
            case .challengeRequired, .rateLimited, .botControlDetected:
                return .failed(.protectedControl)
            case .redirectDrift, .unsupported, .entitled:
                return .failed(.entitlementUnavailable)
            }
        }

        let value = await work(credential)
        guard case let .active(currentSession) = state,
              currentSession == activeSession,
              lastEntitlement == .entitled
        else {
            return .failed(.superseded)
        }
        return .completed(value)
    }

    /// Performs exactly one caller-selected fixed operation using the current
    /// active credential. Unlike tune resolution, catalog refresh does not
    /// issue an implicit second entitlement request: its caller has already
    /// performed the current-session entitlement check and each explicit
    /// refresh has a one-request ceiling.
    func withCurrentCatalogCredential<Value: Sendable>(
        _ work: @Sendable (AuthenticationCredential) async -> Value
    ) async -> CurrentCatalogOperationResult<Value> {
        guard case let .active(activeSession) = state,
              lastEntitlement == .entitled,
              let credential = transientCredential
        else {
            return state == .signedOut ? .authenticationUnavailable : .notEntitled
        }

        let value = await work(credential)
        guard case let .active(currentSession) = state,
              currentSession == activeSession
        else {
            return .superseded
        }
        guard lastEntitlement == .entitled else {
            return .notEntitled
        }
        return .completed(value)
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
