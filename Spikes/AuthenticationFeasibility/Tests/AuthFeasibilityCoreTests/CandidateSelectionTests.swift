import Testing
@testable import AuthFeasibilityCore

@Test("candidate selection blocks zero, multiple, and native-before-rule-out evidence")
func candidateSelectionIsBrowserFirstAndSingular() throws {
    let zero = EvidenceRecord(
        revision: "offline-tracer-v1",
        roundedDate: "1970-01-01",
        browser: .unavailable,
        native: .unavailable,
        candidateCount: 0
    )
    #expect(CandidateSelection.derive(zero).path == .unsupported)

    let nativeBeforeRuleOut = EvidenceRecord(
        revision: "offline-tracer-v1",
        roundedDate: "1970-01-01",
        browser: .unavailable,
        native: .complete,
        nativeReference: "not-a-reference",
        candidateCount: 1
    )
    #expect(CandidateSelection.derive(nativeBeforeRuleOut).path == .unsupported)

    var latch = CandidateLatch()
    #expect(latch.latch(zero) == .unsupported)
    #expect(latch.latch(zero) == .unsupported)
}
