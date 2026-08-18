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
        XCTAssertEqual(await client.events, [.authenticate, .entitlement])
    }

    func testTerminalBridgeAndClientResultsDoNotOfferFallbackOrRetry() async {
        let bridge = WebAuthenticationBridge(
            cookieStore: CompositionCookieStore(cookies: []),
            credentialConsumer: { _ in }
        )
        let client = CompositionClient(authentication: .rejected, entitlement: .unavailable)
        let flow = ComposedAuthenticationPresentationFlow(bridge: bridge, client: client)

        XCTAssertEqual(await flow.useLoggedInSession {}, .unsupported)
        XCTAssertEqual(await client.events, [])
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
    enum Event: Equatable { case authenticate, entitlement }

    private let authentication: AuthenticationOutcome
    private let entitlement: EntitlementAvailability
    private(set) var events: [Event] = []

    init(
        authentication: AuthenticationOutcome = .authenticatedPendingEntitlement,
        entitlement: EntitlementAvailability = .entitled
    ) {
        self.authentication = authentication
        self.entitlement = entitlement
    }

    func authenticate() async -> AuthenticationOutcome {
        events.append(.authenticate)
        return authentication
    }

    func entitlementAvailability() async -> EntitlementAvailability {
        events.append(.entitlement)
        return entitlement
    }

    func signOut() async -> SignOutOutcome { .signedOut }
}

@MainActor
private final class CompositionCookieStore: WebAuthenticationCookieStore {
    private var cookies: [HTTPCookie]

    init(cookies: [HTTPCookie]) { self.cookies = cookies }

    func allCookies() async -> [HTTPCookie] { cookies }
    func delete(_ cookie: HTTPCookie) async throws { cookies.removeAll { $0 === cookie } }
}
