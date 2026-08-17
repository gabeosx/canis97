import AuthFeasibilityCore
import Foundation
import WebKit

/// Coordinates one owner-started browser session and one semantic client. It never reads
/// browser state: the sole handoff is the one-time `AppBoundReturnResult` callback.
@MainActor
public final class LiveBrowserRuntime {
    private let webLoginSession: WebLoginSession
    private let semanticClient = SemanticProofClient()
    private var preflight = BrowserProofPreflight()
    private var proofEvents: [SafeProbeEvent] = []
    private lazy var cleanupCoordinator = CleanupCoordinator(
        participant: BrowserRuntimeCleanupParticipant(webLoginSession: webLoginSession)
    )

    public init(contract: AuthExperimentContract, approval: ExperimentApproval) throws {
        webLoginSession = try WebLoginSession(contract: contract, approval: approval)
    }

    public var events: [SafeProbeEvent] { semanticClient.events + proofEvents }
    public var isClosed: Bool { semanticClient.isClosed }
    public var canSerializeCompleteProof: Bool { preflight.canSerializeComplete }
    public private(set) var renewalStatus: RenewalStatus = .pending {
        didSet { onRenewalStatusChanged?(renewalStatus) }
    }
    /// Receives only a `RenewalStatus` closed semantic state. It must never be
    /// used to surface browser, provider, or session details.
    public var onRenewalStatusChanged: ((RenewalStatus) -> Void)?

    public func startOwnerOperatedRun(onWebViewCreated: @escaping (WKWebView) -> Void) throws {
        try webLoginSession.startOwnerOperatedRun(
            onWebViewCreated: onWebViewCreated,
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
        consumePreflight(semanticClient.recordAuthentication())
    }

    public func recordEntitlement() -> SafeProbeEvent {
        consumePreflight(semanticClient.recordEntitlement())
    }

    public func recordTuneKeyAuthorization() -> SafeProbeEvent {
        recordProofEvent(.tuneKeyAuthorized)
    }

    public func recordAudiblePlayback() -> SafeProbeEvent {
        recordProofEvent(.audiblePlayback)
    }

    public func recordRenewal(_ proof: RenewalProof) -> SafeProbeEvent {
        renewalStatus = RenewalStatus(proof: proof)
        switch proof {
        case .renewed:
            return recordProofEvent(.renewed)
        case .renewalPending:
            return recordProofEvent(.renewalPending)
        case .notApplicable:
            return stop(for: .ambiguous)
        case let .terminal(reason):
            return stop(for: reason)
        }
    }

    public func signOut() -> SafeProbeEvent {
        webLoginSession.stop()
        return consumePreflight(semanticClient.signOut())
    }

    /// Cleanup is explicitly awaited and its closed result is fed back into the
    /// preflight. The runtime has no API to inspect browser or provider state.
    public func cleanUp() async -> CleanupProof {
        if semanticClient.events.last == .entitled {
            _ = signOut()
        }
        let proof = await cleanupCoordinator.cleanUp()
        _ = preflight.consume(proof == .verified ? .cleanupVerified : .cleanupFailed)
        return proof
    }

    public func cancel() -> SafeProbeEvent {
        webLoginSession.cancel()
        return semanticClient.cancel()
    }

    public func stop(for reason: SafeTerminalReason) -> SafeProbeEvent {
        webLoginSession.stop()
        renewalStatus = .terminalStop
        return semanticClient.stop(for: reason)
    }

    private func consume(_ result: AppBoundReturnResult) {
        guard let returnURL = result.consumeURL() else {
            webLoginSession.stop()
            _ = semanticClient.stop(for: .ambiguous)
            return
        }
        _ = consumePreflight(semanticClient.consumeMatchedAppBoundReturn(returnURL))
        webLoginSession.stop()
    }

    @discardableResult
    private func consumePreflight(_ event: SafeProbeEvent) -> SafeProbeEvent {
        _ = preflight.consume(event)
        return event
    }

    private func recordProofEvent(_ event: SafeProbeEvent) -> SafeProbeEvent {
        if case let .terminal(reason) = preflight.consume(event) {
            return stop(for: reason)
        }
        proofEvents.append(event)
        return event
    }
}

@MainActor
private final class BrowserRuntimeCleanupParticipant: VolatileCleanupParticipant {
    private let webLoginSession: WebLoginSession

    init(webLoginSession: WebLoginSession) {
        self.webLoginSession = webLoginSession
    }

    func perform(_ step: CleanupStep) async -> Bool {
        switch step {
        case .tearDownBrowser:
            webLoginSession.stop()
        case .signOut, .cancelEphemeralClient, .tearDownPlayback, .clearVolatileState, .verifyLocalAbsence:
            break
        }
        return true
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
