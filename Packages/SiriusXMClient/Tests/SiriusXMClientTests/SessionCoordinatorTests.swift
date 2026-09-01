import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Session coordinator")
struct SessionCoordinatorTests {
    @Test("one attempt consumes one credential and verifies in order")
    func performsAuthenticationThenEntitlementOnce() async {
        let source = RecordingCredentialSource()
        let sequence = VerificationSequence()
        let authentication = RecordingAuthenticationVerifier(sequence: sequence, response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated))
        let entitlement = RecordingEntitlementVerifier(sequence: sequence, response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active))
        let store = RecordingCredentialStore()
        let diagnostics = RecordingDiagnostics()
        let coordinator = SessionCoordinator(
            credentialSource: source,
            authenticationVerifier: authentication,
            entitlementVerifier: entitlement,
            credentialStore: store,
            clock: FixedSessionClock(),
            diagnostics: diagnostics
        )

        #expect(await coordinator.attemptSession() == .active)
        #expect(await source.requestCount == 1)
        #expect(await authentication.callCount == 1)
        #expect(await entitlement.callCount == 1)
        #expect(await sequence.events == [.authentication, .entitlement])
        #expect(await store.saveCount == 1)
        #expect(await diagnostics.events == [
            .authentication(.completed),
            .entitlement(.completed),
            .credentialPersistenceCompleted,
        ])
    }

    @Test("an expiring browser credential is renewed and durably replaced before verification")
    func renewsBeforeAuthentication() async throws {
        let initial = try browserCredential(
            accessToken: "synthetic-expired-access",
            accessExpiresAt: Date(timeIntervalSince1970: 0)
        )
        let refreshed = try browserCredential(
            accessToken: "synthetic-refreshed-access",
            accessExpiresAt: Date(timeIntervalSince1970: 20_000)
        )
        let refresher = RecordingCredentialRefresher(result: refreshed)
        let authentication = CredentialRecordingAuthenticationVerifier(
            response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)
        )
        let store = RecordingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(credential: initial),
            authenticationVerifier: authentication,
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: store,
            credentialRefresher: refresher,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        #expect(await coordinator.attemptSession() == .active)
        #expect(await refresher.refreshCount == 1)
        #expect(await authentication.lastAccessToken == "synthetic-refreshed-access")
        // One atomic renewal save precedes the ordinary post-entitlement durability save.
        #expect(await store.saveCount == 2)
    }

