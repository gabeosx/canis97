import Testing
@testable import AuthFeasibilityCore

@Test("incomplete synthetic evidence ends in the blocked decision")
func incompleteEvidenceProducesBlockedDecision() {
    let decision = DecisionGate.incompleteEvidenceDecision()

    #expect(decision.value == "NO-GO unsupported")
    #expect(decision.continuation == .blocked)
}
