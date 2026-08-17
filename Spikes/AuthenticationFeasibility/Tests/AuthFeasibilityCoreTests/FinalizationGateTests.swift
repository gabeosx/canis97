import Testing
@testable import AuthFeasibilityCore

@Test("unsupported entitlement closes with no owner runs")
func unsupportedEntitlementDerivesBlockedNoGoWithoutRuns() throws {
    let owner = try V3Finalization.ownerResult(
        entitlement: .unsupported,
        browserProbe: .unsupported,
        suppliedOwnerResult: nil
    )
    #expect(owner == .zeroRunUnsupported)

    let result = try V3Finalization.derive(
        entitlement: .unsupported,
        browserProbe: .unsupported,
        ownerResult: owner
    )

    #expect(result.decision == "NO-GO unsupported")
    #expect(result.continuation == .blocked)

    #expect(throws: ContractError.self) {
        _ = try V3Finalization.ownerResult(
            entitlement: .supported,
            browserProbe: .supported,
            suppliedOwnerResult: nil
        )
    }
}

@Test("supported entitlement requires a complete canonical v3 quartet before Phase 1 GO")
func supportedEntitlementRequiresTwoCompleteV3Runs() throws {
    let complete = OwnerResultV3(
        runs: [.complete(label: "run-1"), .complete(label: "run-2")],
        cooldown: "owner-confirmed"
    )
    let bundle = try V3ArtifactBundle.derive(entitlement: .supported, browserProbe: .supported, ownerResult: complete)
    try bundle.validate()
    try PhaseOneGate.require(bundle)

    #expect(throws: ContractError.self) {
        _ = try V3Finalization.derive(entitlement: .supported, browserProbe: .supported, ownerResult: .zeroRunUnsupported)
    }
    #expect(throws: ContractError.self) {
        _ = try V3Finalization.derive(entitlement: .supported, browserProbe: .unsupported, ownerResult: complete)
    }

    let tampered = V3ArtifactBundle(
        evidence: bundle.evidence,
        selection: bundle.selection,
        ownerResult: bundle.ownerResult,
        decision: bundle.decision.replacingOccurrences(of: "GO browser-return", with: "NO-GO unsupported")
    )
    #expect(throws: ContractError.self) { try tampered.validate() }
    #expect(!bundle.evidence.contains("token"))
    #expect(!bundle.ownerResult.contains("cookie"))
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
