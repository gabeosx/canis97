public enum RunOutcome: String, CaseIterable, Sendable {
    case pass = "authenticated-entitled-signed-out"
    case rejected
    case captcha
    case challenge
    case mfaUnavailable = "mfa-unavailable"
    case forbidden = "403"
    case rateLimited = "429"
    case unexpectedRedirect = "unexpected-redirect"
    case suspectedBot = "suspected-bot"
    case protectedControl = "protected-control"
    case cleanupFailed = "cleanup-failed"
    case unknown
    case ambiguous

    public var isTerminalStop: Bool { self != .pass }
}

/// A deliberately narrow run ledger: it can only remember that the first stop closed the run.
/// It has no retry count, queue, timer, fallback path, or operation hook.
public struct TerminalRunLedger: Sendable {
    public private(set) var terminalOutcome: RunOutcome?

    public init() {}

    public var isTerminal: Bool { terminalOutcome != nil }

    @discardableResult
    public mutating func record(_ outcome: RunOutcome) -> CandidatePath {
        guard terminalOutcome == nil else { return .unsupported }
        guard outcome.isTerminalStop else { return .unsupported }
        terminalOutcome = outcome
        return .unsupported
    }
}

public struct ProofRun: Equatable, Sendable {
    public let label: String
    public let path: CandidatePath
    public let outcome: RunOutcome
    public let authentication: String
    public let entitlement: String
    public let tuneKey: String
    public let audiblePlayback: String
    public let signedOut: String
    public let cleanup: String
    public let renewal: String

    public init(
        label: String,
        path: CandidatePath,
        outcome: RunOutcome,
        authentication: String = "not-observed",
        entitlement: String = "not-observed",
        tuneKey: String = "not-observed",
        audiblePlayback: String = "not-observed",
        signedOut: String = "not-observed",
        cleanup: String = "not-observed",
        renewal: String = "not-observed"
    ) {
        self.label = label
        self.path = path
        self.outcome = outcome
        self.authentication = authentication
        self.entitlement = entitlement
        self.tuneKey = tuneKey
        self.audiblePlayback = audiblePlayback
        self.signedOut = signedOut
        self.cleanup = cleanup
        self.renewal = renewal
    }

    public static func complete(label: String, path: CandidatePath, renewed: Bool) -> ProofRun {
        ProofRun(
            label: label,
            path: path,
            outcome: .pass,
            authentication: "complete",
            entitlement: "complete",
            tuneKey: "authorized",
            audiblePlayback: "audible",
            signedOut: "complete",
            cleanup: "verified",
            renewal: renewed ? "renewed" : "not-observed"
        )
    }

    var canonicalValue: String {
        [label, path.rawValue, outcome.rawValue, authentication, entitlement, tuneKey, audiblePlayback, signedOut, cleanup, renewal]
            .joined(separator: "|")
    }

    func isComplete(allowingRenewal renewalValue: String) -> Bool {
        outcome == .pass && authentication == "complete" && entitlement == "complete" && tuneKey == "authorized" && audiblePlayback == "audible" && signedOut == "complete" && cleanup == "verified" && renewal == renewalValue
    }
}

public struct OwnerResult: Equatable, Sendable {
    public let evidenceRevision: String
    public let selectedPath: CandidatePath
    public let runs: [ProofRun]
    public let cooldown: String
    public let cleanup: String

    public init(evidenceRevision: String, selectedPath: CandidatePath, runs: [ProofRun], cooldown: String, cleanup: String = "verified") {
        self.evidenceRevision = evidenceRevision
        self.selectedPath = selectedPath
        self.runs = runs
        self.cooldown = cooldown
        self.cleanup = cleanup
    }

    public static func zeroRunUnsupported(revision: String) -> OwnerResult {
        OwnerResult(evidenceRevision: revision, selectedPath: .unsupported, runs: [], cooldown: "not-applicable")
    }

