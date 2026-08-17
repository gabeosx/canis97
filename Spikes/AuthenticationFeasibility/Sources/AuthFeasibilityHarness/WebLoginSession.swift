import AuthFeasibilityCore
import Foundation
import WebKit

public enum BrowserTerminalReason: Equatable, Sendable {
    case offProvenanceNavigation
    case unexpectedNavigation
    case cancelled
}

public enum BrowserObservation: Equatable, Sendable {
    case ordinaryFirstPartyNavigation
    case ordinarySecureSubframeNavigation
    case matchedAppBoundReturn
    case terminal(BrowserTerminalReason)
}

public enum WebLoginSessionState: Equatable, Sendable {
    case awaitingOwnerStart
    case ownerOperating
    case returnMatched
    case terminal(BrowserTerminalReason)
    case stopped
}

public enum BrowserPageStatus: Equatable, Sendable {
    case loading
    case rendered
    case applicationNotRendered
    case navigationFailed(Int)
    case blockedOffProvenanceMainFrame
    case blockedUnexpectedNavigation
    case webContentProcessTerminated

    public var ownerVisibleText: String {
        switch self {
        case .loading: "Loading SiriusXM player…"
        case .rendered: "Player loaded — sign in, then use the logged-in session"
        case .applicationNotRendered: "Player HTML loaded, but its application did not render"
        case let .navigationFailed(code): "SiriusXM player navigation failed (WebKit code \(code))"
        case .blockedOffProvenanceMainFrame: "Blocked an off-provenance main-frame navigation"
        case .blockedUnexpectedNavigation: "Blocked an unexpected navigation"
        case .webContentProcessTerminated: "WebKit player process terminated"
        }
    }

    public var canonicalText: String {
        let outcome = switch self {
        case .loading: "loading"
        case .rendered: "rendered"
        case .applicationNotRendered: "application-not-rendered"
        case let .navigationFailed(code): "navigation-failed-\(code)"
        case .blockedOffProvenanceMainFrame: "blocked-off-provenance-main-frame"
        case .blockedUnexpectedNavigation: "blocked-unexpected-navigation"
        case .webContentProcessTerminated: "web-content-process-terminated"
        }
        return [
            "Schema: web-page-status-v1",
            "Outcome: \(outcome)",
            "Sensitive data: none",
            "",
        ].joined(separator: "\n")
    }
}

/// Volatile, single-consumption material emitted only by a matched app-bound return.
/// It intentionally has no Codable, Sendable, or browser-store inspection surface.
public final class AppBoundReturnResult {
    private var returnURL: URL?

    init(returnURL: URL) {
        self.returnURL = returnURL
    }

    func consumeURL() -> URL? {
        defer { returnURL = nil }
        return returnURL
    }

    deinit {
        returnURL = nil
    }
}

