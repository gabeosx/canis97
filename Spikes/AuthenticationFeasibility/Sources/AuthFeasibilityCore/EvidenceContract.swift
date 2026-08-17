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
    case renewalPending = "INCOMPLETE renewal-pending"
    case unsupported = "NO-GO unsupported"

    public var continuation: Continuation {
        switch self {
        case .browserReturn, .nativeDirect: .unlocked
        case .renewalPending, .unsupported: .blocked
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
            "Schema: decision-v2",
            "Evidence revision: \(evidenceRevision)",
            "Selected path: \(selectedPath.rawValue)",
            "Feasibility decision: \(value)",
            "Phase 1 continuation: \(continuation.rawValue)",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> Decision {
        let fields = try ArtifactFields.parse(text, ordered: [
            "Schema", "Evidence revision", "Selected path", "Feasibility decision", "Phase 1 continuation",
        ])
        guard fields["Schema"] == "decision-v2",
              let revision = fields["Evidence revision"], ArtifactFields.isRevisionTwo(revision),
              let pathValue = fields["Selected path"], let path = CandidatePath(rawValue: pathValue),
              let decisionValue = fields["Feasibility decision"], let decision = FeasibilityDecision(rawValue: decisionValue),
              let continuationValue = fields["Phase 1 continuation"], let continuation = Continuation(rawValue: continuationValue),
              decision.continuation == continuation,
              decisionPath(decision) == path else {
            throw ContractError.invalidArtifact
        }
        let parsed = Decision(decision, evidenceRevision: revision, selectedPath: path)
        guard parsed.canonicalText == text else { throw ContractError.invalidArtifact }
        return parsed
    }

    private static func decisionPath(_ decision: FeasibilityDecision) -> CandidatePath {
        switch decision {
        case .browserReturn: .browserReturn
        case .nativeDirect: .nativeDirect
        case .renewalPending, .unsupported: .unsupported
        }
    }
}

public enum EvidenceState: String, Sendable {
    case complete
    case renewalPending = "renewal-pending"
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
            revision: "phase-0-empirical-v2",
            roundedDate: "1970-01-01",
            browser: .unavailable,
            native: .unavailable,
            candidateCount: 0,
            closureReason: reason.rawValue
        )
    }

    public var canonicalText: String {
        [
            "Schema: evidence-v2",
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
        let fields = try ArtifactFields.parse(text, ordered: [
            "Schema", "Harness revision", "Rounded date", "Browser return", "Browser reference", "Native direct", "Native reference", "Candidate count", "Closure reason",
        ])
        guard fields["Schema"] == "evidence-v2",
              let revision = fields["Harness revision"], ArtifactFields.isRevisionTwo(revision),
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
        guard record.canonicalText == text else { throw ContractError.invalidArtifact }
        return record
    }

    public func validate(firstPartyHost: String = "siriusxm.com") throws {
        guard ArtifactFields.isRevisionTwo(revision), ArtifactFields.isRoundedDate(roundedDate),
              ArtifactFields.isClosureReasonOrNone(closureReason), (0...1).contains(candidateCount) else {
            throw ContractError.invalidArtifact
        }

        if closureReason != "none" {
            guard candidateCount == 0, browser != .complete, native != .complete else {
                throw ContractError.invalidArtifact
            }
        }

        switch browser {
        case .complete:
            guard candidateCount == 1, native != .complete,
                  ArtifactFields.isCleanFirstPartyReference(browserReference, host: firstPartyHost) else {
                throw ContractError.invalidArtifact
            }
        case .renewalPending:
            guard candidateCount == 0, native != .complete, browserReference == "none" else {
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
        case .renewalPending:
            throw ContractError.invalidArtifact
        case .ruledOut, .unavailable:
            guard nativeReference == "none" else { throw ContractError.invalidArtifact }
        }

        guard (candidateCount == 0) == (browser != .complete && native != .complete) else {
            throw ContractError.invalidArtifact
        }
    }
}

/// Canonical result of a bounded browser observation. It intentionally records
/// only the closed result, never activity, session, provider, or account data.
public struct BrowserProbeResult: Equatable, Sendable {
    public let outcome: String

    public static let renewalPending = BrowserProbeResult(outcome: "renewal-pending")

    public var canonicalText: String {
        [
            "Schema: browser-probe-v2",
            "Outcome: \(outcome)",
            "Phase 1 continuation: blocked",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> BrowserProbeResult {
        let fields = try ArtifactFields.parse(text, ordered: ["Schema", "Outcome", "Phase 1 continuation"])
        guard fields["Schema"] == "browser-probe-v2",
              fields["Outcome"] == "renewal-pending",
              fields["Phase 1 continuation"] == "blocked" else {
            throw ContractError.invalidArtifact
        }
        let result = BrowserProbeResult.renewalPending
        guard result.canonicalText == text else { throw ContractError.invalidArtifact }
        return result
    }
}

/// The native password boundary cannot be shown while browser renewal evidence
/// is incomplete. This record makes that closed disposition explicit.
public struct NativeDirectApproval: Equatable, Sendable {
    public static let notApplicable = NativeDirectApproval()

    public init() {}

    public var canonicalText: String {
        [
            "Schema: native-direct-approval-v1",
            "Browser result: renewal-pending",
            "Native direct: not-applicable",
            "Disclosure presented: no",
            "Phase 1 continuation: blocked",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> NativeDirectApproval {
        let fields = try ArtifactFields.parse(text, ordered: [
            "Schema", "Browser result", "Native direct", "Disclosure presented", "Phase 1 continuation",
        ])
        guard fields["Schema"] == "native-direct-approval-v1",
              fields["Browser result"] == "renewal-pending",
              fields["Native direct"] == "not-applicable",
              fields["Disclosure presented"] == "no",
              fields["Phase 1 continuation"] == "blocked" else {
            throw ContractError.invalidArtifact
        }
        let approval = NativeDirectApproval.notApplicable
        guard approval.canonicalText == text else { throw ContractError.invalidArtifact }
        return approval
    }
}

enum ArtifactFields {
    static func parse(_ text: String, ordered: [String]) throws -> [String: String] {
        guard text.hasSuffix("\n") else { throw ContractError.invalidArtifact }
        var fields: [String: String] = [:]
        let lines = text.dropLast().split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count == ordered.count else { throw ContractError.invalidArtifact }
        for (line, expectedKey) in zip(lines, ordered) {
            guard !line.isEmpty, let separator = line.firstIndex(of: ":") else {
                throw ContractError.invalidArtifact
            }
            let key = String(line[..<separator])
            let valueStart = line.index(after: separator)
            guard line.indices.contains(valueStart), line[valueStart] == " ", key == expectedKey else {
                throw ContractError.invalidArtifact
            }
            let value = String(line[line.index(after: valueStart)...])
            guard !value.isEmpty, fields[key] == nil else { throw ContractError.invalidArtifact }
            fields[key] = value
        }
        guard fields.count == ordered.count else { throw ContractError.invalidArtifact }
        return fields
    }

    static func isOpaque(_ value: String) -> Bool {
        guard (1...64).contains(value.count) else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    static func isRoundedDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    static func isRevisionTwo(_ value: String) -> Bool {
        isOpaque(value) && value.hasSuffix("-v2")
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
