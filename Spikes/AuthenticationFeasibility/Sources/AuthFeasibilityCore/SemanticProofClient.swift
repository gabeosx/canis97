import Foundation

/// A purpose-scoped, ephemeral client. It has no API for browser storage, cookies,
/// profiles, or arbitrary request construction; it can only collapse an explicit return.
public final class EphemeralSiriusXMProbeClient {
    private let session: URLSession
    private var isClosed = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration)
    }

    func consumeExplicitAppBoundReturn(_ returnURL: URL) -> SafeProbeEvent {
        defer { _ = returnURL }
        guard !isClosed, Self.isMatchedAppBoundReturn(returnURL) else {
            return .terminal(.redirectMismatch)
        }
        return .cleanAppBoundReturn
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        session.invalidateAndCancel()
    }

    private static func isMatchedAppBoundReturn(_ url: URL) -> Bool {
        url.scheme == "siriusmac-auth" &&
            url.host == "browser-return" &&
            (url.path.isEmpty || url.path == "/") &&
            url.user == nil &&
            url.password == nil &&
            url.fragment == nil
    }
}

/// Collapses volatile runtime material to closed semantic outcomes immediately.
/// It intentionally offers neither retry nor fallback behavior.
public final class SemanticProofClient {
    private enum State {
        case awaitingReturn
        case returnObserved
        case authenticated
        case entitled
        case incomplete
        case closed(SafeProbeEvent)
    }

    private let probeClient = EphemeralSiriusXMProbeClient()
    private var state: State = .awaitingReturn
    public private(set) var events: [SafeProbeEvent] = []

    public init() {}

    public var isClosed: Bool {
        if case .closed = state { return true }
        return false
    }

    /// `LiveBrowserRuntime` calls this only after consuming `AppBoundReturnResult`.
    /// It validates the app-bound shape and never retains or exposes the volatile URL.
    public func consumeMatchedAppBoundReturn(_ returnURL: URL) -> SafeProbeEvent {
        guard case .awaitingReturn = state else { return close(.ambiguous) }
        let event = probeClient.consumeExplicitAppBoundReturn(returnURL)
        switch event {
        case .cleanAppBoundReturn:
            state = .returnObserved
            return append(event)
        case let .terminal(reason):
            return close(reason)
        default:
            return close(.ambiguous)
        }
    }

    public func recordAuthentication() -> SafeProbeEvent {
        guard case .returnObserved = state else { return terminalOrClose(.ambiguous) }
        state = .authenticated
        return append(.authenticated)
    }

    public func recordEntitlement() -> SafeProbeEvent {
        guard case .authenticated = state else { return terminalOrClose(.ambiguous) }
        state = .entitled
        return append(.entitled)
    }

    public func recordNoCleanReturn(provenance: SanitizedNavigationProvenance) -> SafeProbeEvent {
        guard case .awaitingReturn = state else { return terminalOrClose(.ambiguous) }
        probeClient.close()
        state = .incomplete
        return append(.noCleanReturn(provenance))
    }

    public func stop(for reason: SafeTerminalReason) -> SafeProbeEvent {
        close(reason)
    }

    public func cancel() -> SafeProbeEvent {
        close(.cancelled)
    }

    public func signOut() -> SafeProbeEvent {
        guard case .entitled = state else { return terminalOrClose(.ambiguous) }
        return close(.signedOut)
    }

    private func terminalOrClose(_ reason: SafeTerminalReason) -> SafeProbeEvent {
        if case let .closed(event) = state { return event }
        return close(reason)
    }

    private func close(_ event: SafeProbeEvent) -> SafeProbeEvent {
        if case let .closed(existing) = state { return existing }
        probeClient.close()
        state = .closed(event)
        return append(event)
    }

    private func close(_ reason: SafeTerminalReason) -> SafeProbeEvent {
        close(.terminal(reason))
    }

    private func append(_ event: SafeProbeEvent) -> SafeProbeEvent {
        events.append(event)
        return event
    }
}