/// The sole AppKit/WebKit boundary for the owner-operated browser experiment.
/// It holds a web view only for one explicit run. Session extraction is explicit,
/// owner-triggered, first-party-only, in-memory, and never persisted or logged.
@MainActor
public final class WebLoginSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let entryURL: URL

    public private(set) var state: WebLoginSessionState = .awaitingOwnerStart

    var hasVolatileBrowserState: Bool { webView != nil || returnHandler != nil || terminalHandler != nil }

    private var webView: WKWebView?
    private var returnHandler: ((AppBoundReturnResult) -> Void)?
    private var terminalHandler: ((BrowserTerminalReason) -> Void)?
    public var onPageStatusChanged: ((BrowserPageStatus) -> Void)?

    public init(contract: AuthExperimentContract, approval: ExperimentApproval) throws {
        try contract.validate()
        guard try CandidateSelection.experimentReadiness(for: contract) == .browserExperimentReady else {
            throw ContractError.invalidArtifact
        }
        try approval.validate(against: contract)
        guard let entryURL = URL(string: contract.browser.entryURL) else {
            throw ContractError.invalidArtifact
        }
        self.entryURL = entryURL
        super.init()
    }

    /// Creates the nonpersistent WebKit view only after the account owner explicitly starts a run.
    public func startOwnerOperatedRun(
        onWebViewCreated: @escaping (WKWebView) -> Void,
        onAppBoundReturn: @escaping (AppBoundReturnResult) -> Void,
        onTerminal: @escaping (BrowserTerminalReason) -> Void
    ) throws {
        guard state == .awaitingOwnerStart else { throw ContractError.invalidArtifact }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = self
        browser.uiDelegate = self
        webView = browser
        returnHandler = onAppBoundReturn
        terminalHandler = onTerminal
        state = .ownerOperating
        onWebViewCreated(browser)
        onPageStatusChanged?(.loading)
        browser.load(URLRequest(url: entryURL))
    }

    /// This is a policy classifier, not a browser-state query. It has no access to cookies,
    /// storage, profiles, credentials, scripts, developer tools, or accessibility data.
    public func observedEvent(for url: URL, isMainFrame: Bool = true) -> BrowserObservation {
        if Self.isAppBoundReturn(url) {
            return isMainFrame ? .matchedAppBoundReturn : .terminal(.unexpectedNavigation)
        }
        if !isMainFrame {
            let allowedSubframeSchemes = ["https", "about", "blob", "data"]
            return url.scheme.map(allowedSubframeSchemes.contains) == true
                ? .ordinarySecureSubframeNavigation
                : .terminal(.unexpectedNavigation)
        }
        guard url.scheme == "https", let host = url.host?.lowercased() else {
            return .terminal(.unexpectedNavigation)
        }
        guard host == "siriusxm.com" || host.hasSuffix(".siriusxm.com") else {
            return .terminal(.offProvenanceNavigation)
        }
        return .ordinaryFirstPartyNavigation
    }

    public func cancel() {
        terminate(.cancelled)
    }

    public func stop() {
        guard state != .stopped else { return }
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        returnHandler = nil
        terminalHandler = nil
        state = .stopped
    }

    func extractFirstPartySession() async -> WebSessionExtraction {
        guard state == .ownerOperating, let webView else { return .authCookieMissing }
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        return SiriusXMAuthCookieExtractor.extract(from: cookies)
    }

    func signOutPresence() async -> WebSessionSignOutPresence {
        guard let webView else { return .absent }
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        return WebSessionSignOutChecker.classify(cookies: cookies)
    }

    /// Keeps target=_blank and window.open login transitions inside the same
    /// ephemeral WebKit data store so the resulting player cookie is extractable.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else {
            return nil
        }
        switch observedEvent(for: url) {
        case .ordinaryFirstPartyNavigation, .ordinarySecureSubframeNavigation:
            webView.load(navigationAction.request)
        case .matchedAppBoundReturn:
            state = .returnMatched
            let result = AppBoundReturnResult(returnURL: url)
            let handler = returnHandler
            returnHandler = nil
            handler?(result)
        case let .terminal(reason):
            terminate(reason)
        }
        return nil
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onPageStatusChanged?(.loading)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard state == .ownerOperating else { return }
        // Navigation completion is the only page signal we need. Querying page
        // JavaScript would expand this feasibility harness into a state extractor.
        onPageStatusChanged?(.rendered)
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        onPageStatusChanged?(.navigationFailed((error as NSError).code))
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        onPageStatusChanged?(.navigationFailed((error as NSError).code))
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onPageStatusChanged?(.webContentProcessTerminated)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            terminate(.unexpectedNavigation)
            decisionHandler(.cancel)
            return
        }

        switch observedEvent(for: url, isMainFrame: navigationAction.targetFrame?.isMainFrame == true) {
        case .ordinaryFirstPartyNavigation, .ordinarySecureSubframeNavigation:
            decisionHandler(.allow)
        case .matchedAppBoundReturn:
            state = .returnMatched
            let result = AppBoundReturnResult(returnURL: url)
            let handler = returnHandler
            returnHandler = nil
            handler?(result)
            decisionHandler(.cancel)
        case let .terminal(reason):
            terminate(reason)
            decisionHandler(.cancel)
        }
    }

    private func terminate(_ reason: BrowserTerminalReason) {
        let handler = terminalHandler
        switch reason {
        case .offProvenanceNavigation:
            onPageStatusChanged?(.blockedOffProvenanceMainFrame)
        case .unexpectedNavigation:
            onPageStatusChanged?(.blockedUnexpectedNavigation)
        case .cancelled:
            break
        }
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        returnHandler = nil
        terminalHandler = nil
        state = .terminal(reason)
        handler?(reason)
    }

    private static func isAppBoundReturn(_ url: URL) -> Bool {
        url.scheme == "siriusmac-auth" &&
            url.host == "browser-return" &&
            (url.path.isEmpty || url.path == "/") &&
            url.user == nil &&
            url.password == nil &&
            url.query == nil &&
            url.fragment == nil
    }
}
