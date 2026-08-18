import Foundation
import WebKit
import XCTest
import SiriusXMClient
@testable import SiriusMac

@MainActor
final class SelectedAuthenticationCompositionTests: XCTestCase {
    func testLoggedInSessionUsesBridgeThenNativeClientInOrder() async throws {
        let now = Date()
        let bridge = WebAuthenticationBridge(
            cookieStore: CompositionCookieStore(cookies: [try tokenCookie(expires: now.addingTimeInterval(60))]),
            now: { now },
            credentialConsumer: { _ in }
        )
        let client = CompositionClient()
        let flow = ComposedAuthenticationPresentationFlow(bridge: bridge, client: client)
        var enteredEntitlementVerification = 0

        let state = await flow.useLoggedInSession {
            enteredEntitlementVerification += 1
        }

        XCTAssertEqual(state, .entitled)
        XCTAssertEqual(enteredEntitlementVerification, 1)
        let events = await client.events
        XCTAssertEqual(events, [.authenticate, .entitlement])
    }

    func testTerminalBridgeAndClientResultsDoNotOfferFallbackOrRetry() async {
        let bridge = WebAuthenticationBridge(
            cookieStore: CompositionCookieStore(cookies: []),
            credentialConsumer: { _ in }
        )
        let client = CompositionClient(authentication: .rejected, entitlement: .unavailable)
        let flow = ComposedAuthenticationPresentationFlow(bridge: bridge, client: client)

        let state = await flow.useLoggedInSession {}
        let events = await client.events

        XCTAssertEqual(state, .unsupported)
        XCTAssertEqual(events, [])
    }

    func testExplicitRetryAfterTerminalClientResultStartsOneFreshNativeTransaction() async throws {
        let now = Date()
        let store = CompositionCookieStore(cookies: [try tokenCookie(expires: now.addingTimeInterval(60))])
        let bridge = WebAuthenticationBridge(cookieStore: store, now: { now }, credentialConsumer: { _ in })
        let client = CompositionClient(
            authentications: [.rejected, .authenticatedPendingEntitlement],
            entitlements: [.entitled]
        )
        let model = AuthenticationPresentationModel(
            flow: ComposedAuthenticationPresentationFlow(bridge: bridge, client: client)
        )

        try await XCTUnwrap(model.signIn()).value
        try await XCTUnwrap(model.useLoggedInSession()).value
        XCTAssertEqual(model.state, .rejected)
        let terminalEvents = await client.events
        XCTAssertEqual(terminalEvents, [.authenticate])

        try await XCTUnwrap(model.retry()).value
        try await XCTUnwrap(model.useLoggedInSession()).value

        XCTAssertEqual(model.state, .entitled)
        let retriedEvents = await client.events
        XCTAssertEqual(retriedEvents, [.authenticate, .authenticate, .entitlement])
    }

    func testExplicitNewLoginAfterSignOutTransfersOneFreshCredential() async throws {
        let now = Date()
        let store = CompositionCookieStore(cookies: [try tokenCookie(expires: now.addingTimeInterval(60))])
        let bridge = WebAuthenticationBridge(cookieStore: store, now: { now }, credentialConsumer: { _ in })
        let client = CompositionClient(
            authentications: [.authenticatedPendingEntitlement, .authenticatedPendingEntitlement],
            entitlements: [.entitled, .entitled]
        )
        let model = AuthenticationPresentationModel(
            flow: ComposedAuthenticationPresentationFlow(bridge: bridge, client: client)
        )

        try await XCTUnwrap(model.signIn()).value
        try await XCTUnwrap(model.useLoggedInSession()).value
        XCTAssertEqual(model.state, .entitled)
        try await XCTUnwrap(model.signOut()).value
        XCTAssertEqual(model.state, .signedOut)

        store.replaceCookies(with: [try tokenCookie(expires: now.addingTimeInterval(60))])
        try await XCTUnwrap(model.signIn()).value
        try await XCTUnwrap(model.useLoggedInSession()).value

        XCTAssertEqual(model.state, .entitled)
        let events = await client.events
        XCTAssertEqual(events, [.authenticate, .entitlement, .signOut, .authenticate, .entitlement])
    }

