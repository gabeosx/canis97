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

    @Test("a fresh signed-out coordinator clears persisted local material")
    func clearsPersistedMaterialFromFreshState() async {
        let store = TrackingCredentialStore()
        let cleaner = TrackingResidueCleaner()
        let coordinator = makeActiveCoordinator(credentialStore: store, residueCleaner: cleaner)

        #expect(await coordinator.snapshot == .signedOut)
        #expect(await coordinator.signOut() == .signedOut)
        #expect(await store.eraseCount == 1)
        #expect(await cleaner.callCount == 1)
    }

    @Test("each explicit cleanup reruns idempotent external cleaners")
    func rerunsCleanersForSequentialExplicitRequests() async {
        let store = TrackingCredentialStore()
        let cleaner = TrackingResidueCleaner()
        let coordinator = makeActiveCoordinator(credentialStore: store, residueCleaner: cleaner)
        #expect(await coordinator.attemptSession() == .active)

        #expect(await coordinator.signOut() == .signedOut)
        #expect(await coordinator.signOut() == .signedOut)
        #expect(await store.eraseCount == 2)
        #expect(await cleaner.callCount == 2)
    }

    @Test("overlapping explicit cleanup requests share one cleanup operation")
    func coalescesOverlappingCleanupRequests() async {
        let store = TrackingCredentialStore()
        let cleaner = BlockingResidueCleaner()
        let coordinator = makeActiveCoordinator(credentialStore: store, residueCleaner: cleaner)

        let first = Task { await coordinator.signOut() }
        await cleaner.waitUntilStarted()
        let second = Task { await coordinator.signOut() }
        await Task.yield()

        #expect(await store.eraseCount == 1)
        #expect(await cleaner.callCount == 1)
        await cleaner.finish(with: .removed)
        #expect(await first.value == .signedOut)
        #expect(await second.value == .signedOut)
    }

    @Test("a later explicit request can retry cleanup after failure")
    func retriesOnlyWhenExplicitlyRequested() async {
        let store = FailOnceCredentialStore()
        let cleaner = TrackingResidueCleaner()
        let coordinator = makeActiveCoordinator(credentialStore: store, residueCleaner: cleaner)

        #expect(await coordinator.signOut() == .cleanupFailed(.keychain))
        #expect(await coordinator.snapshot == .signedOut)
        #expect(await coordinator.signOut() == .signedOut)
        #expect(await store.eraseCount == 2)
        #expect(await cleaner.callCount == 2)
    }

    @Test("cleanup remains complete after a new attempt begins between explicit requests")
    func cleansAfterNewAttemptFollowingEarlierCleanup() async {
        let store = TrackingCredentialStore()
        let cleaner = TrackingResidueCleaner()
        let coordinator = makeActiveCoordinator(credentialStore: store, residueCleaner: cleaner)

        #expect(await coordinator.signOut() == .signedOut)
        #expect(await coordinator.attemptSession() == .active)
        #expect(await coordinator.signOut() == .signedOut)
        #expect(await store.eraseCount == 2)
        #expect(await cleaner.callCount == 2)
    }

    @Test("a new attempt waits for blocked cleanup before reading or replacing persisted material")
    func waitsForBlockedCleanupBeforeStartingNewAttempt() async {
        let events = OperationLog()
        let source = CountingCredentialSource(events: events)
        let authentication = CountingAuthenticationVerifier(events: events)
        let entitlement = CountingEntitlementVerifier(events: events)
        let store = BlockingGenerationCredentialStore(events: events)
        let coordinator = SessionCoordinator(
            credentialSource: source,
            authenticationVerifier: authentication,
            entitlementVerifier: entitlement,
            credentialStore: store,
            residueCleaner: TrackingResidueCleaner(),
            clock: FixedSessionClock(),
            diagnostics: NoopDiagnostics()
        )

        #expect(await coordinator.attemptSession() == .active)
        #expect(await store.storedGeneration == 1)
        await events.clear()

        let signOut = Task { await coordinator.signOut() }
        await store.waitUntilEraseStarted()

        let replacement = Task.detached { await coordinator.attemptSession() }
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(await source.requestCount == 1)
        #expect(await authentication.callCount == 1)
        #expect(await entitlement.callCount == 1)
        #expect(await store.saveCount == 1)

        await store.releaseErase()

        #expect(await signOut.value == .signedOut)
        #expect(await replacement.value == .active)
        #expect(await store.storedGeneration == 2)
        #expect(await events.values == ["erase-old", "read-2", "authenticate-2", "entitle-2", "save-2"])
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
        await authentication.finish(with: nativeResponse(SanitizedNativeResponseFixtures.profileV4Authenticated))

        #expect(await attempt.value == .authentication(.cancelled))
        #expect(await coordinator.snapshot == .signedOut)
        #expect(await store.eraseCount == 1)
        #expect(await cleaner.callCount == 1)
    }

    @Test("explicit sign-out supersedes a blocked current-session revalidation")
    func signOutSupersedesBlockedRevalidationWithoutRestoringState() async {
        let entitlement = BlockingCurrentEntitlementVerifier()
        let store = TrackingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: StaticCredentialSource(),
            authenticationVerifier: StaticAuthenticationVerifier(),
            entitlementVerifier: entitlement,
            credentialStore: store,
            residueCleaner: TrackingResidueCleaner(),
            clock: FixedSessionClock(),
            diagnostics: NoopDiagnostics()
        )
        #expect(await coordinator.attemptSession() == .active)

        let revalidation = Task {
            await coordinator.withCurrentEntitledCredential { _ in "late work" }
        }
        await entitlement.waitUntilRevalidationStarted()

        #expect(await coordinator.signOut() == .signedOut)
        await entitlement.finishRevalidation(with: nativeResponse(SanitizedNativeResponseFixtures.subscriptionV1Active))

        guard case let .failed(failure) = await revalidation.value else {
            Issue.record("Expected the retired operation to be superseded")
            return
        }
        #expect(failure == .superseded)
        #expect(await coordinator.snapshot == .signedOut)
        #expect(await store.eraseCount == 1)
    }

    private func makeActiveCoordinator(
        credentialStore: any CredentialStore = TrackingCredentialStore(),
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

private actor CountingCredentialSource: CredentialSource {
    private let events: OperationLog
    private(set) var requestCount = 0

    init(events: OperationLog) {
        self.events = events
    }

    func credential() async -> AuthenticationCredential? {
        requestCount += 1
        await events.append("read-\(requestCount)")
        return AuthenticationCredential(volatileMaterial: Data("synthetic-\(requestCount)".utf8))
    }
}

private actor CountingAuthenticationVerifier: NativeAuthenticationVerifying {
    private let events: OperationLog
    private(set) var callCount = 0

    init(events: OperationLog) {
        self.events = events
    }

    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        callCount += 1
        await events.append("authenticate-\(callCount)")
        return nativeResponse(SanitizedNativeResponseFixtures.profileV4Authenticated)
    }
}