#if DEBUG
    @Test("qualification renews a fresh active credential once and proves cookie rotation twice")
    func qualifiesFreshCredentialAndPersistsEachRotation() async throws {
        let initial = try browserCredential(
            accessToken: "synthetic-current-access",
            accessExpiresAt: Date(timeIntervalSince1970: 20_000)
        )
        let firstReplacement = try browserCredential(
            accessToken: "synthetic-first-replacement",
            accessExpiresAt: Date(timeIntervalSince1970: 30_000)
        )
        let secondReplacement = try browserCredential(
            accessToken: "synthetic-second-replacement",
            accessExpiresAt: Date(timeIntervalSince1970: 40_000)
        )
        let refresher = SequencedCredentialRefresher([firstReplacement, secondReplacement])
        let store = RecordingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(credential: initial),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: store,
            credentialRefresher: refresher,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        #expect(await coordinator.attemptSession() == .active)
        #expect(await coordinator.qualifyCurrentCredentialRenewal() == .replacementPersisted)
        #expect(await coordinator.qualifyCurrentCredentialRenewal() == .replacementPersisted)
        #expect(await refresher.refreshCount == 2)
        // Initial post-entitlement save plus one atomic save for each rotation.
        #expect(await store.saveCount == 3)
        guard case .active = await coordinator.snapshot else {
            Issue.record("Qualification must preserve the active session")
            return
        }
    }

    @Test("qualification fails closed when renewal does not return a replacement")
    func qualificationWithoutReplacementPreservesActiveSession() async throws {
        let initial = try browserCredential(
            accessToken: "synthetic-current-access",
            accessExpiresAt: Date(timeIntervalSince1970: 20_000)
        )
        let refresher = RecordingCredentialRefresher(result: nil)
        let store = RecordingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(credential: initial),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: store,
            credentialRefresher: refresher,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        #expect(await coordinator.attemptSession() == .active)
        #expect(await coordinator.qualifyCurrentCredentialRenewal() == .renewalUnavailable)
        #expect(await refresher.refreshCount == 1)
        #expect(await store.saveCount == 1)
        guard case .active = await coordinator.snapshot else {
            Issue.record("A closed qualification failure must preserve the active session")
            return
        }
    }

    @Test("qualification rejects overlap instead of joining or retrying")
    func qualificationRejectsConcurrentAttempt() async throws {
        let initial = try browserCredential(
            accessToken: "synthetic-current-access",
            accessExpiresAt: Date(timeIntervalSince1970: 20_000)
        )
        let replacement = try browserCredential(
            accessToken: "synthetic-replacement-access",
            accessExpiresAt: Date(timeIntervalSince1970: 30_000)
        )
        let refresher = BlockingCredentialRefresher(result: replacement)
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(credential: initial),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: RecordingCredentialStore(),
            credentialRefresher: refresher,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        #expect(await coordinator.attemptSession() == .active)
        let first = Task { await coordinator.qualifyCurrentCredentialRenewal() }
        await refresher.waitUntilStarted()
        #expect(await coordinator.qualifyCurrentCredentialRenewal() == .attemptInProgress)
        await refresher.release()
        #expect(await first.value == .replacementPersisted)
        #expect(await refresher.refreshCount == 1)
    }
