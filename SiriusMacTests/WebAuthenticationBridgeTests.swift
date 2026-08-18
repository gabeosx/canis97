import Foundation
import WebKit
import XCTest
import SiriusXMClient
@testable import SiriusMac

@MainActor
final class WebAuthenticationBridgeTests: XCTestCase {
    func testCreatesOnlyANonPersistentWebViewStoreAndDoesNotReadCookiesBeforeConsent() {
        let store = TestCookieStore(cookies: [])
        let bridge = WebAuthenticationBridge(cookieStore: store, credentialConsumer: { _ in })

        XCTAssertFalse(bridge.webViewConfiguration.websiteDataStore.isPersistent)
        XCTAssertEqual(store.readCount, 0)
    }

    func testExplicitConsentAcceptsOneCurrentApexOrBoundaryCorrectSubdomainToken() async throws {
        let recorder = CredentialRecorder()
        let now = Date()
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: [try authCookie(domain: ".player.siriusxm.com", expires: now.addingTimeInterval(60))]),
            now: { now },
            credentialConsumer: { credential in await recorder.record(credential) }
        )

        let result = await bridge.useLoggedInSession()
        let repeatedResult = await bridge.useLoggedInSession()
        let snapshot = await recorder.snapshot()

        XCTAssertEqual(result, .credentialTransferred)
        XCTAssertEqual(repeatedResult, .alreadyConsumed)
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.descriptions, ["AuthenticationCredential(redacted)"])
    }

    func testMissingMultipleExpiredLookalikeAndUnsupportedCookiesFailClosed() throws {
        let now = Date()
        let valid = try authCookie(domain: "siriusxm.com", expires: now.addingTimeInterval(60))
        let expired = try authCookie(domain: "siriusxm.com", expires: now.addingTimeInterval(-60))
        let lookalike = try authCookie(domain: "evil-siriusxm.com", expires: now.addingTimeInterval(60))
        let unsupportedPath = try authCookie(domain: "siriusxm.com", path: "/account", expires: now.addingTimeInterval(60))

        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [], now: now), .missing)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [valid, valid], now: now), .ambiguous)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [expired], now: now), .missing)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [lookalike], now: now), .missing)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [unsupportedPath], now: now), .missing)
    }

    func testMalformedOrIncompletePayloadProducesATerminalResult() async throws {
        let now = Date()
        let malformed = try authCookie(value: "not-json", expires: now.addingTimeInterval(60))
        let incomplete = try authCookie(value: #"{"session":{}}"#, expires: now.addingTimeInterval(60))

        let malformedBridge = WebAuthenticationBridge(cookieStore: TestCookieStore(cookies: [malformed]), now: { now }, credentialConsumer: { _ in })
        let incompleteBridge = WebAuthenticationBridge(cookieStore: TestCookieStore(cookies: [incomplete]), now: { now }, credentialConsumer: { _ in })

        let malformedResult = await malformedBridge.useLoggedInSession()
        let incompleteResult = await incompleteBridge.useLoggedInSession()

        XCTAssertEqual(malformedResult, .malformedCredential)
        XCTAssertEqual(incompleteResult, .malformedCredential)
    }

    private func authCookie(
        value: String = #"{"session":{"accessToken":"synthetic-access-token"}}"#,
        domain: String = "siriusxm.com",
        path: String = "/",
        expires: Date
    ) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [
            .name: "AUTH_TOKEN",
            .value: value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value,
            .domain: domain,
            .path: path,
            .expires: expires,
            .secure: "TRUE",
        ]))
    }
}

@MainActor
private final class TestCookieStore: WebAuthenticationCookieStore {
    private let cookies: [HTTPCookie]
    private(set) var readCount = 0

    init(cookies: [HTTPCookie]) {
        self.cookies = cookies
    }

    func allCookies() async -> [HTTPCookie] {
        readCount += 1
        return cookies
    }

    func delete(_ cookie: HTTPCookie) async throws {}
}

private actor CredentialRecorder {
    private(set) var count = 0
    private(set) var descriptions: [String] = []

    func record(_ credential: AuthenticationCredential) {
        count += 1
        descriptions.append(credential.description)
    }

    func snapshot() -> (count: Int, descriptions: [String]) {
        (count, descriptions)
    }
}
