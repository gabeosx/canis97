import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Session coordinator")
struct SessionCoordinatorTests {
    @Test("one attempt consumes one credential and verifies in order")
    func performsAuthenticationThenEntitlementOnce() async {
        let source = RecordingCredentialSource()
        let sequence = VerificationSequence()
        let authentication = RecordingAuthenticationVerifier(sequence: sequence, response: response(object: ["authenticated": true]))
        let entitlement = RecordingEntitlementVerifier(sequence: sequence, response: response(object: ["entitled": true]))
        let store = RecordingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: source,
            authenticationVerifier: authentication,
            entitlementVerifier: entitlement,
            credentialStore: store,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        #expect(await coordinator.attemptSession() == .active)
        #expect(await source.requestCount == 1)
        #expect(await authentication.callCount == 1)
        #expect(await entitlement.callCount == 1)
        #expect(await sequence.events == [.authentication, .entitlement])
        #expect(await store.saveCount == 1)
    }

    @Test("authentication success does not publish a session before entitlement")
    func holdsActiveSessionUntilEntitlementSucceeds() async {
        let entitlement = BlockingEntitlementVerifier()
        let coordinator = SessionCoordinator(
            credentialSource: RecordingCredentialSource(),
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(object: ["authenticated": true])),
            entitlementVerifier: entitlement,
            credentialStore: RecordingCredentialStore(),
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        let attempt = Task { await coordinator.attemptSession() }
        await entitlement.waitUntilStarted()

        #expect(await coordinator.snapshot == .verifyingEntitlement)

        await entitlement.release(with: response(object: ["entitled": true]))
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
            authenticationVerifier: RecordingAuthenticationVerifier(response: response(object: ["authenticated": true])),
            entitlementVerifier: RecordingEntitlementVerifier(response: response(object: ["entitled": false])),
            credentialStore: store,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        #expect(await coordinator.attemptSession() == .entitlement(.authenticatedButNotEntitled))
        #expect(await coordinator.snapshot == .signedOut)
        #expect(await store.saveCount == 0)
    }

    @Test("parallel attempts are rejected before collaborator work")
    func rejectsParallelAttemptsAndClearsCancelledTransientState() async {
        let authentication = BlockingAuthenticationVerifier()
        let source = RecordingCredentialSource()
        let store = RecordingCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: source,
            authenticationVerifier: authentication,
            entitlementVerifier: RecordingEntitlementVerifier(response: response(object: ["entitled": true])),
            credentialStore: store,
            clock: FixedSessionClock(),
            diagnostics: RecordingDiagnostics()
        )

        let first = Task { await coordinator.attemptSession() }
        await authentication.waitUntilStarted()
        #expect(await coordinator.attemptSession() == .attemptInProgress)

        first.cancel()
        await authentication.release(with: response(object: ["authenticated": true]))
        #expect(await first.value == .authentication(.cancelled))
        #expect(await coordinator.snapshot == .signedOut)
        #expect(await source.requestCount == 1)
        #expect(await store.saveCount == 0)
    }

    private func response(object: [String: Any]) -> NativeTransportResponse {
        let body = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return NativeTransportResponse(statusCode: 200, contentType: "application/json", body: body)
    }
}

private actor RecordingCredentialSource: CredentialSource {
    private let supplied = AuthenticationCredential(volatileMaterial: Data("credential".utf8))
    private(set) var requestCount = 0

    func credential() async -> AuthenticationCredential? {
        requestCount += 1
        return supplied
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

    func save(_: AuthenticationCredential) async throws { saveCount += 1 }
    func erase() async throws {}
}

private struct FixedSessionClock: SessionClock {
    func now() -> Date { Date(timeIntervalSince1970: 1) }
}

private actor RecordingDiagnostics: SessionDiagnostics {
    func record(_: SessionDiagnosticEvent) async {}
}
