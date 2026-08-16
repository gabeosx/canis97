import Testing
@testable import AuthFeasibilityCore

@Test("only two ordered same-path complete proof runs unlock a decision")
func exactTwoRunProofIsRequired() throws {
    let evidence = EvidenceRecord.canonicalUnsupported(reason: .invalidArtifact)
    let selection = CandidateSelection.derive(evidence)
    let noRuns = OwnerResult.zeroRunUnsupported(revision: evidence.revision)
    let blocked = try DecisionGate.derive(evidence: evidence, selection: selection, ownerResult: noRuns)
    #expect(blocked.value == "NO-GO unsupported")

    let malformed = OwnerResult(
        evidenceRevision: evidence.revision,
        selectedPath: .unsupported,
        runs: [ProofRun(label: "run-1", path: .unsupported, outcome: .pass)],
        cooldown: "not-applicable"
    )
    #expect(isInvalid { try malformed.validate() })
}

private func isInvalid<T>(_ operation: () throws -> T) -> Bool {
    do {
        _ = try operation()
        return false
    } catch {
        return true
    }
}
