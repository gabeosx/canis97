import Testing
@testable import AuthFeasibilityCore

@Test("unsupported entitlement closes with no owner runs")
func unsupportedEntitlementDerivesBlockedNoGoWithoutRuns() throws {
    let result = try V3Finalization.derive(
        entitlement: .unsupported,
        browserProbe: .unsupported,
        ownerResult: .zeroRunUnsupported
    )

    #expect(result.decision == "NO-GO unsupported")
    #expect(result.continuation == .blocked)
}

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

@Test("Phase 1 entry rejects incomplete, malformed, and noncanonical bundles")
func phaseOneEntryFailsClosedForEveryNonGOInput() throws {
    let incomplete = ArtifactBundle.canonicalRenewalPending()
    #expect(throws: ContractError.self) {
        try PhaseOneGate.require(incomplete)
    }

    let malformed = ArtifactBundle(
        evidence: incomplete.evidence + "Unexpected: value\n",
        selection: incomplete.selection,
        ownerResult: incomplete.ownerResult,
        decision: incomplete.decision
    )
    #expect(throws: ContractError.self) {
        try PhaseOneGate.require(malformed)
    }

    let noncanonical = ArtifactBundle(
        evidence: incomplete.evidence.replacingOccurrences(of: "Rounded date: 1970-01-01", with: "Rounded date: 1970-1-1"),
        selection: incomplete.selection,
        ownerResult: incomplete.ownerResult,
        decision: incomplete.decision
    )
    #expect(throws: ContractError.self) {
        try PhaseOneGate.require(noncanonical)
    }
}
