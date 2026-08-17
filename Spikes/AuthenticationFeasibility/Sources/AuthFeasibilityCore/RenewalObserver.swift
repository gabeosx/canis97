/// Closed outcomes for passive renewal observation. `renewalPending` is incomplete
/// evidence, never a GO or NO-GO classification.
public enum RenewalProof: Equatable, Sendable {
    case notApplicable
    case renewalPending
    case renewed
    case terminal(SafeTerminalReason)
}

/// The only renewal detail presented to an owner during a bounded observation
/// window. It is deliberately a closed vocabulary: it cannot carry provider,
/// account, transport, time, or session material.
public enum RenewalStatus: Equatable, Sendable {
    case pending
    case verified
    case terminalStop

    public init(proof: RenewalProof) {
        switch proof {
        case .renewalPending:
            self = .pending
        case .renewed:
            self = .verified
        case .notApplicable, .terminal:
            self = .terminalStop
        }
    }

    public var ownerVisibleText: String {
        switch self {
        case .pending: "Renewal pending"
        case .verified: "Renewal verified"
        case .terminalStop: "Terminal stop"
        }
    }
}

/// Semantic observations supplied by the established ordinary flow. No token,
/// cookie, expiry, clock, request, response, or provider identifier is retained.
public enum RenewalObservation: Equatable, Sendable {
    case ordinaryProviderReplacement
    case ownerEnded
    case protectedBehavior
    case ambiguous
}

/// Passively classifies the one observed ordinary renewal opportunity. It cannot
/// poll, refresh, mutate time, manufacture expiry, or retry a provider request.
public final class RenewalObserver {
    private let eligibility: BrowserProofEligibility
    private let verifyAuthenticatedReplacement: () -> Bool
    private var terminalProof: RenewalProof?

    public init(
        eligibility: BrowserProofEligibility,
        verifyAuthenticatedReplacement: @escaping () -> Bool
    ) {
        self.eligibility = eligibility
        self.verifyAuthenticatedReplacement = verifyAuthenticatedReplacement
    }

    public func observe(_ observation: RenewalObservation) -> RenewalProof {
        guard eligibility.permitsVolatileWork else { return .notApplicable }
        if let terminalProof { return terminalProof }

        switch observation {
        case .ordinaryProviderReplacement:
            return verifyAuthenticatedReplacement() ? .renewed : closeTerminal(.ambiguous)
        case .ownerEnded:
            return .renewalPending
        case .protectedBehavior:
            return closeTerminal(.protectedControl)
        case .ambiguous:
            return closeTerminal(.ambiguous)
        }
    }

    private func closeTerminal(_ reason: SafeTerminalReason) -> RenewalProof {
        let proof = RenewalProof.terminal(reason)
        terminalProof = proof
        return proof
    }
}
