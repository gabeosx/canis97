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

    func testSignOutDeletesEveryExactApexAndSubdomainMatchThenRescans() async throws {
        let now = Date()
        let store = TestCookieStore(cookies: [
            try authCookie(domain: "siriusxm.com", expires: now.addingTimeInterval(60)),
            try authCookie(domain: "player.siriusxm.com", expires: now.addingTimeInterval(60)),
            try authCookie(domain: "evil-siriusxm.com", expires: now.addingTimeInterval(60)),
        ])
        let bridge = WebAuthenticationBridge(cookieStore: store, now: { now }, credentialConsumer: { _ in })

        let result = await bridge.removeAuthenticationResidue()
        let remainingCookies = await store.allCookies()

        XCTAssertEqual(result, .removed)
        XCTAssertEqual(store.deletedCount, 2)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: remainingCookies, now: now), .missing)
    }

    func testSignOutFailsClosedWhenDeletionFailsOrAMatchingCookieRemains() async throws {
        let now = Date()
        let token = try authCookie(domain: "player.siriusxm.com", expires: now.addingTimeInterval(60))
        let deleteFailureStore = TestCookieStore(cookies: [token], deleteFailure: true)
        let staleStore = TestCookieStore(cookies: [token], retainDeletedCookies: true)

        let deleteFailure = await WebAuthenticationBridge(cookieStore: deleteFailureStore, now: { now }, credentialConsumer: { _ in }).removeAuthenticationResidue()
        let staleResult = await WebAuthenticationBridge(cookieStore: staleStore, now: { now }, credentialConsumer: { _ in }).removeAuthenticationResidue()

        XCTAssertEqual(deleteFailure, .cleanupFailed)
        XCTAssertEqual(staleResult, .cleanupFailed)
    }

    func testBridgeAndTestsAreUnconditionallyIncludedWithoutPlanningArtifactChecks() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("SiriusMac.xcodeproj/project.pbxproj"), encoding: .utf8)
        let testSource = try String(contentsOf: root.appendingPathComponent("SiriusMacTests/WebAuthenticationBridgeTests.swift"), encoding: .utf8)

        XCTAssertTrue(project.contains("WebAuthenticationBridge.swift in Sources"))
        XCTAssertTrue(project.contains("WebAuthenticationBridgeTests.swift in Sources"))
        let planningDirectory = "." + "planning"
        XCTAssertFalse(project.contains(planningDirectory))
        let excludedImport = "can" + "Import(AuthFeasibilityHarness)"
        XCTAssertFalse(testSource.contains(excludedImport))
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
    private var cookies: [HTTPCookie]
    private let deleteFailure: Bool
    private let retainDeletedCookies: Bool
    private(set) var readCount = 0
    private(set) var deletedCount = 0

    init(cookies: [HTTPCookie], deleteFailure: Bool = false, retainDeletedCookies: Bool = false) {
        self.cookies = cookies
        self.deleteFailure = deleteFailure
        self.retainDeletedCookies = retainDeletedCookies
    }

    func allCookies() async -> [HTTPCookie] {
        readCount += 1
        return cookies
    }

    func delete(_ cookie: HTTPCookie) async throws {
        if deleteFailure { throw TestCookieStoreError.deleteFailed }
        deletedCount += 1
        if !retainDeletedCookies {
            cookies.removeAll { $0 === cookie }
        }
    }
}

private enum TestCookieStoreError: Error {
    case deleteFailed
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
