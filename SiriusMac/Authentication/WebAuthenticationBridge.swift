import Foundation
import OSLog
import WebKit
import SiriusXMClient

enum AuthenticationBridgeDiagnostic: String, CaseIterable, Equatable {
    case webSignInStarted = "web-sign-in-started"
    case credentialSelectionStarted = "credential-selection-started"
    case authCookieNameAbsent = "auth-cookie-name-absent"
    case authCookieIssuerRejected = "auth-cookie-issuer-rejected"
    case authCookiePathRejected = "auth-cookie-path-rejected"
    case authCookieExpired = "auth-cookie-expired"
    case authCookieMissing = "auth-cookie-missing"
    case ambiguousCredentials = "ambiguous-credentials"
    case malformedCredential = "malformed-credential"
    case selectionCancelled = "selection-cancelled"
    case credentialAlreadyConsumed = "credential-already-consumed"
    case credentialTransferred = "credential-transferred"
    case websiteSessionResetFailed = "web-session-reset-failed"
}

@MainActor
struct AuthenticationBridgeTelemetry {
    private let recorder: (AuthenticationBridgeDiagnostic) -> Void
    init(record: @escaping (AuthenticationBridgeDiagnostic) -> Void = { _ in }) {
        recorder = record
    }

    static let disabled = AuthenticationBridgeTelemetry()
    static let live: AuthenticationBridgeTelemetry = {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.siriusmac.player",
            category: "authentication"
        )
        return AuthenticationBridgeTelemetry(record: { event in
                logger.info("Sirius Mac auth bridge event \(event.rawValue, privacy: .public)")
        })
    }()

    func record(_ event: AuthenticationBridgeDiagnostic) {
        recorder(event)
    }

}

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

    var webViewConfiguration: WKWebViewConfiguration { websiteSession.configuration }
    var websiteSessionGeneration: Int { websiteSession.generation }

    private var cookieStore: any WebAuthenticationCookieStore
    private let now: @MainActor () -> Date
    private let credentialConsumer: @MainActor @Sendable (AuthenticationCredential) async -> Void
    private let handoffDisposer: @MainActor @Sendable () async -> Void
    private let handoff: VolatileWebCredentialHandoff
    private let websiteSession: WebAuthenticationWebsiteSession
    private let websiteSessionRetirer: @MainActor @Sendable () async -> Bool
    private let signInRequestLoader: @MainActor (URLRequest) -> Void
    private let telemetry: AuthenticationBridgeTelemetry
    private let usesLiveCookieStore: Bool
    private var selectionState: CredentialSelectionState = .available
    private var selectionGeneration = 0
    private var pendingSignInRequest: URLRequest?

    init() {
        let handoff = VolatileWebCredentialHandoff()
        let websiteSession = WebAuthenticationWebsiteSession()
        self.websiteSession = websiteSession
        cookieStore = WebKitAuthenticationCookieStore(cookieStore: websiteSession.configuration.websiteDataStore.httpCookieStore)
        now = Date.init
        self.handoff = handoff
        websiteSessionRetirer = { await websiteSession.removeAllWebsiteData() }
        signInRequestLoader = { request in websiteSession.makeWebView().load(request) }
        usesLiveCookieStore = true
        telemetry = .live
        handoffDisposer = { await handoff.discard() }
        credentialConsumer = { credential in
            await handoff.store(credential)
        }
    }

    init(
        cookieStore: any WebAuthenticationCookieStore,
        now: @escaping @MainActor () -> Date = Date.init,
        credentialConsumer: @escaping @MainActor @Sendable (AuthenticationCredential) async -> Void,
        handoffDisposer: @escaping @MainActor @Sendable () async -> Void = {},
        websiteSessionRetirer: @escaping @MainActor @Sendable () async -> Bool = { true },
        telemetry: AuthenticationBridgeTelemetry = .disabled,
        signInRequestLoader: @escaping @MainActor (URLRequest) -> Void = { _ in }
    ) {
        let handoff = VolatileWebCredentialHandoff()
        websiteSession = WebAuthenticationWebsiteSession()
        self.cookieStore = cookieStore
        self.now = now
        self.handoff = handoff
        self.websiteSessionRetirer = websiteSessionRetirer
        self.signInRequestLoader = signInRequestLoader
        self.telemetry = telemetry
        usesLiveCookieStore = false
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
        websiteSession.makeWebView()
    }

    /// Starts the sole owner-operated authentication path without reading browser state.
    /// A new explicit attempt discards any volatile prior handoff before re-arming selection.
    func beginUserOperatedSignIn() async -> Bool {
        telemetry.record(.webSignInStarted)
        // Keep selection fail-closed while stale handoff and website state retire.
        let reservation = beginSelection()
        pendingSignInRequest = nil
        await handoffDisposer()
        guard await retireAuthenticationWebsiteSession() else {
            telemetry.record(.websiteSessionResetFailed)
            return false
        }
        completeUncommittedSelection(reservation)
        guard let url = URL(string: "https://www.siriusxm.com/player") else { return false }
        pendingSignInRequest = URLRequest(url: url)
        return true
    }

    /// Starts the queued request only after SwiftUI has installed this bridge's
    /// current WebView in the visible AppKit host. Repeated view updates cannot
    /// issue a second navigation.
    func loadPendingSignInRequestIfNeeded() {
        guard let request = pendingSignInRequest else { return }
        pendingSignInRequest = nil
        signInRequestLoader(request)
    }

    /// The only action that reads the WebView-owned cookie store.
    func useLoggedInSession() async -> Result {
        telemetry.record(.credentialSelectionStarted)
        guard selectionState == .available else {
            telemetry.record(.credentialAlreadyConsumed)
            return .alreadyConsumed
        }
        let reservation = beginSelection()
        defer { completeUncommittedSelection(reservation) }

        let cookies = await cookieStore.allCookies()
        guard !Task.isCancelled else {
            telemetry.record(.selectionCancelled)
            return .cancelled
        }
        switch WebCredentialSelectionPolicy.select(from: cookies, now: now()) {
        case let .missing(reasons):
            for reason in reasons {
                telemetry.record(reason.bridgeDiagnostic)
            }
            telemetry.record(.authCookieMissing)
            return .authCookieMissing
        case .ambiguous:
            telemetry.record(.ambiguousCredentials)
            return .ambiguousCredentials
        case .malformed:
            telemetry.record(.malformedCredential)
            return .malformedCredential
        case let .credential(credential):
            guard !Task.isCancelled else {
                telemetry.record(.selectionCancelled)
                return .cancelled
            }

            selectionState = .consumed
            await credentialConsumer(credential)
            telemetry.record(.credentialTransferred)
            return .credentialTransferred
        }
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

    /// Retires the bridge-owned nonpersistent website session without inspecting its records.
    /// The only observable result is whether its bulk removal completed before rotation.
    func retireAuthenticationWebsiteSession() async -> Bool {
        websiteSession.stopLoading()
        guard await websiteSessionRetirer() else { return false }
        websiteSession.installFreshNonpersistentSession()
        if usesLiveCookieStore {
            cookieStore = WebKitAuthenticationCookieStore(
                cookieStore: websiteSession.configuration.websiteDataStore.httpCookieStore
            )
        }
        return true
    }
}

