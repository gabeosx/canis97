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
        XCTAssertEqual(model.state, .profileAuthorizationRejected)
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

    func testFreshRestoreConsumesOneStoredCredentialBeforeOrderedNativeTransaction() async throws {
        let keychain = KeychainCredentialStore(
            service: "com.siriusmac.tests.\(UUID().uuidString)",
            account: "fresh-restore"
        )
        defer { try? keychain.removeStoredCredential() }
        try await keychain.save(AuthenticationCredential(volatileMaterial: Data("approved-restore".utf8)))

        let cookieStore = CompositionCookieStore(cookies: [])
        let bridge = WebAuthenticationBridge(cookieStore: cookieStore, credentialConsumer: { _ in })
        let source = RestorableAuthenticationCredentialSource(keychain: keychain, webViewSource: bridge)
        let client = CompositionClient(credentialSource: source)
        let flow = ComposedAuthenticationPresentationFlow(bridge: bridge, client: client, credentialSource: source)

        let state = await flow.prepareForExplicitSignIn(onAuthenticationVerification: {}, onEntitlementVerification: {})
        let events = await client.events
        let cookieReadCount = cookieStore.allCookieReadCount
        let secondCredential = await source.credential()

        XCTAssertEqual(state, .entitled)
        XCTAssertEqual(events, [.credential, .authenticate, .entitlement])
        XCTAssertEqual(cookieReadCount, 0)
        XCTAssertNil(secondCredential)
    }

    func testAutomaticRestoreConsumesOneStoredCredentialBeforeOrderedNativeTransaction() async throws {
        var storedCredentialReadCount = 0
        let keychain = KeychainCredentialStore(
            storedCredentialReader: {
                storedCredentialReadCount += 1
                return Data("approved-restore".utf8)
            },
            storedCredentialRemover: {}
        )

        let cookieStore = CompositionCookieStore(cookies: [])
        var signInRequestLoadCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: cookieStore,
            credentialConsumer: { _ in },
            signInRequestLoader: { _ in signInRequestLoadCount += 1 }
        )
        var lifecycleEvents: [ClosedAuthenticationTerminal] = []
        let source = RestorableAuthenticationCredentialSource(
            keychain: keychain,
            webViewSource: bridge,
            telemetry: RestorableAuthenticationCredentialTelemetry { lifecycleEvents.append($0) }
        )
        let client = CompositionClient(credentialSource: source)
        let flow = ComposedAuthenticationPresentationFlow(bridge: bridge, client: client, credentialSource: source)

        let state = await flow.restoreStoredCredential(
            onAuthenticationVerification: {},
            onEntitlementVerification: {}
        )
        let events = await client.events

        XCTAssertEqual(state, .restoreCompleted)
        XCTAssertEqual(events, [.credential, .authenticate, .entitlement])
        XCTAssertEqual(storedCredentialReadCount, 1)
        XCTAssertEqual(cookieStore.allCookieReadCount, 0)
        XCTAssertEqual(signInRequestLoadCount, 0)
        XCTAssertEqual(lifecycleEvents, [.restoreCompleted])
        let subsequentCredential = await source.credential()
        XCTAssertNil(subsequentCredential)
    }

    func testMissingAutomaticRestoreStaysSignedOutWithoutStartingWebView() async {
        let keychain = KeychainCredentialStore(
            service: "com.siriusmac.tests.\(UUID().uuidString)",
            account: "missing-automatic-restore"
        )
        let cookieStore = CompositionCookieStore(cookies: [])
        var signInRequestLoadCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: cookieStore,
            credentialConsumer: { _ in },
            signInRequestLoader: { _ in signInRequestLoadCount += 1 }
        )
        let source = RestorableAuthenticationCredentialSource(keychain: keychain, webViewSource: bridge)
        let client = CompositionClient(credentialSource: source)
        let flow = ComposedAuthenticationPresentationFlow(bridge: bridge, client: client, credentialSource: source)

        let state = await flow.restoreStoredCredential(
            onAuthenticationVerification: {},
            onEntitlementVerification: {}
        )
        let events = await client.events

        XCTAssertEqual(state, .localCredentialMissing)
        XCTAssertEqual(events, [])
        XCTAssertEqual(cookieStore.allCookieReadCount, 0)
        XCTAssertEqual(signInRequestLoadCount, 0)
    }

    func testInvalidAutomaticRestoreRetainsMaterialAndFailsClosedWithoutWebViewFallback() async {
        let invalidMaterial = Data("malformed credential".utf8)
        var storedMaterial: Data? = invalidMaterial
        var removalCount = 0
        let keychain = KeychainCredentialStore(
            storedCredentialReader: { storedMaterial },
            storedCredentialRemover: {
                removalCount += 1
                storedMaterial = nil
            }
        )
        let cookieStore = CompositionCookieStore(cookies: [])
        var signInRequestLoadCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: cookieStore,
            credentialConsumer: { _ in },
            signInRequestLoader: { _ in signInRequestLoadCount += 1 }
        )
        let source = RestorableAuthenticationCredentialSource(keychain: keychain, webViewSource: bridge)
        let client = CompositionClient(credentialSource: source)
        let flow = ComposedAuthenticationPresentationFlow(bridge: bridge, client: client, credentialSource: source)

        let state = await flow.restoreStoredCredential(
            onAuthenticationVerification: {},
            onEntitlementVerification: {}
        )
        let events = await client.events

        XCTAssertEqual(state, .localCredentialInvalid)
        XCTAssertEqual(storedMaterial, invalidMaterial)
        XCTAssertEqual(removalCount, 0)
        XCTAssertEqual(events, [])
        XCTAssertEqual(cookieStore.allCookieReadCount, 0)
        XCTAssertEqual(signInRequestLoadCount, 0)
    }

    func testRejectedAutomaticRestorePreservesCredentialAndDoesNotFallbackOrRetry() async throws {
        let keychain = KeychainCredentialStore(
            service: "com.siriusmac.tests.\(UUID().uuidString)",
            account: "rejected-automatic-restore"
        )
        defer { try? keychain.removeStoredCredential() }
        try await keychain.save(AuthenticationCredential(volatileMaterial: Data("approved-restore".utf8)))

        let cookieStore = CompositionCookieStore(cookies: [])
        var signInRequestLoadCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: cookieStore,
            credentialConsumer: { _ in },
            signInRequestLoader: { _ in signInRequestLoadCount += 1 }
        )
        let source = RestorableAuthenticationCredentialSource(keychain: keychain, webViewSource: bridge)
        let client = CompositionClient(authentication: .rejected, credentialSource: source)
        let flow = ComposedAuthenticationPresentationFlow(bridge: bridge, client: client, credentialSource: source)

        let state = await flow.restoreStoredCredential(
            onAuthenticationVerification: {},
            onEntitlementVerification: {}
        )
        let events = await client.events

        XCTAssertEqual(state, .profileAuthorizationRejected)
        XCTAssertEqual(try keychain.readStoredCredential(), Data("approved-restore".utf8))
        XCTAssertEqual(events, [.credential, .authenticate])
        XCTAssertEqual(cookieStore.allCookieReadCount, 0)
        XCTAssertEqual(signInRequestLoadCount, 0)
    }

    func testRejectedRestoreRetainsCredentialBeforeTerminalStateThenLaterExplicitRetryUsesIt() async throws {
        let now = Date()
        let keychain = KeychainCredentialStore(
            service: "com.siriusmac.tests.\(UUID().uuidString)",
            account: "rejected-restore"
        )
        defer { try? keychain.removeStoredCredential() }
        try await keychain.save(AuthenticationCredential(volatileMaterial: Data("approved-restore".utf8)))

        let cookieStore = CompositionCookieStore(cookies: [try tokenCookie(expires: now.addingTimeInterval(60))])
        let bridge = WebAuthenticationBridge(cookieStore: cookieStore, now: { now }, credentialConsumer: { _ in })
        let source = RestorableAuthenticationCredentialSource(keychain: keychain, webViewSource: bridge)
        let client = CompositionClient(
            credentialSource: source,
            authentications: [.rejected, .authenticatedPendingEntitlement],
            entitlements: [.entitled]
        )
        let model = AuthenticationPresentationModel(
            flow: ComposedAuthenticationPresentationFlow(bridge: bridge, client: client, credentialSource: source)
        )

        try await XCTUnwrap(model.signIn()).value
        XCTAssertEqual(model.state, .profileAuthorizationRejected)
        XCTAssertEqual(try keychain.readStoredCredential(), Data("approved-restore".utf8))
        let cookieReadCount = cookieStore.allCookieReadCount
        XCTAssertEqual(cookieReadCount, 0)

        try await XCTUnwrap(model.retry()).value
        let events = await client.events

        XCTAssertEqual(model.state, .entitled)
        XCTAssertNil(model.useLoggedInSession())
        XCTAssertEqual(events, [.credential, .authenticate, .credential, .authenticate, .entitlement])
    }

    func testUnavailableAutomaticRestoreDoesNotFallThroughToWebViewOrClient() async {
        let cookieStore = CompositionCookieStore(cookies: [])
        var signInRequestLoadCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: cookieStore,
            credentialConsumer: { _ in },
            signInRequestLoader: { _ in signInRequestLoadCount += 1 }
        )
        let keychain = KeychainCredentialStore(
            storedCredentialReader: { throw KeychainCredentialStore.StorageError.unavailable },
            storedCredentialRemover: {}
        )
        let source = RestorableAuthenticationCredentialSource(keychain: keychain, webViewSource: bridge)
        let client = CompositionClient(credentialSource: source)
        let flow = ComposedAuthenticationPresentationFlow(bridge: bridge, client: client, credentialSource: source)

        let state = await flow.restoreStoredCredential(
            onAuthenticationVerification: {},
            onEntitlementVerification: {}
        )
        let events = await client.events

        XCTAssertEqual(state, .localCredentialUnavailable)
        XCTAssertEqual(events, [])
        XCTAssertEqual(cookieStore.allCookieReadCount, 0)
        XCTAssertEqual(signInRequestLoadCount, 0)
    }

    func testMissingRestoreStartsOnlyTheExistingWebViewBranch() async {
        let keychain = KeychainCredentialStore(
            service: "com.siriusmac.tests.\(UUID().uuidString)",
            account: "missing-restore"
        )
        let cookieStore = CompositionCookieStore(cookies: [])
        let bridge = WebAuthenticationBridge(cookieStore: cookieStore, credentialConsumer: { _ in })
        let client = CompositionClient()
        let composition = AuthenticationComposition(bridge: bridge, keychain: keychain, client: client)

        let state = await composition.flow.prepareForExplicitSignIn(
            onAuthenticationVerification: {},
            onEntitlementVerification: {}
        )
        let events = await client.events

        XCTAssertEqual(state, .waitingForWebView)
        XCTAssertEqual(events, [])
        XCTAssertEqual(cookieStore.allCookieReadCount, 0)
    }

    func testRestoredSuccessSignOutClearsKeychainAndBridgeResidueThroughClientPipeline() async throws {
        let now = Date()
        let keychain = KeychainCredentialStore(
            service: "com.siriusmac.tests.\(UUID().uuidString)",
            account: "restored-sign-out"
        )
        defer { try? keychain.removeStoredCredential() }
        try await keychain.save(AuthenticationCredential(volatileMaterial: Data("approved-restore".utf8)))

        let cookieStore = CompositionCookieStore(cookies: [try tokenCookie(expires: now.addingTimeInterval(60))])
        let bridge = WebAuthenticationBridge(cookieStore: cookieStore, now: { now }, credentialConsumer: { _ in })
        let source = RestorableAuthenticationCredentialSource(keychain: keychain, webViewSource: bridge)
        let cleanupClient = SiriusXMClient(credentialSource: source, credentialStore: keychain, residueCleaner: bridge)
        let client = CompositionClient(
            credentialSource: source,
            signOutAction: { await cleanupClient.signOut() }
        )
        let model = AuthenticationPresentationModel(
            flow: ComposedAuthenticationPresentationFlow(bridge: bridge, client: client, credentialSource: source)
        )

        try await XCTUnwrap(model.signIn()).value
        XCTAssertEqual(model.state, .entitled)
        try await XCTUnwrap(model.signOut()).value
        let remainingCookies = await cookieStore.allCookies()

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(try keychain.readStoredCredential())
        XCTAssertTrue(remainingCookies.isEmpty)
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
    enum Event: Equatable { case credential, authenticate, entitlement, signOut }

    private var authentications: [AuthenticationOutcome]
    private var entitlements: [EntitlementAvailability]
    private let signOutResult: SignOutOutcome
    private let signOutAction: (@Sendable () async -> SignOutOutcome)?
    private let credentialSource: (any CredentialSource)?
    private(set) var events: [Event] = []

    init(
        authentication: AuthenticationOutcome = .authenticatedPendingEntitlement,
        entitlement: EntitlementAvailability = .entitled,
        signOut: SignOutOutcome = .signedOut,
        credentialSource: (any CredentialSource)? = nil,
        signOutAction: (@Sendable () async -> SignOutOutcome)? = nil
    ) {
        authentications = [authentication]
        entitlements = [entitlement]
        signOutResult = signOut
        self.credentialSource = credentialSource
        self.signOutAction = signOutAction
    }

    init(
        credentialSource: (any CredentialSource)? = nil,
        authentications: [AuthenticationOutcome],
        entitlements: [EntitlementAvailability]
    ) {
        self.authentications = authentications
        self.entitlements = entitlements
        signOutResult = .signedOut
        self.credentialSource = credentialSource
        signOutAction = nil
    }

    func authenticate() async -> AuthenticationOutcome {
        if let credentialSource {
            guard await credentialSource.credential() != nil else { return .cancelled }
            events.append(.credential)
        }
        events.append(.authenticate)
        return authentications.isEmpty ? .unsupported : authentications.removeFirst()
    }

    func entitlementAvailability() async -> EntitlementAvailability {
        events.append(.entitlement)
        return entitlements.isEmpty ? .unavailable : entitlements.removeFirst()
    }

    func signOut() async -> SignOutOutcome {
        events.append(.signOut)
        return await signOutAction?() ?? signOutResult
    }
}

@MainActor
private final class CompositionCookieStore: WebAuthenticationCookieStore {
    private var cookies: [HTTPCookie]
    private(set) var allCookieReadCount = 0

    init(cookies: [HTTPCookie]) { self.cookies = cookies }

    func allCookies() async -> [HTTPCookie] {
        allCookieReadCount += 1
        return cookies
    }
    func delete(_ cookie: HTTPCookie) async throws { cookies.removeAll { $0 === cookie } }
    func replaceCookies(with cookies: [HTTPCookie]) { self.cookies = cookies }
}
