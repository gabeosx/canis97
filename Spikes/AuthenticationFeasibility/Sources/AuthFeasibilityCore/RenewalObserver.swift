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
    private var resolvedProof: RenewalProof?

    public init(
        eligibility: BrowserProofEligibility,
        verifyAuthenticatedReplacement: @escaping () -> Bool
    ) {
        self.eligibility = eligibility
        self.verifyAuthenticatedReplacement = verifyAuthenticatedReplacement
    }

    public func observe(_ observation: RenewalObservation) -> RenewalProof {
        guard eligibility.permitsVolatileWork else { return .notApplicable }
        if let resolvedProof { return resolvedProof }

        switch observation {
        case .ordinaryProviderReplacement:
            return close(verifyAuthenticatedReplacement() ? .renewed : .terminal(.ambiguous))
        case .ownerEnded:
            return close(.renewalPending)
        case .protectedBehavior:
            return close(.terminal(.protectedControl))
        case .ambiguous:
            return close(.terminal(.ambiguous))
        }
    }

    private func close(_ proof: RenewalProof) -> RenewalProof {
        resolvedProof = proof
        return proof
    }
}
