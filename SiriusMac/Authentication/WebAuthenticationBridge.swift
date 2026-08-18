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
        case cancelled
        case alreadyConsumed
    }

    let webViewConfiguration: WKWebViewConfiguration

    private let cookieStore: any WebAuthenticationCookieStore
    private let now: @MainActor () -> Date
    private let credentialConsumer: @MainActor @Sendable (AuthenticationCredential) async -> Void
    private let handoffDisposer: @MainActor @Sendable () async -> Void
    private let handoff: VolatileWebCredentialHandoff
    private var webView: WKWebView?
    private var selectionState: CredentialSelectionState = .available
    private var selectionGeneration = 0

    init() {
        let handoff = VolatileWebCredentialHandoff()
        let configuration = Self.makeConfiguration()
        webViewConfiguration = configuration
        cookieStore = WebKitAuthenticationCookieStore(cookieStore: configuration.websiteDataStore.httpCookieStore)
        now = Date.init
        self.handoff = handoff
        handoffDisposer = { await handoff.discard() }
        credentialConsumer = { credential in
            await handoff.store(credential)
        }
    }

    init(
        cookieStore: any WebAuthenticationCookieStore,
        now: @escaping @MainActor () -> Date = Date.init,
        credentialConsumer: @escaping @MainActor @Sendable (AuthenticationCredential) async -> Void,
        handoffDisposer: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        let handoff = VolatileWebCredentialHandoff()
        webViewConfiguration = Self.makeConfiguration()
        self.cookieStore = cookieStore
        self.now = now
        self.handoff = handoff
        self.handoffDisposer = {
            await handoff.discard()
            await handoffDisposer()
        }
        self.credentialConsumer = { credential in
            await handoff.store(credential)
            await credentialConsumer(credential)
        }
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
    /// A new explicit attempt discards any volatile prior handoff before re-arming selection.
    func beginUserOperatedSignIn() async {
        // Keep selection fail-closed while the actor erases stale material.
        let reservation = beginSelection()
        await handoffDisposer()
        completeUncommittedSelection(reservation)
        guard let url = URL(string: "https://www.siriusxm.com/") else { return }
        makeWebView().load(URLRequest(url: url))
    }

    /// The only action that reads the WebView-owned cookie store.
    func useLoggedInSession() async -> Result {
        guard selectionState == .available else { return .alreadyConsumed }
        let reservation = beginSelection()
        defer { completeUncommittedSelection(reservation) }

        let candidates = FirstPartyTokenCookiePolicy.matchingCookies(
            in: await cookieStore.allCookies(),
            now: now()
        )
        guard !Task.isCancelled else { return .cancelled }
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
        guard !Task.isCancelled else { return .cancelled }

        let credential = AuthenticationCredential(volatileMaterial: Data(payload.session.accessToken.utf8))
        selectionState = .consumed
        await credentialConsumer(credential)
        return .credentialTransferred
    }

    private func beginSelection() -> Int {
        selectionGeneration &+= 1
        selectionState = .selecting
        return selectionGeneration
    }

    private func completeUncommittedSelection(_ reservation: Int) {
        guard selectionState == .selecting, selectionGeneration == reservation else { return }
        selectionState = .available
    }
}

extension WebAuthenticationBridge: CredentialSource {
    /// Provides the bridge's single-consumption handoff without exposing its material.
    func credential() async -> AuthenticationCredential? {
        await handoff.credential()
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

private enum CredentialSelectionState {
    case available
    case selecting
    case consumed
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

    func discard() {
        storedCredential = nil
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
