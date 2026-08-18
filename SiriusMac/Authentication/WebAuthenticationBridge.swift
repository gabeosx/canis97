import Foundation
import WebKit
import SiriusXMClient

@MainActor
protocol WebAuthenticationCookieStore: AnyObject {
    func allCookies() async -> [HTTPCookie]
    func delete(_ cookie: HTTPCookie) async throws
}

@MainActor
final class WebAuthenticationBridge {
    enum Result: Equatable {
        case credentialTransferred
        case authCookieMissing
        case ambiguousCredentials
        case malformedCredential
        case alreadyConsumed
    }

    let webViewConfiguration: WKWebViewConfiguration

    private let cookieStore: any WebAuthenticationCookieStore
    private let now: @MainActor () -> Date
    private let credentialConsumer: @MainActor @Sendable (AuthenticationCredential) async -> Void
    private let handoff: VolatileWebCredentialHandoff?
    private var webView: WKWebView?
    private var didTransferCredential = false

    init() {
        let handoff = VolatileWebCredentialHandoff()
        let configuration = Self.makeConfiguration()
        webViewConfiguration = configuration
        cookieStore = WebKitAuthenticationCookieStore(cookieStore: configuration.websiteDataStore.httpCookieStore)
        now = Date.init
        self.handoff = handoff
        credentialConsumer = { credential in
            await handoff.store(credential)
        }
    }

    init(
        cookieStore: any WebAuthenticationCookieStore,
        now: @escaping @MainActor () -> Date = Date.init,
        credentialConsumer: @escaping @MainActor @Sendable (AuthenticationCredential) async -> Void
    ) {
        webViewConfiguration = Self.makeConfiguration()
        self.cookieStore = cookieStore
        self.now = now
        self.credentialConsumer = credentialConsumer
        handoff = nil
    }

    /// The app-facing, single-consumption client seam for the opaque credential.
    var credentialSource: (any CredentialSource)? {
        handoff
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        self.webView = webView
        return webView
    }

    /// Starts the sole owner-operated authentication path without reading browser state.
    func beginUserOperatedSignIn() {
        guard let url = URL(string: "https://www.siriusxm.com/") else { return }
        makeWebView().load(URLRequest(url: url))
    }

    /// The only action that reads the WebView-owned cookie store.
    func useLoggedInSession() async -> Result {
        guard !didTransferCredential else { return .alreadyConsumed }

        let candidates = FirstPartyTokenCookiePolicy.matchingCookies(
            in: await cookieStore.allCookies(),
            now: now()
        )
        switch candidates.count {
        case 0: return .authCookieMissing
        case 1: break
        default: return .ambiguousCredentials
        }

        var encodedCookieValue = candidates[0].value
        defer { encodedCookieValue = "" }
        guard encodedCookieValue.utf8.count <= 16_384,
              var decodedCookieValue = encodedCookieValue.removingPercentEncoding,
              decodedCookieValue.utf8.count <= 8_192 else {
            return .malformedCredential
        }
        defer { decodedCookieValue = "" }

        var payloadData: Data? = Data(decodedCookieValue.utf8)
        defer { payloadData = nil }
        guard let payloadData,
              let payload = try? JSONDecoder().decode(TokenCookiePayload.self, from: payloadData),
              payload.session.accessToken.utf8.count <= 8_192,
              !payload.session.accessToken.isEmpty,
              !payload.session.accessToken.contains(where: { $0.isWhitespace }) else {
            return .malformedCredential
        }

        let credential = AuthenticationCredential(volatileMaterial: Data(payload.session.accessToken.utf8))
        didTransferCredential = true
        await credentialConsumer(credential)
        return .credentialTransferred
    }
}

extension WebAuthenticationBridge: AuthenticationResidueCleaner {
    /// Deletes only cookies selected by the same predicate used for extraction,
    /// then requires a clean rescan before reporting completion.
    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome {
        let currentTime = now()
        let initialMatches = FirstPartyTokenCookiePolicy.matchingCookies(
            in: await cookieStore.allCookies(),
            now: currentTime
        )

        for cookie in initialMatches {
            do {
                try await cookieStore.delete(cookie)
            } catch {
                return .cleanupFailed
            }
        }

        let remainingMatches = FirstPartyTokenCookiePolicy.matchingCookies(
            in: await cookieStore.allCookies(),
            now: currentTime
        )
        return remainingMatches.isEmpty ? .removed : .cleanupFailed
    }
}

private struct TokenCookiePayload: Decodable {
    let session: TokenSession

    struct TokenSession: Decodable {
        let accessToken: String
    }
}

private actor VolatileWebCredentialHandoff: CredentialSource {
    private var storedCredential: AuthenticationCredential?

    func store(_ credential: AuthenticationCredential) {
        storedCredential = credential
    }

    func credential() -> AuthenticationCredential? {
        defer { storedCredential = nil }
        return storedCredential
    }
}

@MainActor
private final class WebKitAuthenticationCookieStore: WebAuthenticationCookieStore {
    private let cookieStore: WKHTTPCookieStore

    init(cookieStore: WKHTTPCookieStore) {
        self.cookieStore = cookieStore
    }

    func allCookies() async -> [HTTPCookie] {
        await cookieStore.allCookies()
    }

    func delete(_ cookie: HTTPCookie) async throws {
        await withCheckedContinuation { continuation in
            cookieStore.delete(cookie) { continuation.resume() }
        }
    }
}