    public var canonicalText: String {
        let runOne = runs.indices.contains(0) ? runs[0].canonicalValue : "none"
        let runTwo = runs.indices.contains(1) ? runs[1].canonicalValue : "none"
        return [
            "Schema: owner-result-v2",
            "Evidence revision: \(evidenceRevision)",
            "Selected path: \(selectedPath.rawValue)",
            "Run count: \(runs.count)",
            "Run 1: \(runOne)",
            "Cooldown: \(cooldown)",
            "Run 2: \(runTwo)",
            "Cleanup: \(cleanup)",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> OwnerResult {
        let fields = try ArtifactFields.parse(text, ordered: [
            "Schema", "Evidence revision", "Selected path", "Run count", "Run 1", "Cooldown", "Run 2", "Cleanup",
        ])
        guard fields["Schema"] == "owner-result-v2",
              let revision = fields["Evidence revision"], ArtifactFields.isRevisionTwo(revision),
              let pathValue = fields["Selected path"], let path = CandidatePath(rawValue: pathValue),
              let countValue = fields["Run count"], let count = Int(countValue), (0...2).contains(count),
              let runOneValue = fields["Run 1"], let cooldown = fields["Cooldown"],
              let runTwoValue = fields["Run 2"], fields["Cleanup"] == "verified" else {
            throw ContractError.invalidArtifact
        }
        let values = [runOneValue, runTwoValue]
        let runs = try values.enumerated().compactMap { index, value -> ProofRun? in
            if value == "none" { return nil }
            let pieces = value.split(separator: "|", omittingEmptySubsequences: false)
            guard pieces.count == 10,
                  let runPath = CandidatePath(rawValue: String(pieces[1])),
                  let outcome = RunOutcome(rawValue: String(pieces[2])) else {
                throw ContractError.invalidArtifact
            }
            let label = String(pieces[0])
            guard label == "run-\(index + 1)" else { throw ContractError.invalidArtifact }
            return ProofRun(
                label: label,
                path: runPath,
                outcome: outcome,
                authentication: String(pieces[3]),
                entitlement: String(pieces[4]),
                tuneKey: String(pieces[5]),
                audiblePlayback: String(pieces[6]),
                signedOut: String(pieces[7]),
                cleanup: String(pieces[8]),
                renewal: String(pieces[9])
            )
        }
        guard runs.count == count else { throw ContractError.invalidArtifact }
        let result = OwnerResult(evidenceRevision: revision, selectedPath: path, runs: runs, cooldown: cooldown)
        try result.validate()
        guard result.canonicalText == text else { throw ContractError.invalidArtifact }
        return result
    }

    public func validate() throws {
        guard ArtifactFields.isRevisionTwo(evidenceRevision), cleanup == "verified" else {
            throw ContractError.invalidArtifact
        }
        if selectedPath == .unsupported {
            guard runs.isEmpty, cooldown == "not-applicable" else { throw ContractError.invalidArtifact }
            return
        }
        guard runs.count == 2,
              runs[0].label == "run-1", runs[1].label == "run-2",
              runs[0].path == selectedPath, runs[1].path == selectedPath,
              runs[0].isComplete(allowingRenewal: "renewed") || runs[0].isComplete(allowingRenewal: "not-observed"),
              runs[1].isComplete(allowingRenewal: "renewed") || runs[1].isComplete(allowingRenewal: "not-observed"),
              runs.contains(where: { $0.renewal == "renewed" }), cooldown == "owner-confirmed" else {
            throw ContractError.invalidArtifact
        }
    }
}

public enum DecisionGate {
    public static func incompleteEvidenceDecision() -> Decision {
        Decision(.unsupported, evidenceRevision: "phase-0-empirical-v2", selectedPath: .unsupported)
    }

    public static func derive(
        evidence: EvidenceRecord,
        selection: Selection,
        ownerResult: OwnerResult
    ) throws -> Decision {
        try evidence.validate()
        try CandidateSelection.validate(selection, against: evidence)
        guard ownerResult.evidenceRevision == evidence.revision,
              ownerResult.selectedPath == selection.path else {
            throw ContractError.invalidArtifact
        }
        try ownerResult.validate()

        switch selection.path {
        case .unsupported:
            guard ownerResult.runs.isEmpty else { throw ContractError.invalidArtifact }
            return Decision(.unsupported, evidenceRevision: evidence.revision, selectedPath: .unsupported)
        case .browserReturn:
            return decisionForSupportedPath(.browserReturn, evidence: evidence, ownerResult: ownerResult)
        case .nativeDirect:
            return decisionForSupportedPath(.nativeDirect, evidence: evidence, ownerResult: ownerResult)
        }
    }

    private static func decisionForSupportedPath(
        _ path: FeasibilityDecision,
        evidence: EvidenceRecord,
        ownerResult: OwnerResult
    ) -> Decision {
        if ownerResult.runs.count == 2 {
            return Decision(path, evidenceRevision: evidence.revision, selectedPath: ownerResult.selectedPath)
        }
        return Decision(.unsupported, evidenceRevision: evidence.revision, selectedPath: .unsupported)
    }

    public static func validate(_ decision: Decision, evidence: EvidenceRecord, selection: Selection, ownerResult: OwnerResult) throws {
        let derived = try derive(evidence: evidence, selection: selection, ownerResult: ownerResult)
        guard decision == derived else {
            throw ContractError.invalidArtifact
        }
    }
}

public struct ArtifactBundle: Sendable {
    public let evidence: String
    public let selection: String
    public let ownerResult: String
    public let decision: String

    public init(evidence: String, selection: String, ownerResult: String, decision: String) {
        self.evidence = evidence
        self.selection = selection
        self.ownerResult = ownerResult
        self.decision = decision
    }

    public func validate(firstPartyHost: String = "siriusxm.com") throws {
        let parsedEvidence = try EvidenceRecord.parse(evidence, firstPartyHost: firstPartyHost)
        let parsedSelection = try Selection.parse(selection)
        let parsedOwnerResult = try OwnerResult.parse(ownerResult)
        let parsedDecision = try Decision.parse(decision)
        try parsedEvidence.validate(firstPartyHost: firstPartyHost)
        try CandidateSelection.validate(parsedSelection, against: parsedEvidence)
        try DecisionGate.validate(parsedDecision, evidence: parsedEvidence, selection: parsedSelection, ownerResult: parsedOwnerResult)
    }

    public static func canonicalUnsupported(reason: ClosureReason) -> ArtifactBundle {
        let evidence = EvidenceRecord.canonicalUnsupported(reason: reason)
        let selection = try! CandidateSelection.derive(evidence)
        let owner = OwnerResult.zeroRunUnsupported(revision: evidence.revision)
        let decision = try! DecisionGate.derive(evidence: evidence, selection: selection, ownerResult: owner)
        return ArtifactBundle(
            evidence: evidence.canonicalText,
            selection: selection.canonicalText,
            ownerResult: owner.canonicalText,
            decision: decision.canonicalText
        )
    }
}
