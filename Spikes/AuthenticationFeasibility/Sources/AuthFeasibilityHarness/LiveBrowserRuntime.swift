import AuthFeasibilityCore
import Foundation

/// Coordinates one owner-started browser session and one semantic client. It never reads
/// browser state: the sole handoff is the one-time `AppBoundReturnResult` callback.
@MainActor
public final class LiveBrowserRuntime {
    private let webLoginSession: WebLoginSession
    private let semanticClient = SemanticProofClient()

    public init(contract: AuthExperimentContract, approval: ExperimentApproval) throws {
        webLoginSession = try WebLoginSession(contract: contract, approval: approval)
    }

    public var events: [SafeProbeEvent] { semanticClient.events }
    public var isClosed: Bool { semanticClient.isClosed }

    public func startOwnerOperatedRun() throws {
        try webLoginSession.startOwnerOperatedRun(
            onAppBoundReturn: { [weak self] result in
                self?.consume(result)
            },
            onTerminal: { [weak self] reason in
                guard let self else { return }
                if reason == .cancelled {
                    _ = self.semanticClient.cancel()
                } else {
                    _ = self.stop(for: reason.safeReason)
                }
            }
        )
    }

    public func recordNoCleanReturn() -> SafeProbeEvent {
        webLoginSession.stop()
        return semanticClient.recordNoCleanReturn(provenance: .firstPartyNavigation)
    }

    public func recordAuthentication() -> SafeProbeEvent {
        semanticClient.recordAuthentication()
    }

    public func recordEntitlement() -> SafeProbeEvent {
        semanticClient.recordEntitlement()
    }

    public func signOut() -> SafeProbeEvent {
        webLoginSession.stop()
        return semanticClient.signOut()
    }

    public func cancel() -> SafeProbeEvent {
        webLoginSession.cancel()
        return semanticClient.cancel()
    }

    public func stop(for reason: SafeTerminalReason) -> SafeProbeEvent {
        webLoginSession.stop()
        return semanticClient.stop(for: reason)
    }

    private func consume(_ result: AppBoundReturnResult) {
        guard let returnURL = result.consumeURL() else {
            webLoginSession.stop()
            _ = semanticClient.stop(for: .ambiguous)
            return
        }
        _ = semanticClient.consumeMatchedAppBoundReturn(returnURL)
        webLoginSession.stop()
    }
}

private extension BrowserTerminalReason {
    var safeReason: SafeTerminalReason {
        switch self {
        case .offProvenanceNavigation: .offProvenanceNavigation
        case .unexpectedNavigation: .unexpectedNavigation
        case .cancelled: .ambiguous
        }
    }
}
