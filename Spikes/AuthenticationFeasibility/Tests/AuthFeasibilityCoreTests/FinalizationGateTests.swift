import Testing
@testable import AuthFeasibilityCore

@Test("finalization keeps unresolved prerequisites closed without creating a terminal decision")
func prerequisiteIncompleteStatesRemainBlocked() {
    let incompleteStates: [FinalizationState] = [
        .environmentPending,
        .safeConstructionIncomplete,
        .ordinaryBrowserNoCleanReturn,
        .browserRenewalPending,
        .nativePurposeIncomplete,
    ]

    for state in incompleteStates {
        #expect(FinalizationGate.derive(for: state) == .incomplete)
    }
}

@Test("finalization maps explicit terminal and completed branches to their single decisions")
func finalizationUsesTheExhaustiveClosedStateTable() {
    #expect(FinalizationGate.derive(for: .browserTerminal) == .terminal(.unsupported))
    #expect(FinalizationGate.derive(for: .nativeTerminal) == .terminal(.unsupported))
    #expect(FinalizationGate.derive(for: .browserComplete) == .terminal(.browserReturn))
    #expect(FinalizationGate.derive(for: .qualifiedNativeComplete) == .terminal(.nativeDirect))
}

@Test("renewal pending cannot be elevated to a Phase 1 GO")
func renewalPendingIsNeverTerminal() {
    #expect(FinalizationGate.derive(for: .browserRenewalPending) != .terminal(.browserReturn))
    #expect(FinalizationGate.derive(for: .browserRenewalPending) != .terminal(.nativeDirect))
}
