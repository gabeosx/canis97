public struct Selection: Equatable, Sendable {
    public let path: CandidatePath
    public let evidenceRevision: String

    public init(path: CandidatePath, evidenceRevision: String) {
        self.path = path
        self.evidenceRevision = evidenceRevision
    }

    public var liveAttemptPermitted: String {
        path == .unsupported ? "prohibited" : "owner-only"
    }

    public var canonicalText: String {
        [
            "Schema: selection-v1",
            "Evidence revision: \(evidenceRevision)",
            "Selected candidate: \(path.rawValue)",
            "Live attempt permitted: \(liveAttemptPermitted)",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> Selection {
        let fields = try ArtifactFields.parse(text, allowed: [
            "Schema", "Evidence revision", "Selected candidate", "Live attempt permitted",
        ])
        guard fields["Schema"] == "selection-v1",
              let revision = fields["Evidence revision"], ArtifactFields.isOpaque(revision),
              let value = fields["Selected candidate"], let path = CandidatePath(rawValue: value),
              fields["Live attempt permitted"] == (path == .unsupported ? "prohibited" : "owner-only") else {
            throw ContractError.invalidArtifact
        }
        return Selection(path: path, evidenceRevision: revision)
    }
}

public enum CandidateSelection {
    public static func derive(_ evidence: EvidenceRecord) -> Selection {
        let path: CandidatePath
        if evidence.candidateCount != 1 {
            path = .unsupported
        } else if evidence.browser == .complete {
            path = .browserReturn
        } else if evidence.browser == .ruledOut && evidence.native == .complete {
            path = .nativeDirect
        } else {
            path = .unsupported
        }
        return Selection(path: path, evidenceRevision: evidence.revision)
    }

    public static func validate(_ selection: Selection, against evidence: EvidenceRecord) throws {
        guard selection == derive(evidence) else { throw ContractError.invalidArtifact }
    }
}

public struct CandidateLatch: Sendable {
    public private(set) var selectedPath: CandidatePath?

    public init() {}

    public mutating func latch(_ evidence: EvidenceRecord) -> CandidatePath {
        guard selectedPath == nil else { return .unsupported }
        let selected = CandidateSelection.derive(evidence).path
        selectedPath = selected
        return selected
    }
}
