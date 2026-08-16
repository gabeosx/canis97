import Foundation

public enum ContractError: Error, Equatable, Sendable {
    case invalidArtifact
}

public enum CandidatePath: String, CaseIterable, Sendable {
    case browserReturn = "browser-return"
    case nativeDirect = "native-direct"
    case unsupported
}

public enum Continuation: String, Sendable {
    case unlocked
    case blocked
}

public enum FeasibilityDecision: String, CaseIterable, Sendable {
    case browserReturn = "GO browser-return"
    case nativeDirect = "GO native-direct"
    case unsupported = "NO-GO unsupported"

    public var continuation: Continuation {
        switch self {
        case .browserReturn, .nativeDirect: .unlocked
        case .unsupported: .blocked
        }
    }
}

public struct Decision: Equatable, Sendable {
    public let value: String
    public let continuation: Continuation
    public let evidenceRevision: String
    public let selectedPath: CandidatePath

    public init(_ decision: FeasibilityDecision, evidenceRevision: String, selectedPath: CandidatePath) {
        self.value = decision.rawValue
        self.continuation = decision.continuation
        self.evidenceRevision = evidenceRevision
        self.selectedPath = selectedPath
    }

    public var canonicalText: String {
        [
            "Schema: decision-v1",
            "Evidence revision: \(evidenceRevision)",
            "Selected path: \(selectedPath.rawValue)",
            "Feasibility decision: \(value)",
            "Phase 1 continuation: \(continuation.rawValue)",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> Decision {
        let fields = try ArtifactFields.parse(text, allowed: [
            "Schema", "Evidence revision", "Selected path", "Feasibility decision", "Phase 1 continuation",
        ])
        guard fields["Schema"] == "decision-v1",
              let revision = fields["Evidence revision"], ArtifactFields.isOpaque(revision),
              let pathValue = fields["Selected path"], let path = CandidatePath(rawValue: pathValue),
              let decisionValue = fields["Feasibility decision"], let decision = FeasibilityDecision(rawValue: decisionValue),
              let continuationValue = fields["Phase 1 continuation"], let continuation = Continuation(rawValue: continuationValue),
              decision.continuation == continuation,
              decisionPath(decision) == path else {
            throw ContractError.invalidArtifact
        }
        return Decision(decision, evidenceRevision: revision, selectedPath: path)
    }

    private static func decisionPath(_ decision: FeasibilityDecision) -> CandidatePath {
        switch decision {
        case .browserReturn: .browserReturn
        case .nativeDirect: .nativeDirect
        case .unsupported: .unsupported
        }
    }
}

public enum EvidenceState: String, Sendable {
    case complete
    case ruledOut = "ruled-out"
    case unavailable
}

public enum ClosureReason: String, CaseIterable, Sendable {
    case invalidArtifact = "invalid-artifact"
    case unsupportedSelection = "unsupported-selection"
    case browserToolingUnavailable = "browser-tooling-unavailable"
    case candidatePreflightFailed = "candidate-preflight-failed"
}

public struct EvidenceRecord: Equatable, Sendable {
    public let revision: String
    public let roundedDate: String
    public let browser: EvidenceState
    public let browserReference: String
    public let native: EvidenceState
    public let nativeReference: String
    public let candidateCount: Int
    public let closureReason: String

    public init(
        revision: String,
        roundedDate: String,
        browser: EvidenceState,
        browserReference: String = "none",
        native: EvidenceState,
        nativeReference: String = "none",
        candidateCount: Int,
        closureReason: String = "none"
    ) {
        self.revision = revision
        self.roundedDate = roundedDate
        self.browser = browser
        self.browserReference = browserReference
        self.native = native
        self.nativeReference = nativeReference
        self.candidateCount = candidateCount
        self.closureReason = closureReason
    }

    public static func canonicalUnsupported(reason: ClosureReason) -> EvidenceRecord {
        EvidenceRecord(
            revision: "offline-tracer-v1",
            roundedDate: "1970-01-01",
            browser: .unavailable,
            native: .unavailable,
            candidateCount: 0,
            closureReason: reason.rawValue
        )
    }

    public var canonicalText: String {
        [
            "Schema: evidence-v1",
            "Harness revision: \(revision)",
            "Rounded date: \(roundedDate)",
            "Browser return: \(browser.rawValue)",
            "Browser reference: \(browserReference)",
            "Native direct: \(native.rawValue)",
            "Native reference: \(nativeReference)",
            "Candidate count: \(candidateCount)",
            "Closure reason: \(closureReason)",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String, firstPartyHost: String = "siriusxm.com") throws -> EvidenceRecord {
        let fields = try ArtifactFields.parse(text, allowed: [
            "Schema", "Harness revision", "Rounded date", "Browser return", "Browser reference", "Native direct", "Native reference", "Candidate count", "Closure reason",
        ])
        guard fields["Schema"] == "evidence-v1",
              let revision = fields["Harness revision"], ArtifactFields.isOpaque(revision),
              let date = fields["Rounded date"], ArtifactFields.isRoundedDate(date),
              let browserValue = fields["Browser return"], let browser = EvidenceState(rawValue: browserValue),
              let browserReference = fields["Browser reference"],
              let nativeValue = fields["Native direct"], let native = EvidenceState(rawValue: nativeValue),
              let nativeReference = fields["Native reference"],
              let countValue = fields["Candidate count"], let count = Int(countValue), (0...1).contains(count),
              let closeValue = fields["Closure reason"], ArtifactFields.isClosureReasonOrNone(closeValue) else {
            throw ContractError.invalidArtifact
        }

        let record = EvidenceRecord(
            revision: revision,
            roundedDate: date,
            browser: browser,
            browserReference: browserReference,
            native: native,
            nativeReference: nativeReference,
            candidateCount: count,
            closureReason: closeValue
        )
        try record.validate(firstPartyHost: firstPartyHost)
        return record
    }

    public func validate(firstPartyHost: String = "siriusxm.com") throws {
        guard ArtifactFields.isOpaque(revision), ArtifactFields.isRoundedDate(roundedDate),
              ArtifactFields.isClosureReasonOrNone(closureReason), (0...1).contains(candidateCount) else {
            throw ContractError.invalidArtifact
        }

        switch browser {
        case .complete:
            guard candidateCount == 1, native != .complete,
                  ArtifactFields.isCleanFirstPartyReference(browserReference, host: firstPartyHost) else {
                throw ContractError.invalidArtifact
            }
        case .ruledOut, .unavailable:
            guard browserReference == "none" else { throw ContractError.invalidArtifact }
        }

        switch native {
        case .complete:
            guard candidateCount == 1, browser == .ruledOut,
                  ArtifactFields.isCleanFirstPartyReference(nativeReference, host: firstPartyHost) else {
                throw ContractError.invalidArtifact
            }
        case .ruledOut, .unavailable:
            guard nativeReference == "none" else { throw ContractError.invalidArtifact }
        }

        guard (candidateCount == 0) == (browser != .complete && native != .complete) else {
            throw ContractError.invalidArtifact
        }
    }
}

enum ArtifactFields {
    static func parse(_ text: String, allowed: Set<String>) throws -> [String: String] {
        guard text.hasSuffix("\n") else { throw ContractError.invalidArtifact }
        var fields: [String: String] = [:]
        let lines = text.dropLast().split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { throw ContractError.invalidArtifact }
        for line in lines {
            guard !line.isEmpty, let separator = line.firstIndex(of: ":") else {
                throw ContractError.invalidArtifact
            }
            let key = String(line[..<separator])
            let valueStart = line.index(after: separator)
            guard line.indices.contains(valueStart), line[valueStart] == " ", allowed.contains(key) else {
                throw ContractError.invalidArtifact
            }
            let value = String(line[line.index(after: valueStart)...])
            guard !value.isEmpty, fields[key] == nil else { throw ContractError.invalidArtifact }
            fields[key] = value
        }
        guard Set(fields.keys) == allowed else { throw ContractError.invalidArtifact }
        return fields
    }

    static func isOpaque(_ value: String) -> Bool {
        guard (1...64).contains(value.count) else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    static func isRoundedDate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let characters = Array(value)
        return characters.enumerated().allSatisfy { index, character in
            (index == 4 || index == 7) ? character == "-" : character.isNumber
        }
    }

    static func isClosureReasonOrNone(_ value: String) -> Bool {
        value == "none" || ClosureReason(rawValue: value) != nil
    }

    static func isCleanFirstPartyReference(_ value: String, host: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              let referenceHost = components.host?.lowercased(),
              (referenceHost == host || referenceHost.hasSuffix("." + host)),
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            return false
        }
        return true
    }
}
