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

// MARK: - Corrected Phase 0 v3 evidence

/// The only browser result that can participate in the corrected finish line.
/// It deliberately contains no provider/account/session value or raw response.
public enum BrowserProbeV3Outcome: String, Sendable {
    case supported
    case unsupported
}

public struct BrowserProbeV3: Equatable, Sendable {
    public let outcome: BrowserProbeV3Outcome

    public init(outcome: BrowserProbeV3Outcome) {
        self.outcome = outcome
    }

    public static let supported = BrowserProbeV3(outcome: .supported)
    public static let unsupported = BrowserProbeV3(outcome: .unsupported)

    public var canonicalText: String {
        [
            "Schema: browser-probe-v3",
            "Outcome: \(outcome.rawValue)",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> BrowserProbeV3 {
        let fields = try ArtifactFields.parse(text, ordered: ["Schema", "Outcome"])
        guard fields["Schema"] == "browser-probe-v3",
              let value = fields["Outcome"],
              let outcome = BrowserProbeV3Outcome(rawValue: value) else {
            throw ContractError.invalidArtifact
        }
        let probe = BrowserProbeV3(outcome: outcome)
        guard probe.canonicalText == text else { throw ContractError.invalidArtifact }
        return probe
    }
}

public struct V3ProofRun: Equatable, Sendable {
    public let label: String
    public let path: CandidatePath
    public let outcome: RunOutcome
    public let authentication: String
    public let entitlement: String
    public let signedOut: String
    public let cleanup: String

    public init(
        label: String,
        path: CandidatePath,
        outcome: RunOutcome,
        authentication: String,
        entitlement: String,
        signedOut: String,
        cleanup: String
    ) {
        self.label = label
        self.path = path
        self.outcome = outcome
        self.authentication = authentication
        self.entitlement = entitlement
        self.signedOut = signedOut
        self.cleanup = cleanup
    }

    public static func complete(label: String) -> V3ProofRun {
        V3ProofRun(
            label: label,
            path: .browserReturn,
            outcome: .pass,
            authentication: "complete",
            entitlement: "complete",
            signedOut: "complete",
            cleanup: "verified"
        )
    }

    var canonicalValue: String {
        [label, path.rawValue, outcome.rawValue, authentication, entitlement, signedOut, cleanup]
            .joined(separator: "|")
    }

    var isCompleteBrowserReturn: Bool {
        (label == "run-1" || label == "run-2")
            && path == .browserReturn
            && outcome == .pass
            && authentication == "complete"
            && entitlement == "complete"
            && signedOut == "complete"
            && cleanup == "verified"
    }
}

/// Version-three owner evidence intentionally has no renewal, tune/key, or
/// playback fields. Login is necessary but cannot substitute for entitlement.
public struct OwnerResultV3: Equatable, Sendable {
    public let runs: [V3ProofRun]
    public let cooldown: String

    public init(runs: [V3ProofRun], cooldown: String) {
        self.runs = runs
        self.cooldown = cooldown
    }

    public static let zeroRunUnsupported = OwnerResultV3(runs: [], cooldown: "not-applicable")

    public var canonicalText: String {
        let first = runs.indices.contains(0) ? runs[0].canonicalValue : "none"
        let second = runs.indices.contains(1) ? runs[1].canonicalValue : "none"
        return [
            "Schema: owner-result-v3",
            "Run count: \(runs.count)",
            "Run 1: \(first)",
            "Cooldown: \(cooldown)",
            "Run 2: \(second)",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> OwnerResultV3 {
        let fields = try ArtifactFields.parse(text, ordered: ["Schema", "Run count", "Run 1", "Cooldown", "Run 2"])
        guard fields["Schema"] == "owner-result-v3",
              let countText = fields["Run count"], let count = Int(countText), (0...2).contains(count),
              let first = fields["Run 1"], let cooldown = fields["Cooldown"], let second = fields["Run 2"] else {
            throw ContractError.invalidArtifact
        }
        let values = [first, second]
        let runs = try values.enumerated().compactMap { index, value -> V3ProofRun? in
            if value == "none" { return nil }
            let pieces = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard pieces.count == 7,
                  pieces[0] == "run-\(index + 1)",
                  let path = CandidatePath(rawValue: pieces[1]),
                  let outcome = RunOutcome(rawValue: pieces[2]) else {
                throw ContractError.invalidArtifact
            }
            return V3ProofRun(label: pieces[0], path: path, outcome: outcome, authentication: pieces[3], entitlement: pieces[4], signedOut: pieces[5], cleanup: pieces[6])
        }
        guard runs.count == count else { throw ContractError.invalidArtifact }
        let result = OwnerResultV3(runs: runs, cooldown: cooldown)
        try result.validate()
        guard result.canonicalText == text else { throw ContractError.invalidArtifact }
        return result
    }

    public func validate() throws {
        if runs.isEmpty {
            guard cooldown == "not-applicable" else { throw ContractError.invalidArtifact }
            return
        }
        guard runs.count == 2,
              runs[0].label == "run-1", runs[1].label == "run-2",
              runs.allSatisfy(\.isCompleteBrowserReturn),
              cooldown == "owner-confirmed" else {
            throw ContractError.invalidArtifact
        }
    }
}

public struct V3FinalizationResult: Equatable, Sendable {
    public let decision: String
    public let continuation: Continuation
}

/// Corrected finish-line derivation. It never looks at a profile result as
/// entitlement and intentionally owns none of renewal, tuning, or playback.
public enum V3Finalization {
    /// The unsupported branch is deliberately ownerless: it has no runtime
    /// proof to parse, and its sole canonical owner result is zero runs.
    public static func ownerResult(
        entitlement: EntitlementContractStatus,
        browserProbe: BrowserProbeV3,
        suppliedOwnerResult: OwnerResultV3?
    ) throws -> OwnerResultV3 {
        switch entitlement {
        case .unsupported:
            guard browserProbe.outcome == .unsupported else {
                throw ContractError.invalidArtifact
            }
            return .zeroRunUnsupported
        case .supported:
            guard let suppliedOwnerResult else {
                throw ContractError.invalidArtifact
            }
            return suppliedOwnerResult
        }
    }

    public static func derive(
        entitlement: EntitlementContractStatus,
        browserProbe: BrowserProbeV3,
        ownerResult: OwnerResultV3
    ) throws -> V3FinalizationResult {
        try ownerResult.validate()
        switch entitlement {
        case .unsupported:
            guard browserProbe.outcome == .unsupported, ownerResult == .zeroRunUnsupported else {
                throw ContractError.invalidArtifact
            }
            return V3FinalizationResult(decision: FeasibilityDecision.unsupported.rawValue, continuation: .blocked)
        case .supported:
            guard browserProbe.outcome == .supported,
                  ownerResult.runs.count == 2,
                  ownerResult.cooldown == "owner-confirmed" else {
                throw ContractError.invalidArtifact
            }
            return V3FinalizationResult(decision: FeasibilityDecision.browserReturn.rawValue, continuation: .unlocked)
        }
    }
}

/// The v3 quartet is intentionally small and self-verifying. All values are
/// closed semantic outcomes; no input can carry a token, cookie, identity,
/// endpoint, response body, or stream value.
public struct V3ArtifactBundle: Sendable {
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

    public static func derive(
        entitlement: EntitlementContractStatus,
        browserProbe: BrowserProbeV3,
        ownerResult: OwnerResultV3
    ) throws -> V3ArtifactBundle {
        let result = try V3Finalization.derive(
            entitlement: entitlement,
            browserProbe: browserProbe,
            ownerResult: ownerResult
        )
        let path = result.decision == FeasibilityDecision.browserReturn.rawValue ? CandidatePath.browserReturn : .unsupported
        return V3ArtifactBundle(
            evidence: [
                "Schema: evidence-v3",
                "Entitlement: \(entitlement.rawValue)",
                "Browser probe: \(browserProbe.outcome.rawValue)",
                "",
            ].joined(separator: "\n"),
            selection: [
                "Schema: selection-v3",
                "Selected path: \(path.rawValue)",
                "",
            ].joined(separator: "\n"),
            ownerResult: ownerResult.canonicalText,
            decision: [
                "Schema: decision-v3",
                "Feasibility decision: \(result.decision)",
                "Phase 1 continuation: \(result.continuation.rawValue)",
                "",
            ].joined(separator: "\n")
        )
    }

    public func validate() throws {
        let evidenceFields = try ArtifactFields.parse(evidence, ordered: ["Schema", "Entitlement", "Browser probe"])
        guard evidenceFields["Schema"] == "evidence-v3",
              let entitlementText = evidenceFields["Entitlement"], let entitlement = EntitlementContractStatus(rawValue: entitlementText),
              let probeText = evidenceFields["Browser probe"], let outcome = BrowserProbeV3Outcome(rawValue: probeText) else {
            throw ContractError.invalidArtifact
        }
        let selectionFields = try ArtifactFields.parse(selection, ordered: ["Schema", "Selected path"])
        guard selectionFields["Schema"] == "selection-v3",
              let selectedPath = selectionFields["Selected path"].flatMap(CandidatePath.init(rawValue:)) else {
            throw ContractError.invalidArtifact
        }
        let parsedOwner = try OwnerResultV3.parse(ownerResult)
        let decisionFields = try ArtifactFields.parse(decision, ordered: ["Schema", "Feasibility decision", "Phase 1 continuation"])
        guard decisionFields["Schema"] == "decision-v3",
              let value = decisionFields["Feasibility decision"],
              let continuation = decisionFields["Phase 1 continuation"].flatMap(Continuation.init(rawValue:)) else {
            throw ContractError.invalidArtifact
        }
        let derived = try V3Finalization.derive(
            entitlement: entitlement,
            browserProbe: BrowserProbeV3(outcome: outcome),
            ownerResult: parsedOwner
        )
        let expectedPath: CandidatePath = derived.decision == FeasibilityDecision.browserReturn.rawValue ? .browserReturn : .unsupported
        let expectedBundle = try V3ArtifactBundle.derive(
            entitlement: entitlement,
            browserProbe: BrowserProbeV3(outcome: outcome),
            ownerResult: parsedOwner
        )
        guard value == derived.decision, continuation == derived.continuation, selectedPath == expectedPath,
              self == expectedBundle else {
            throw ContractError.invalidArtifact
        }
    }
}

extension V3ArtifactBundle: Equatable {}

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
            return Decision(
                evidence.browser == .renewalPending ? .renewalPending : .unsupported,
                evidenceRevision: evidence.revision,
                selectedPath: .unsupported
            )
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

/// The closed finalization table deliberately separates an unresolved proof
/// state from a terminal feasibility decision. In particular, renewal-pending
/// may never be serialized as either a GO or a terminal unsupported result.
public enum FinalizationState: Equatable, Sendable {
    case environmentPending
    case safeConstructionIncomplete
    case ordinaryBrowserNoCleanReturn
    case browserRenewalPending
    case nativePurposeIncomplete
    case browserTerminal
    case nativeTerminal
    case browserComplete
    case qualifiedNativeComplete
}

public enum FinalizationDisposition: Equatable, Sendable {
    case incomplete
    case terminal(FeasibilityDecision)
}

public enum FinalizationGate {
    public static func derive(for state: FinalizationState) -> FinalizationDisposition {
        switch state {
        case .environmentPending,
             .safeConstructionIncomplete,
             .ordinaryBrowserNoCleanReturn,
             .browserRenewalPending,
             .nativePurposeIncomplete:
            .incomplete
        case .browserTerminal, .nativeTerminal:
            .terminal(.unsupported)
        case .browserComplete:
            .terminal(.browserReturn)
        case .qualifiedNativeComplete:
            .terminal(.nativeDirect)
        }
    }
}

/// The sole Phase 1 authorization boundary. It reparses and rederives the
/// complete quartet before accepting either canonical GO decision.
public enum PhaseOneGate {
    public static func require(_ bundle: ArtifactBundle) throws {
        try bundle.validate()
        // Every v2 bundle is historical blocked input, including a syntactically
        // valid legacy GO. Only the independently rederived v3 quartet can
        // authorize Phase 1.
        throw ContractError.invalidArtifact
    }

    public static func require(_ bundle: V3ArtifactBundle) throws {
        try bundle.validate()
        let fields = try ArtifactFields.parse(bundle.decision, ordered: ["Schema", "Feasibility decision", "Phase 1 continuation"])
        guard fields["Feasibility decision"] == FeasibilityDecision.browserReturn.rawValue,
              fields["Phase 1 continuation"] == Continuation.unlocked.rawValue else {
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

    /// A bounded owner observation that ended before a legitimate replacement
    /// was seen. This is incomplete evidence, not a terminal feasibility result.
    public static func canonicalRenewalPending() -> ArtifactBundle {
        let evidence = EvidenceRecord(
            revision: "phase-0-empirical-v2",
            roundedDate: "1970-01-01",
            browser: .renewalPending,
            native: .unavailable,
            candidateCount: 0
        )
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
