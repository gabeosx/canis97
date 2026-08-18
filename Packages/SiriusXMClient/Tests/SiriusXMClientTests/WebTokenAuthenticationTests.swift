import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Web token native authentication")
struct WebTokenAuthenticationTests {
    @Test("multi-field native responses publish one active session after entitlement")
    func authenticatesWithOneRuntimeOwnedTransaction() async {
        let source = WebTokenCredentialSource()
        let sequence = WebTokenVerificationSequence()
        let store = WebTokenCredentialStore()
        let coordinator = SessionCoordinator(
            credentialSource: source,
            authenticationVerifier: WebTokenAuthenticationVerifier(sequence: sequence, response: response(SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: WebTokenEntitlementVerifier(sequence: sequence, response: response(SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: store,
            clock: WebTokenFixedClock(),
            diagnostics: WebTokenDiagnostics()
        )
        let client = SiriusXMClient(sessionCoordinator: coordinator)

        #expect(await client.authenticate() == .authenticatedPendingEntitlement)
        #expect(await client.entitlement() == .entitled)
        #expect(await sequence.events == [.authentication, .entitlement])
        #expect(await source.requestCount == 1)
        #expect(await store.saveCount == 1)
        guard case .active = await coordinator.snapshot else {
            Issue.record("Expected the coordinator to publish one active session")
            return
        }
    }

    @Test("unentitled and terminal native results leave no active state or persistence")
    func failsClosedWithoutEntitlementOrOnTerminalAuthentication() async {
        let unentitledStore = WebTokenCredentialStore()
        let unentitled = SiriusXMClient(sessionCoordinator: SessionCoordinator(
            credentialSource: WebTokenCredentialSource(),
            authenticationVerifier: WebTokenAuthenticationVerifier(response: response(SanitizedNativeResponseFixtures.profileV4Authenticated)),
            entitlementVerifier: WebTokenEntitlementVerifier(response: response(SanitizedNativeResponseFixtures.subscriptionV1Inactive)),
            credentialStore: unentitledStore,
            clock: WebTokenFixedClock(),
            diagnostics: WebTokenDiagnostics()
        ))

        #expect(await unentitled.authenticate() == .authenticatedPendingEntitlement)
        #expect(await unentitled.entitlement() == .authenticatedButNotEntitled)
        #expect(await unentitledStore.saveCount == 0)

        let rejectedStore = WebTokenCredentialStore()
        let rejected = SiriusXMClient(sessionCoordinator: SessionCoordinator(
            credentialSource: WebTokenCredentialSource(),
            authenticationVerifier: WebTokenAuthenticationVerifier(response: response(SanitizedNativeResponseFixtures.profileV4Authenticated, statusCode: 403)),
            entitlementVerifier: WebTokenEntitlementVerifier(response: response(SanitizedNativeResponseFixtures.subscriptionV1Active)),
            credentialStore: rejectedStore,
            clock: WebTokenFixedClock(),
            diagnostics: WebTokenDiagnostics()
        ))

        #expect(await rejected.authenticate() == .rejected)
        #expect(await rejected.entitlement() == .unavailable)
        #expect(await rejectedStore.saveCount == 0)
    }

    private func response(_ body: Data, statusCode: Int = 200) -> NativeTransportResponse {
        NativeTransportResponse(
            statusCode: statusCode,
            contentType: "application/json",
            body: body
        )
    }
}

private actor WebTokenCredentialSource: CredentialSource {
    private(set) var requestCount = 0

    func credential() -> AuthenticationCredential? {
        requestCount += 1
        return AuthenticationCredential(volatileMaterial: Data("web-token".utf8))
    }
}

private actor WebTokenVerificationSequence {
    enum Event: Sendable, Equatable { case authentication, entitlement }
    private(set) var events: [Event] = []

    func append(_ event: Event) { events.append(event) }
}

private actor WebTokenAuthenticationVerifier: NativeAuthenticationVerifying {
    private let sequence: WebTokenVerificationSequence?
    private let response: NativeTransportResponse

    init(sequence: WebTokenVerificationSequence? = nil, response: NativeTransportResponse) {
        self.sequence = sequence
        self.response = response
    }

    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        await sequence?.append(.authentication)
        return response
    }
}

private actor WebTokenEntitlementVerifier: NativeEntitlementVerifying {
    private let sequence: WebTokenVerificationSequence?
    private let response: NativeTransportResponse

    init(sequence: WebTokenVerificationSequence? = nil, response: NativeTransportResponse) {
        self.sequence = sequence
        self.response = response
    }

    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        await sequence?.append(.entitlement)
        return response
    }
}

private actor WebTokenCredentialStore: CredentialStore {
    private(set) var saveCount = 0

    func save(_: AuthenticationCredential) async throws { saveCount += 1 }
    func erase() async throws {}
}

private struct WebTokenFixedClock: SessionClock {
    func now() -> Date { Date(timeIntervalSince1970: 1) }
}

private actor WebTokenDiagnostics: SessionDiagnostics {
    func record(_: SessionDiagnosticEvent) async {}
}