    func testFreshCompositionClearsSyntheticKeychainAndBrowserResidueWithoutAuthentication() async throws {
        let now = Date()
        let keychain = KeychainCredentialStore(
            service: "com.siriusmac.tests.\(UUID().uuidString)",
            account: "fresh-cleanup"
        )
        let credential = AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))
        try await keychain.save(credential)
        defer { try? keychain.removeStoredCredential() }

        let cookieStore = CompositionCookieStore(cookies: [try tokenCookie(expires: now.addingTimeInterval(60))])
        let bridge = WebAuthenticationBridge(cookieStore: cookieStore, now: { now }, credentialConsumer: { _ in })
        let client = SiriusXMClient(credentialSource: bridge, credentialStore: keychain, residueCleaner: bridge)
        let model = AuthenticationPresentationModel(
            flow: ComposedAuthenticationPresentationFlow(bridge: bridge, client: client)
        )

        let clearTask = try XCTUnwrap(model.clearLocalSession())
        await clearTask.value

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(try keychain.readStoredCredential())
        let remainingCookies = await cookieStore.allCookies()
        XCTAssertTrue(remainingCookies.isEmpty)
    }

    func testFreshCleanupFailureStaysSignedOutAndAllowsAnExplicitRetry() async throws {
        let client = CompositionClient(signOut: .cleanupFailed(.browserResidue))
        let bridge = WebAuthenticationBridge(cookieStore: CompositionCookieStore(cookies: []), credentialConsumer: { _ in })
        let model = AuthenticationPresentationModel(
            flow: ComposedAuthenticationPresentationFlow(bridge: bridge, client: client)
        )

        let cleanupTask = try XCTUnwrap(model.clearLocalSession())
        await cleanupTask.value

        XCTAssertEqual(model.state, .cleanupFailed(.browserResidue))
        let retryTask = try XCTUnwrap(model.clearLocalSession())
        await retryTask.value
        let events = await client.events
        XCTAssertEqual(events, [.signOut, .signOut])
    }

    private func tokenCookie(expires: Date) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [
            .name: "AUTH_TOKEN",
            .value: #"{"session":{"accessToken":"synthetic-access-token"}}"#.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!,
            .domain: "siriusxm.com",
            .path: "/",
            .expires: expires,
            .secure: "TRUE",
        ]))
    }
}

private actor CompositionClient: ClientAuthenticationFlow {
    enum Event: Equatable { case authenticate, entitlement, signOut }

    private var authentications: [AuthenticationOutcome]
    private var entitlements: [EntitlementAvailability]
    private let signOutResult: SignOutOutcome
    private(set) var events: [Event] = []

    init(
        authentication: AuthenticationOutcome = .authenticatedPendingEntitlement,
        entitlement: EntitlementAvailability = .entitled,
        signOut: SignOutOutcome = .signedOut
    ) {
        authentications = [authentication]
        entitlements = [entitlement]
        signOutResult = signOut
    }

    init(authentications: [AuthenticationOutcome], entitlements: [EntitlementAvailability]) {
        self.authentications = authentications
        self.entitlements = entitlements
        signOutResult = .signedOut
    }

    func authenticate() async -> AuthenticationOutcome {
        events.append(.authenticate)
        return authentications.isEmpty ? .unsupported : authentications.removeFirst()
    }

    func entitlementAvailability() async -> EntitlementAvailability {
        events.append(.entitlement)
        return entitlements.isEmpty ? .unavailable : entitlements.removeFirst()
    }

    func signOut() async -> SignOutOutcome {
        events.append(.signOut)
        return signOutResult
    }
}

@MainActor
private final class CompositionCookieStore: WebAuthenticationCookieStore {
    private var cookies: [HTTPCookie]

    init(cookies: [HTTPCookie]) { self.cookies = cookies }

    func allCookies() async -> [HTTPCookie] { cookies }
    func delete(_ cookie: HTTPCookie) async throws { cookies.removeAll { $0 === cookie } }
    func replaceCookies(with cookies: [HTTPCookie]) { self.cookies = cookies }
}