#endif

    @Test("a down authentication endpoint remains a closed support-visible transport outcome")
    func recordsAuthenticationEndpointConnectionFailure() async {
        let diagnostics = OSLogSessionDiagnostics()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(),
            authenticationVerifier: RecordingAuthenticationVerifier(response: NativeTransportResponse(
                statusCode: 0,
                contentType: nil,
                body: Data(),
                transportFailure: SafeTransportFailure(error: URLError(.cannotConnectToHost))
            )),
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: RecordingCredentialStore(),
            clock: FixedSessionClock(),
            diagnostics: diagnostics
        )
        let client = SiriusXMClient(
            sessionCoordinator: coordinator,
            retainedSessionDiagnostics: diagnostics
        )

        #expect(await client.authenticate() == .unsupported)
        #expect(await client.latestAuthenticationDiagnostic() == .transportConnectionFailed)
    }

    @Test("a refreshed credential that cannot be persisted fails before endpoint verification")
    func renewalPersistenceFailureStopsBeforeAuthentication() async throws {
        let initial = try browserCredential(
            accessToken: "synthetic-expired-access",
            accessExpiresAt: Date(timeIntervalSince1970: 0)
        )
        let refreshed = try browserCredential(
            accessToken: "synthetic-refreshed-access",
            accessExpiresAt: Date(timeIntervalSince1970: 20_000)
        )
        let authentication = RecordingAuthenticationVerifier(
            response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)
        )
        let diagnostics = RecordingDiagnostics()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(credential: initial),
            authenticationVerifier: authentication,
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: FailingCredentialStore(),
            credentialRefresher: RecordingCredentialRefresher(result: refreshed),
            clock: FixedSessionClock(),
            diagnostics: diagnostics
        )

        #expect(await coordinator.attemptSession() == .credentialPersistenceFailed)
        #expect(await authentication.callCount == 0)
        #expect(await diagnostics.events == [.credentialPersistenceFailed])
    }

    @Test("an expiring stored credential without a renewal is reported distinctly")
    func reportsUnavailableCredentialBeforeAuthentication() async throws {
        let expired = try browserCredential(
            accessToken: "synthetic-expired-access",
            accessExpiresAt: Date(timeIntervalSince1970: 0)
        )
        let diagnostics = RecordingDiagnostics()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(credential: expired),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: RecordingCredentialStore(),
            credentialRefresher: RecordingCredentialRefresher(result: nil),
            clock: FixedSessionClock(),
            diagnostics: diagnostics
        )

        #expect(await coordinator.attemptSession() == .authentication(.credentialUnavailable))
        #expect(await diagnostics.events == [.authentication(.credentialUnavailable)])
    }

    @Test("overlapping active operations share one browser renewal")
    func activeOperationsSingleFlightRenewal() async throws {
        let initial = try browserCredential(
            accessToken: "synthetic-current-access",
            accessExpiresAt: Date(timeIntervalSince1970: 10_000)
        )
        let refreshed = try browserCredential(
            accessToken: "synthetic-single-flight-access",
            accessExpiresAt: Date(timeIntervalSince1970: 30_000)
        )
        let clock = MutableSessionClock(Date(timeIntervalSince1970: 1))
        let refresher = BlockingCredentialRefresher(result: refreshed)
        let entitlement = SequencedEntitlementVerifier([
            response(body: SanitizedNativeResponseFixtures.subscriptionV1Active),
            response(body: SanitizedNativeResponseFixtures.subscriptionV1Active),
            response(body: SanitizedNativeResponseFixtures.subscriptionV1Active),
        ])
        let store = RecordingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(credential: initial),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: entitlement,
            credentialStore: store,
            credentialRefresher: refresher,
            clock: clock,
            diagnostics: RecordingDiagnostics()
        )

        #expect(await coordinator.attemptSession() == .active)
        clock.set(Date(timeIntervalSince1970: 10_000))

        let first = Task { await coordinator.withCurrentEntitledCredential { _ in "first" } }
        await refresher.waitUntilStarted()
        let second = Task { await coordinator.withCurrentEntitledCredential { _ in "second" } }
        await Task.yield()
        await refresher.release()

        guard case let .completed(firstValue) = await first.value,
              case let .completed(secondValue) = await second.value else {
            Issue.record("Expected both operations to share and survive one renewal")
            return
        }
        #expect(Set([firstValue, secondValue]) == Set(["first", "second"]))
        #expect(await refresher.refreshCount == 1)
        #expect(await store.saveCount == 2)
    }

    @Test("authentication success does not publish a session before entitlement")
    func holdsActiveSessionUntilEntitlementSucceeds() async {
        let entitlement = BlockingEntitlementVerifier()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: entitlement,
            credentialStore: RecordingCredentialStore(),
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        let attempt = Task { await coordinator.attemptSession() }
        await entitlement.waitUntilStarted()

        #expect(await coordinator.snapshot == .verifyingEntitlement)

        await entitlement.release(with: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active))
        #expect(await attempt.value == .active)
        guard case .active = await coordinator.snapshot else {
            Issue.record("Expected an active session only after entitlement")
            return
        }
    }

    @Test("unentitled and terminal outcomes do not persist or retain a session")
    func doesNotPersistBeforeAConfirmedEntitlement() async {
        let store = RecordingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Inactive)),
            credentialStore: store,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        #expect(await coordinator.attemptSession() == .entitlement(.authenticatedButNotEntitled))
        #expect(await coordinator.snapshot == .signedOut)
        #expect(await store.saveCount == 0)
    }

    @Test("profile authorization rejection short-circuits entitlement and persistence")
    func profileAuthorizationRejectionNeverContinues() async {
        for (statusCode, diagnostic) in [(401, SafeDiagnosticOutcome.httpUnauthorized), (403, .httpForbidden)] {
            let entitlement = RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active))
            let store = RecordingCredentialStore()
            let diagnostics = RecordingDiagnostics()
            let coordinator = SessionCoordinator(
                credentialSource: RecordingCredentialSource(),
                authenticationVerifier: RecordingAuthenticationVerifier(
                    response: NativeTransportResponse(statusCode: statusCode, contentType: "application/json", body: Data())
                ),
                entitlementVerifier: entitlement,
                credentialStore: store,
                clock: FixedSessionClock(),
                diagnostics: diagnostics
            )

            #expect(await coordinator.attemptSession() == .authentication(.rejected))
            #expect(await entitlement.callCount == 0)
            #expect(await store.saveCount == 0)
            #expect(await diagnostics.events == [.authentication(diagnostic)])
        }
    }

    @Test("entitlement authorization rejection short-circuits persistence")
    func entitlementAuthorizationRejectionNeverPersists() async {
        for (statusCode, diagnostic) in [(401, SafeDiagnosticOutcome.httpUnauthorized), (403, .httpForbidden)] {
            let store = RecordingCredentialStore()
            let diagnostics = RecordingDiagnostics()
            let coordinator = SessionCoordinator(
                credentialSource: RecordingCredentialSource(),
                authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
                entitlementVerifier: RecordingEntitlementVerifier(
                    response: NativeTransportResponse(statusCode: statusCode, contentType: "application/json", body: Data())
                ),
                credentialStore: store,
                clock: FixedSessionClock(),
                diagnostics: diagnostics
            )

            #expect(await coordinator.attemptSession() == .entitlement(.rejected))
            #expect(await store.saveCount == 0)
            #expect(await diagnostics.events == [.authentication(.completed), .entitlement(diagnostic)])
        }
    }

    @Test("persistence failure is terminal and never publishes an active session")
    func persistenceFailureDoesNotProduceActiveSession() async {
        let diagnostics = RecordingDiagnostics()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: FailingCredentialStore(),
            clock: FixedSessionClock(),
            diagnostics: diagnostics
        )

        let client = SiriusXMClient(sessionCoordinator: coordinator)

        #expect(await client.authenticate() == .credentialPersistenceFailed)
        #expect(await coordinator.snapshot == .signedOut)
        #expect(await diagnostics.events == [
            .authentication(.completed),
            .entitlement(.completed),
            .credentialPersistenceFailed,
        ])
    }

    @Test("cancellation while persistence is pending cannot publish an active session")
    func cancellationBeforePersistenceCompletesNeverPublishesActiveSession() async {
        let store = BlockingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: store,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        let attempt = Task { await coordinator.attemptSession() }
        await store.waitUntilSaveStarted()
        attempt.cancel()
        await store.releaseSave()

        #expect(await attempt.value == .authentication(.cancelled))
        #expect(await coordinator.snapshot == .signedOut)
    }

    @Test("parallel attempts are rejected before collaborator work")
    func rejectsParallelAttemptsAndClearsCancelledTransientState() async {
        let authentication = BlockingAuthenticationVerifier()
        let source = RecordingCredentialSource()
        let store = RecordingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: source,
            authenticationVerifier: authentication,
            entitlementVerifier: RecordingEntitlementVerifier(response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: store,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        let first = Task { await coordinator.attemptSession() }
        await authentication.waitUntilStarted()
        #expect(await coordinator.attemptSession() == .attemptInProgress)

        first.cancel()
        await authentication.release(with: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated))
        #expect(await first.value == .authentication(.cancelled))
        #expect(await coordinator.snapshot == .signedOut)
        #expect(await source.requestCount == 1)
        #expect(await store.saveCount == 0)
    }

    @Test("session diagnostics preserve the safe native failure reason")
    func recordsSafeFailureReason() async {
        let diagnostics = RecordingDiagnostics()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(),
            authenticationVerifier: RecordingAuthenticationVerifier(
                response: NativeTransportResponse(
                    statusCode: 200,
                    contentType: "application/json",
                    body: Data()
                )
            ),
            entitlementVerifier: RecordingEntitlementVerifier(
                response: response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)
            ),
            credentialStore: RecordingCredentialStore(),
            clock: FixedSessionClock(),
            diagnostics: diagnostics
        )

        #expect(await coordinator.attemptSession() == .authentication(.unsupported))
        #expect(await diagnostics.events == [.authentication(.payloadEmpty)])
    }

    @Test("ordinary current-session revalidation failures preserve the active credential")
    func preservesActiveSessionAcrossClosedOperationFailures() async {
        let failures: [(NativeTransportResponse, LiveStreamResolutionFailure)] = [
            (NativeTransportResponse(statusCode: 400, contentType: "application/json", body: Data()), .entitlementUnavailable),
            (NativeTransportResponse(statusCode: 429, contentType: "application/json", body: Data()), .protectedControl),
            (NativeTransportResponse(statusCode: 200, contentType: "application/json", body: Data(#"{"challenge":"control"}"#.utf8)), .protectedControl),
            (NativeTransportResponse(statusCode: 200, contentType: "application/json", body: Data(), redirectLocation: "fixture-redirect"), .protectedControl),
            (NativeTransportResponse(statusCode: 200, contentType: "application/json", body: Data(), transportFailure: .other), .networkUnavailable),
            (NativeTransportResponse(statusCode: 200, contentType: "application/json", body: Data("not-json".utf8)), .entitlementUnavailable),
        ]

        for (failureResponse, expectedFailure) in failures {
            let source = RecordingCredentialSource()
            let entitlement = SequencedEntitlementVerifier([
                response(body: SanitizedNativeResponseFixtures.subscriptionV1Active),
                failureResponse,
                response(body: SanitizedNativeResponseFixtures.subscriptionV1Active),
            ])
            let store = RecordingCredentialStore()
            let coordinator = SessionCoordinator(
                credentialSource: source,
                authenticationVerifier: RecordingAuthenticationVerifier(response: response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)),
                entitlementVerifier: entitlement,
                credentialStore: store,
                clock: FixedSessionClock(),
                diagnostics: RecordingDiagnostics()
            )

            #expect(await coordinator.attemptSession() == .active)
            let activeSnapshot = await coordinator.snapshot

            let failed = await coordinator.withCurrentEntitledCredential { _ in "unexpected" }
            guard case let .failed(actualFailure) = failed else {
                Issue.record("Expected a closed operation failure")
                continue
            }
            #expect(actualFailure == expectedFailure)
            #expect(await coordinator.snapshot == activeSnapshot)

            let reused = await coordinator.withCurrentEntitledCredential { _ in "reused" }
            guard case let .completed(value) = reused else {
                Issue.record("Expected the preserved active session to support a later operation")
                continue
            }
            #expect(value == "reused")
            #expect(await source.requestCount == 1)
            #expect(await store.eraseCount == 0)
        }
    }

    private func response(body: Data) -> NativeTransportResponse {
        return NativeTransportResponse(statusCode: 200, contentType: "application/json", body: body)
    }
}

private actor RecordingCredentialSource: CredentialSource {
    private let supplied: AuthenticationCredential
    private(set) var requestCount = 0

    init(credential: AuthenticationCredential = AuthenticationCredential(volatileMaterial: Data("credential".utf8))) {
        supplied = credential
    }

    func credential() async -> AuthenticationCredential? {
        requestCount += 1
        return supplied
    }
}

private actor CredentialRecordingAuthenticationVerifier: NativeAuthenticationVerifying {
    private let response: NativeTransportResponse
    private(set) var lastAccessToken: String?

    init(response: NativeTransportResponse) {
        self.response = response
    }

    func verifyAuthentication(using credential: AuthenticationCredential) async -> NativeTransportResponse {
        lastAccessToken = credential.accessToken()
        return response
    }
}

private actor RecordingCredentialRefresher: CredentialRefresher {
    private let result: AuthenticationCredential?
    private(set) var refreshCount = 0

    init(result: AuthenticationCredential?) {
        self.result = result
    }

    func refreshedCredential(ifNeeded credential: AuthenticationCredential) async -> AuthenticationCredential? {
        refreshCount += 1
        return result
    }
}

#if DEBUG
private actor SequencedCredentialRefresher: CredentialRefresher {
    private var results: [AuthenticationCredential]
    private(set) var refreshCount = 0

    init(_ results: [AuthenticationCredential]) {
        self.results = results
    }

    func refreshedCredential(ifNeeded credential: AuthenticationCredential) async -> AuthenticationCredential? {
        credential
    }

    func refreshedCredentialForQualification(_: AuthenticationCredential) async -> AuthenticationCredential? {
        refreshCount += 1
        guard !results.isEmpty else { return nil }
        return results.removeFirst()
    }
}
#endif

private actor BlockingCredentialRefresher: CredentialRefresher {
    private let result: AuthenticationCredential
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var refreshCount = 0

    init(result: AuthenticationCredential) {
        self.result = result
    }

    func refreshedCredential(ifNeeded credential: AuthenticationCredential) async -> AuthenticationCredential? {
        refreshCount += 1
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return result
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor VerificationSequence {
    enum Event: Sendable, Equatable { case authentication, entitlement }
    private(set) var events: [Event] = []

    func append(_ event: Event) { events.append(event) }
}

private actor RecordingAuthenticationVerifier: NativeAuthenticationVerifying {
    private let sequence: VerificationSequence?
    private let response: NativeTransportResponse
    private(set) var callCount = 0

    init(sequence: VerificationSequence? = nil, response: NativeTransportResponse) {
        self.sequence = sequence
        self.response = response
    }

    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        callCount += 1
        await sequence?.append(.authentication)
        return response
    }
}

private actor RecordingEntitlementVerifier: NativeEntitlementVerifying {
    private let sequence: VerificationSequence?
    private let response: NativeTransportResponse
    private(set) var callCount = 0

    init(sequence: VerificationSequence? = nil, response: NativeTransportResponse) {
        self.sequence = sequence
        self.response = response
    }

    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        callCount += 1
        await sequence?.append(.entitlement)
        return response
    }
}

private actor SequencedEntitlementVerifier: NativeEntitlementVerifying {
    private var responses: [NativeTransportResponse]

    init(_ responses: [NativeTransportResponse]) {
        self.responses = responses
    }

    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        responses.removeFirst()
    }
}