private extension FirstPartyTokenCookiePolicy.RejectionReason {
    var bridgeDiagnostic: AuthenticationBridgeDiagnostic {
        switch self {
        case .nameAbsent: .authCookieNameAbsent
        case .issuerRejected: .authCookieIssuerRejected
        case .pathRejected: .authCookiePathRejected
        case .expired: .authCookieExpired
        }
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
    /// rescans that exact set, then retires the app-owned nonpersistent website session.
    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome {
        let currentTime = now()
        let initialMatches = FirstPartyTokenCookiePolicy.matchingCookies(
            in: await cookieStore.allCookies(),
            now: currentTime
        )

        var deletionFailed = false
        for cookie in initialMatches {
            do {
                try await cookieStore.delete(cookie)
            } catch {
                deletionFailed = true
            }
        }

        let remainingMatches = FirstPartyTokenCookiePolicy.matchingCookies(
            in: await cookieStore.allCookies(),
            now: currentTime
        )
        let didRetireWebsiteSession = await retireAuthenticationWebsiteSession()
        return !deletionFailed && remainingMatches.isEmpty && didRetireWebsiteSession ? .removed : .cleanupFailed
    }
}

@MainActor
private final class WebAuthenticationWebsiteSession {
    private(set) var configuration: WKWebViewConfiguration = WebAuthenticationBridge.makeConfiguration()
    private(set) var generation = 0
    private var webView: WKWebView?

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        return webView
    }

    func stopLoading() {
        webView?.stopLoading()
    }

    func removeAllWebsiteData() async -> Bool {
        await configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
        return true
    }

    func installFreshNonpersistentSession() {
        webView = nil
        configuration = WebAuthenticationBridge.makeConfiguration()
        generation &+= 1
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
