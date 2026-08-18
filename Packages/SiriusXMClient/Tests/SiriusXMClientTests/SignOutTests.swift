import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Memory-first sign-out")
struct SignOutTests {
    @Test("sign-out clears actor memory before external cleanup begins")
    func clearsMemoryBeforeCleaners() async {
        let cleaner = BlockingResidueCleaner()
        let coordinator = makeActiveCoordinator(residueCleaner: cleaner)
        #expect(await coordinator.attemptSession() == .active)

        let signOut = Task { await coordinator.signOut() }
        await cleaner.waitUntilStarted()

        #expect(await coordinator.snapshot == .signedOut)
        await cleaner.finish(with: .removed)
        #expect(await signOut.value == .signedOut)
    }

    @Test("each external cleaner runs once and successful sign-out is idempotent")
    func cleansEachStoreOnce() async {
        let store = TrackingCredentialStore()
        let cleaner = TrackingResidueCleaner()
        let coordinator = makeActiveCoordinator(credentialStore: store, residueCleaner: cleaner)
        #expect(await coordinator.attemptSession() == .active)

        #expect(await coordinator.signOut() == .signedOut)
        #expect(await coordinator.signOut() == .alreadySignedOut)
        #expect(await store.eraseCount == 1)
        #expect(await cleaner.callCount == 1)
    }

    @Test("partial and complete cleanup failures remain explicit after memory is retired")
    func reportsAggregateCleanupFailures() async {
        let keychainFailure = makeActiveCoordinator(
            credentialStore: TrackingCredentialStore(shouldFail: true),
            residueCleaner: TrackingResidueCleaner()
        )
        #expect(await keychainFailure.attemptSession() == .active)
        #expect(await keychainFailure.signOut() == .cleanupFailed(.keychain))
        #expect(await keychainFailure.snapshot == .signedOut)

        let bothFailures = makeActiveCoordinator(
            credentialStore: TrackingCredentialStore(shouldFail: true),
            residueCleaner: TrackingResidueCleaner(result: .cleanupFailed)
        )
        #expect(await bothFailures.attemptSession() == .active)
        #expect(await bothFailures.signOut() == .cleanupFailed(.both))
        #expect(await bothFailures.snapshot == .signedOut)
    }

    @Test("retired in-flight work cannot reactivate state or skip cleanup")
    func revokesInFlightAttemptBeforeCleanup() async {
        let authentication = BlockingAuthenticationVerifier()
        let store = TrackingCredentialStore()
        let cleaner = TrackingResidueCleaner()
        let coordinator = SessionCoordinator(
            credentialSource: StaticCredentialSource(),
            authenticationVerifier: authentication,
            entitlementVerifier: StaticEntitlementVerifier(),
            credentialStore: store,
            residueCleaner: cleaner,
            clock: FixedSessionClock(),
            diagnostics: NoopDiagnostics()
        )

        let attempt = Task { await coordinator.attemptSession() }
        await authentication.waitUntilStarted()

        #expect(await coordinator.signOut() == .signedOut)
        await authentication.finish(with: nativeResponse(["authenticated": true]))

        #expect(await attempt.value == .authentication(.cancelled))
        #expect(await coordinator.snapshot == .signedOut)
        #expect(await store.eraseCount == 1)
        #expect(await cleaner.callCount == 1)
    }

    private func makeActiveCoordinator(
        credentialStore: TrackingCredentialStore = TrackingCredentialStore(),
        residueCleaner: any AuthenticationResidueCleaner = TrackingResidueCleaner()
    ) -> SessionCoordinator {
        SessionCoordinator(
            credentialSource: StaticCredentialSource(),
            authenticationVerifier: StaticAuthenticationVerifier(),
            entitlementVerifier: StaticEntitlementVerifier(),
            credentialStore: credentialStore,
            residueCleaner: residueCleaner,
            clock: FixedSessionClock(),
            diagnostics: NoopDiagnostics()
        )
    }
}

private actor StaticCredentialSource: CredentialSource {
    func credential() async -> AuthenticationCredential? {
        AuthenticationCredential(volatileMaterial: Data("credential".utf8))
    }
}

private actor StaticAuthenticationVerifier: NativeAuthenticationVerifying {
    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        nativeResponse(["authenticated": true])
    }
}

private actor StaticEntitlementVerifier: NativeEntitlementVerifying {
    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        nativeResponse(["entitled": true])
    }
}

private actor BlockingAuthenticationVerifier: NativeAuthenticationVerifying {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<NativeTransportResponse, Never>?

    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish(with response: NativeTransportResponse) {
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
    }
}

private actor TrackingCredentialStore: CredentialStore {
    private let shouldFail: Bool
    private(set) var eraseCount = 0

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func save(_: AuthenticationCredential) async throws {}

    func erase() async throws {
        eraseCount += 1
        if shouldFail { throw CleanupFailureError.failed }
    }
}

private actor TrackingResidueCleaner: AuthenticationResidueCleaner {
    private let result: AuthenticationResidueCleanupOutcome
    private(set) var callCount = 0

    init(result: AuthenticationResidueCleanupOutcome = .removed) {
        self.result = result
    }

    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome {
        callCount += 1
        result
    }
}

private actor BlockingResidueCleaner: AuthenticationResidueCleaner {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var resultWaiter: CheckedContinuation<AuthenticationResidueCleanupOutcome, Never>?

    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { resultWaiter = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish(with result: AuthenticationResidueCleanupOutcome) {
        resultWaiter?.resume(returning: result)
        resultWaiter = nil
    }
}

private struct FixedSessionClock: SessionClock {
    func now() -> Date { Date(timeIntervalSince1970: 1) }
}

private actor NoopDiagnostics: SessionDiagnostics {
    func record(_: SessionDiagnosticEvent) async {}
}

private enum CleanupFailureError: Error { case failed }

private func nativeResponse(_ object: [String: Any]) -> NativeTransportResponse {
    NativeTransportResponse(
        statusCode: 200,
        contentType: "application/json",
        body: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}
