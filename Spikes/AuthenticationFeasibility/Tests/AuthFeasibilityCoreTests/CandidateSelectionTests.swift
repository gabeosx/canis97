import Testing
@testable import AuthFeasibilityCore

@Test("candidate selection blocks zero, multiple, and native-before-rule-out evidence")
func candidateSelectionIsBrowserFirstAndSingular() throws {
    let zero = EvidenceRecord(
        revision: "empirical-proof-v2",
        roundedDate: "1970-01-01",
        browser: .unavailable,
        native: .unavailable,
        candidateCount: 0
    )
    #expect(try CandidateSelection.derive(zero).path == .unsupported)

    let nativeBeforeRuleOut = EvidenceRecord(
        revision: "empirical-proof-v2",
        roundedDate: "1970-01-01",
        browser: .unavailable,
        native: .complete,
        nativeReference: "not-a-reference",
        candidateCount: 1
    )
    #expect(isInvalid { try CandidateSelection.derive(nativeBeforeRuleOut) })

    var latch = CandidateLatch()
    #expect(try latch.latch(zero) == .unsupported)
    #expect(try latch.latch(zero) == .unsupported)
}

private func isInvalid<T>(_ operation: () throws -> T) -> Bool {
    do {
        _ = try operation()
        return false
    } catch {
        return true
    }
}