private actor BlockingAuthenticationVerifier: NativeAuthenticationVerifying {
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<NativeTransportResponse, Never>?
    private var started = false

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

    func release(with response: NativeTransportResponse) {
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
    }
}

private actor BlockingEntitlementVerifier: NativeEntitlementVerifying {
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<NativeTransportResponse, Never>?
    private var started = false

    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release(with response: NativeTransportResponse) {
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
    }
}

private actor RecordingCredentialStore: CredentialStore {
    private(set) var saveCount = 0
    private(set) var eraseCount = 0

    func save(_: AuthenticationCredential) async throws { saveCount += 1 }
    func erase() async throws { eraseCount += 1 }
}

private actor FailingCredentialStore: CredentialStore {
    func save(_: AuthenticationCredential) async throws {
        throw FixtureStoreError.saveFailed
    }

    func erase() async throws {}
}

private actor BlockingCredentialStore: CredentialStore {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var saveWaiter: CheckedContinuation<Void, Never>?

    func save(_: AuthenticationCredential) async throws {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { saveWaiter = $0 }
    }

    func erase() async throws {}

    func waitUntilSaveStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func releaseSave() {
        saveWaiter?.resume()
        saveWaiter = nil
    }
}

private enum FixtureStoreError: Error {
    case saveFailed
}

private struct FixedSessionClock: SessionClock {
    func now() -> Date { Date(timeIntervalSince1970: 1) }
}

private final class MutableSessionClock: SessionClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.withLock { date }
    }

    func set(_ date: Date) {
        lock.withLock { self.date = date }
    }
}

private actor RecordingDiagnostics: SessionDiagnostics {
    private(set) var events: [SessionDiagnosticEvent] = []

    func record(_ event: SessionDiagnosticEvent) async {
        events.append(event)
    }
}