private actor CountingEntitlementVerifier: NativeEntitlementVerifying {
    private let events: OperationLog
    private(set) var callCount = 0

    init(events: OperationLog) {
        self.events = events
    }

    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        callCount += 1
        await events.append("entitle-\(callCount)")
        return nativeResponse(SanitizedNativeResponseFixtures.subscriptionV1Active)
    }
}

private actor OperationLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func clear() {
        values = []
    }
}

private actor StaticAuthenticationVerifier: NativeAuthenticationVerifying {
    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        nativeResponse(SanitizedNativeResponseFixtures.profileV4Authenticated)
    }
}

private actor StaticEntitlementVerifier: NativeEntitlementVerifying {
    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        nativeResponse(SanitizedNativeResponseFixtures.subscriptionV1Active)
    }
}

private actor BlockingCurrentEntitlementVerifier: NativeEntitlementVerifying {
    private var callCount = 0
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<NativeTransportResponse, Never>?

    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        callCount += 1
        guard callCount > 1 else {
            return nativeResponse(SanitizedNativeResponseFixtures.subscriptionV1Active)
        }
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func waitUntilRevalidationStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finishRevalidation(with response: NativeTransportResponse) {
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
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

private actor BlockingGenerationCredentialStore: CredentialStore {
    private let events: OperationLog
    private var eraseWaiter: CheckedContinuation<Void, Never>?
    private var eraseStarted = false
    private(set) var saveCount = 0
    private(set) var storedGeneration: Int?

    init(events: OperationLog) {
        self.events = events
    }

    func save(_: AuthenticationCredential) async throws {
        saveCount += 1
        storedGeneration = saveCount
        await events.append("save-\(saveCount)")
    }

    func erase() async throws {
        eraseStarted = true
        await withCheckedContinuation { eraseWaiter = $0 }
        storedGeneration = nil
        await events.append("erase-old")
    }

    func waitUntilEraseStarted() async {
        while !eraseStarted {
            await Task.yield()
        }
    }

    func releaseErase() {
        eraseWaiter?.resume()
        eraseWaiter = nil
    }
}

private actor FailOnceCredentialStore: CredentialStore {
    private(set) var eraseCount = 0

    func save(_: AuthenticationCredential) async throws {}

    func erase() async throws {
        eraseCount += 1
        if eraseCount == 1 { throw CleanupFailureError.failed }
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
        return result
    }
}

private actor BlockingResidueCleaner: AuthenticationResidueCleaner {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var resultWaiter: CheckedContinuation<AuthenticationResidueCleanupOutcome, Never>?
    private(set) var callCount = 0

    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome {
        callCount += 1
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

private func nativeResponse(_ body: Data) -> NativeTransportResponse {
    NativeTransportResponse(
        statusCode: 200,
        contentType: "application/json",
        body: body
    )
}
