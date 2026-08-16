import Testing
@testable import AuthFeasibilityCore

@Test("incomplete synthetic evidence ends in the blocked decision")
func incompleteEvidenceProducesBlockedDecision() {
    let decision = DecisionGate.incompleteEvidenceDecision()

    #expect(decision.value == "NO-GO unsupported")
    #expect(decision.continuation == .blocked)
}

@Test("decision artifacts accept one exact decision and compatible continuation")
func decisionSchemaIsStrict() throws {
    let valid = Decision(.unsupported, evidenceRevision: "offline-tracer-v1", selectedPath: .unsupported).canonicalText
    #expect(try Decision.parse(valid).continuation == .blocked)

    let duplicate = valid.replacingOccurrences(of: "Phase 1 continuation: blocked\n", with: "Phase 1 continuation: blocked\nPhase 1 continuation: blocked\n")
    #expect(isInvalid { try Decision.parse(duplicate) })

    let conflicting = valid.replacingOccurrences(of: "Phase 1 continuation: blocked", with: "Phase 1 continuation: unlocked")
    #expect(isInvalid { try Decision.parse(conflicting) })

    let extra = String(valid.dropLast()) + "\nUntrusted: content\n"
    #expect(isInvalid { try Decision.parse(extra) })
}

@Test("evidence rejects malformed and non-public candidate references")
func evidenceValidationFailsClosed() {
    let incomplete = EvidenceRecord(
        revision: "offline-tracer-v1",
        roundedDate: "1970-01-01",
        browser: .complete,
        browserReference: "not-a-reference",
        native: .unavailable,
        candidateCount: 1
    ).canonicalText
    #expect(isInvalid { try EvidenceRecord.parse(incomplete) })

    let canary = ArtifactBundle.canonicalUnsupported(reason: .invalidArtifact)
    #expect(!canary.evidence.contains("synthetic-secret"))
    #expect(!canary.decision.contains("callback"))
    let secretBearing = String(canary.evidence.dropLast()) + "\nSecret: synthetic-secret\n"
    #expect(isInvalid { try EvidenceRecord.parse(secretBearing) })
}

@Test("canonical unsupported closure is a fully validated, blocked bundle")
func unsupportedClosureIsCanonical() throws {
    let bundle = ArtifactBundle.canonicalUnsupported(reason: .browserToolingUnavailable)
    try bundle.validate()
    let decision = try Decision.parse(bundle.decision)
    #expect(decision.value == "NO-GO unsupported")
    #expect(decision.continuation == .blocked)
}

private func isInvalid<T>(_ operation: () throws -> T) -> Bool {
    do {
        _ = try operation()
        return false
    } catch {
        return true
    }
}
