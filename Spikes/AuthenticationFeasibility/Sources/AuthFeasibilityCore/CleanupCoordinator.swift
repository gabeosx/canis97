/// Fixed teardown steps for all proof exits. The names describe local cleanup
/// operations only; they contain no account or provider material.
public enum CleanupStep: Equatable, Sendable {
    case signOut
    case cancelEphemeralClient
    case tearDownBrowser
    case tearDownPlayback
    case clearVolatileState
    case verifyLocalAbsence
}

public enum CleanupProof: Equatable, Sendable {
    case verified
    case failed
}

@MainActor
public protocol VolatileCleanupParticipant: AnyObject {
    func perform(_ step: CleanupStep) async -> Bool
}

/// Runs cleanup in one canonical order and caches the resulting proof. A failed
/// cleanup is never retried implicitly: it remains a closed failure.
@MainActor
public final class CleanupCoordinator {
    private let participant: any VolatileCleanupParticipant
    private var proof: CleanupProof?

    public init(participant: any VolatileCleanupParticipant) {
        self.participant = participant
    }

    public func cleanUp() async -> CleanupProof {
        if let proof { return proof }

        for step in [
            CleanupStep.signOut,
            .cancelEphemeralClient,
            .tearDownBrowser,
            .tearDownPlayback,
            .clearVolatileState,
            .verifyLocalAbsence,
        ] {
            guard await participant.perform(step) else {
                proof = .failed
                return .failed
            }
        }
        proof = .verified
        return .verified
    }
}

public enum BrowserPreflightOutcome: Equatable, Sendable {
    case awaitingNextStep
    case renewalPending
    case incomplete
    case complete
    case terminal(SafeTerminalReason)
}

/// Validates the fixed closed-event sequence before any browser proof can count.
/// It has no provider operation, playback, network, or serialization surface.
public struct BrowserProofPreflight: Sendable {
    private enum State: Sendable {
        case awaitingReturn
        case awaitingAuthentication
        case awaitingEntitlement
        case awaitingTuneKey
        case awaitingAudible
        case awaitingRenewal
        case awaitingSignOut(BrowserPreflightOutcome)
        case awaitingCleanup(BrowserPreflightOutcome)
        case closed(BrowserPreflightOutcome)
    }

    private var state: State = .awaitingReturn

    public init() {}

    public var canSerializeComplete: Bool {
        if case .closed(.complete) = state { return true }
        return false
    }

    public mutating func consume(_ event: SafeProbeEvent) -> BrowserPreflightOutcome {
        if case let .closed(outcome) = state { return outcome }
        switch event {
        case let .terminal(reason): return close(.terminal(reason))
        case .cancelled: return close(.terminal(.ambiguous))
        case .noCleanReturn: return close(.incomplete)
        case .cleanupFailed: return close(.incomplete)
        default: break
        }

        switch (state, event) {
        case (.awaitingReturn, .cleanAppBoundReturn):
            state = .awaitingAuthentication
        case (.awaitingAuthentication, .authenticated):
            state = .awaitingEntitlement
        case (.awaitingEntitlement, .entitled):
            state = .awaitingTuneKey
        case (.awaitingTuneKey, .tuneKeyAuthorized):
            state = .awaitingAudible
        case (.awaitingAudible, .audiblePlayback):
            state = .awaitingRenewal
        case (.awaitingRenewal, .renewed):
            state = .awaitingSignOut(.complete)
        case (.awaitingRenewal, .renewalPending):
            state = .awaitingSignOut(.renewalPending)
        case let (.awaitingSignOut(outcome), .signedOut):
            state = .awaitingCleanup(outcome)
        case let (.awaitingCleanup(outcome), .cleanupVerified):
            return close(outcome)
        default:
            return close(.terminal(.ambiguous))
        }
        return .awaitingNextStep
    }

    private mutating func close(_ outcome: BrowserPreflightOutcome) -> BrowserPreflightOutcome {
        state = .closed(outcome)
        return outcome
    }
}
