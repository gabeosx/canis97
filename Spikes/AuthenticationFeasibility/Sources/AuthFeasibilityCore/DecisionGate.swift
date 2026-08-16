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

public struct ProofRun: Equatable, Sendable {
    public let label: String
    public let path: CandidatePath
    public let outcome: RunOutcome

    public init(label: String, path: CandidatePath, outcome: RunOutcome) {
        self.label = label
        self.path = path
        self.outcome = outcome
    }

    var canonicalValue: String { "\(label)|\(path.rawValue)|\(outcome.rawValue)" }
}

public struct OwnerResult: Equatable, Sendable {
    public let evidenceRevision: String
    public let selectedPath: CandidatePath
    public let runs: [ProofRun]
    public let cooldown: String
    public let cleanup: String

    public init(evidenceRevision: String, selectedPath: CandidatePath, runs: [ProofRun], cooldown: String, cleanup: String = "confirmed") {
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
            "Schema: owner-result-v1",
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
        let fields = try ArtifactFields.parse(text, allowed: [
            "Schema", "Evidence revision", "Selected path", "Run count", "Run 1", "Cooldown", "Run 2", "Cleanup",
        ])
        guard fields["Schema"] == "owner-result-v1",
              let revision = fields["Evidence revision"], ArtifactFields.isOpaque(revision),
              let pathValue = fields["Selected path"], let path = CandidatePath(rawValue: pathValue),
              let countValue = fields["Run count"], let count = Int(countValue), (0...2).contains(count),
              let runOneValue = fields["Run 1"], let cooldown = fields["Cooldown"],
              let runTwoValue = fields["Run 2"], fields["Cleanup"] == "confirmed" else {
            throw ContractError.invalidArtifact
        }
        let values = [runOneValue, runTwoValue]
        let runs = try values.enumerated().compactMap { index, value -> ProofRun? in
            if value == "none" { return nil }
            let pieces = value.split(separator: "|", omittingEmptySubsequences: false)
            guard pieces.count == 3,
                  let runPath = CandidatePath(rawValue: String(pieces[1])),
                  let outcome = RunOutcome(rawValue: String(pieces[2])) else {
                throw ContractError.invalidArtifact
            }
            let label = String(pieces[0])
            guard label == "run-\(index + 1)" else { throw ContractError.invalidArtifact }
            return ProofRun(label: label, path: runPath, outcome: outcome)
        }
        guard runs.count == count else { throw ContractError.invalidArtifact }
        let result = OwnerResult(evidenceRevision: revision, selectedPath: path, runs: runs, cooldown: cooldown)
        try result.validate()
        return result
    }

    public func validate() throws {
        guard ArtifactFields.isOpaque(evidenceRevision), cleanup == "confirmed" else {
            throw ContractError.invalidArtifact
        }
        if selectedPath == .unsupported {
            guard runs.isEmpty, cooldown == "not-applicable" else { throw ContractError.invalidArtifact }
            return
        }
        if runs.count == 1 {
            guard runs[0].path == selectedPath, runs[0].outcome.isTerminalStop,
                  cooldown == "not-applicable" else { throw ContractError.invalidArtifact }
            return
        }
        guard runs.count == 2,
              runs[0].label == "run-1", runs[1].label == "run-2",
              runs[0].path == selectedPath, runs[1].path == selectedPath,
              runs[0].outcome == .pass, runs[1].outcome == .pass,
              cooldown == "owner-confirmed" else {
            throw ContractError.invalidArtifact
        }
    }
}

public enum DecisionGate {
    public static func incompleteEvidenceDecision() -> Decision {
        Decision(.unsupported, evidenceRevision: "offline-tracer-v1", selectedPath: .unsupported)
    }

    public static func derive(
        evidence: EvidenceRecord,
        selection: Selection,
        ownerResult: OwnerResult
    ) throws -> Decision {
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
        return Decision(.unsupported, evidenceRevision: evidence.revision, selectedPath: ownerResult.selectedPath)
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
        try CandidateSelection.validate(parsedSelection, against: parsedEvidence)
        guard parsedSelection.canonicalText == selection else { throw ContractError.invalidArtifact }
        try DecisionGate.validate(parsedDecision, evidence: parsedEvidence, selection: parsedSelection, ownerResult: parsedOwnerResult)
        guard parsedDecision.canonicalText == decision else { throw ContractError.invalidArtifact }
    }

    public static func canonicalUnsupported(reason: ClosureReason) -> ArtifactBundle {
        let evidence = EvidenceRecord.canonicalUnsupported(reason: reason)
        let selection = CandidateSelection.derive(evidence)
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
