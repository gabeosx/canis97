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
/// It holds a web view only for one explicit run and never queries browser state.
@MainActor
public final class WebLoginSession: NSObject, WKNavigationDelegate {
    private static let entryURL = URL(string: "https://www.siriusxm.com/")!

    public private(set) var state: WebLoginSessionState = .awaitingOwnerStart

    private var webView: WKWebView?
    private var returnHandler: ((AppBoundReturnResult) -> Void)?
    private var terminalHandler: ((BrowserTerminalReason) -> Void)?

    public init(contract: AuthExperimentContract, approval: ExperimentApproval) throws {
        try contract.validate()
        guard try CandidateSelection.experimentReadiness(for: contract) == .browserExperimentReady else {
            throw ContractError.invalidArtifact
        }
        try approval.validate(against: contract)
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
        webView = browser
        returnHandler = onAppBoundReturn
        terminalHandler = onTerminal
        state = .ownerOperating
        onWebViewCreated(browser)
        browser.load(URLRequest(url: Self.entryURL))
    }

    /// This is a policy classifier, not a browser-state query. It has no access to cookies,
    /// storage, profiles, credentials, scripts, developer tools, or accessibility data.
    public func observedEvent(for url: URL) -> BrowserObservation {
        if Self.isAppBoundReturn(url) {
            return .matchedAppBoundReturn
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
        webView = nil
        returnHandler = nil
        terminalHandler = nil
        state = .stopped
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

        switch observedEvent(for: url) {
        case .ordinaryFirstPartyNavigation:
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
        webView?.stopLoading()
        webView?.navigationDelegate = nil
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
            url.fragment == nil
    }
}
