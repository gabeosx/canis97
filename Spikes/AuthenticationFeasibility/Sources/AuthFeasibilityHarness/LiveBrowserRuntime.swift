import AuthFeasibilityCore
import Foundation
import WebKit

public enum InstrumentedBrowserRunResult: Equatable, Sendable {
    case awaitingOwnerSignOut
    case complete
    case incomplete
    case terminal
}

/// One non-retryable synthetic tracer. Authentication and entitlement are
/// deliberately distinct; a successful profile verification only advances to
/// the separately bounded entitlement check.
@MainActor
public final class InstrumentedBrowserRun {
    private enum State { case ready, inFlight, awaitingOwnerSignOut, complete, closed }

    private var state: State = .ready
    private let authenticationVerifier: NativeWebSessionVerifier
    private let entitlementVerifier: NativeEntitlementVerifier
    private let cleanup: CleanupCoordinator

    init(
        entitlementContract: EntitlementContract,
        authenticationTransport: WebSessionTransport = .live,
        entitlementTransport: WebSessionTransport = .live,
        cleanup: CleanupCoordinator
    ) throws {
        authenticationVerifier = NativeWebSessionVerifier(transport: authenticationTransport)
        entitlementVerifier = try NativeEntitlementVerifier(contract: entitlementContract, transport: entitlementTransport)
        self.cleanup = cleanup
    }

    func use(_ session: VolatileWebSession) async -> InstrumentedBrowserRunResult {
        guard state == .ready else { return .terminal }
        state = .inFlight
        guard let result = await session.consumeForRun({ accessToken in
            let authentication = await authenticationVerifier.verify(accessToken: accessToken)
            guard authentication == .authenticated else { return InstrumentedBrowserRunResult.terminal }
            let entitlement = await entitlementVerifier.verify(accessToken: accessToken)
            return entitlement == .entitled ? .awaitingOwnerSignOut : .terminal
        }) else {
            state = .closed
            return .terminal
        }
        state = result == .awaitingOwnerSignOut ? .awaitingOwnerSignOut : .closed
        return result
    }

    func finish(signOutPresence: WebSessionSignOutPresence) async -> InstrumentedBrowserRunResult {
        guard state == .awaitingOwnerSignOut else { return .terminal }
        guard signOutPresence == .absent else {
            state = .closed
            return .terminal
        }
        let proof = await cleanup.cleanUp()
        guard proof == .verified else {
            state = .closed
            return .incomplete
        }
        state = .complete
        return .complete
    }
}

/// Coordinates one owner-started browser session and an explicit owner-triggered,
/// in-memory transfer of first-party WebKit session cookies to an ephemeral native client.
@MainActor
public final class LiveBrowserRuntime {
    private let webLoginSession: WebLoginSession
    private let semanticClient = SemanticProofClient()
    private let nativeSessionVerifier = NativeWebSessionVerifier()
    private var preflight = BrowserProofPreflight()
    private var proofEvents: [SafeProbeEvent] = []
    private lazy var cleanupCoordinator = CleanupCoordinator(
        participant: BrowserRuntimeCleanupParticipant(
            webLoginSession: webLoginSession,
            semanticClient: semanticClient
        )
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
    public var onPageStatusChanged: ((BrowserPageStatus) -> Void)? {
        didSet { webLoginSession.onPageStatusChanged = onPageStatusChanged }
    }

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

    public func importAuthenticatedWebSession() async -> WebSessionBridgeResult {
        switch await webLoginSession.extractFirstPartySession() {
        case let .session(session):
            return await nativeSessionVerifier.verify(session)
        case .authCookieMissing:
            return .authCookieMissing
        case .authCookieMalformed:
            return .authCookieMalformed
        }
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

    /// The owner performs sign-out in the provider surface. We then inspect only
    /// the named first-party cookie's presence before allowing cleanup to finish.
    public func verifySignOutAndClean() async -> CleanupProof {
        guard await webLoginSession.signOutPresence() == .absent else {
            _ = stop(for: .ambiguous)
            return .failed
        }
        return await cleanUp()
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
    private let semanticClient: SemanticProofClient

    init(webLoginSession: WebLoginSession, semanticClient: SemanticProofClient) {
        self.webLoginSession = webLoginSession
        self.semanticClient = semanticClient
    }

    func perform(_ step: CleanupStep) async -> Bool {
        switch step {
        case .signOut:
            guard semanticClient.canSignOutSafely else { return true }
            return semanticClient.signOut() == .signedOut
        case .cancelEphemeralClient:
            if !semanticClient.isClosed { _ = semanticClient.cancel() }
            return semanticClient.isClosed
        case .tearDownBrowser:
            webLoginSession.stop()
            return !webLoginSession.hasVolatileBrowserState
        case .tearDownPlayback:
            // This browser runtime has no playback object. Absence is the verified state.
            return true
        case .clearVolatileState:
            webLoginSession.stop()
            if !semanticClient.isClosed { _ = semanticClient.cancel() }
            return !webLoginSession.hasVolatileBrowserState && semanticClient.isClosed
        case .verifyLocalAbsence:
            return !webLoginSession.hasVolatileBrowserState && semanticClient.isClosed
        }
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
