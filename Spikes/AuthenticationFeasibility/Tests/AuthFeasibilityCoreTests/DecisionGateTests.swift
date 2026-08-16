import Testing
@testable import AuthFeasibilityCore

@Test("only two ordered same-path complete proof runs unlock a decision")
func exactTwoRunProofIsRequired() throws {
    let evidence = EvidenceRecord(
        revision: "offline-tracer-v1",
        roundedDate: "1970-01-01",
        browser: .complete,
        browserReference: "synthetic-reference",
        native: .unavailable,
        candidateCount: 1
    )
    let selection = CandidateSelection.derive(evidence)
    #expect(selection.path == .browserReturn)

    let oneStop = OwnerResult(
        evidenceRevision: evidence.revision,
        selectedPath: .browserReturn,
        runs: [ProofRun(label: "run-1", path: .browserReturn, outcome: .challenge)],
        cooldown: "not-applicable"
    )
    let blocked = try DecisionGate.derive(evidence: evidence, selection: selection, ownerResult: oneStop)
    #expect(blocked.value == "NO-GO unsupported")

    let complete = OwnerResult(
        evidenceRevision: evidence.revision,
        selectedPath: .browserReturn,
        runs: [
            ProofRun(label: "run-1", path: .browserReturn, outcome: .pass),
            ProofRun(label: "run-2", path: .browserReturn, outcome: .pass),
        ],
        cooldown: "owner-confirmed"
    )
    let unlocked = try DecisionGate.derive(evidence: evidence, selection: selection, ownerResult: complete)
    #expect(unlocked.value == "GO browser-return")
    #expect(unlocked.continuation == .unlocked)

    let malformed = OwnerResult(
        evidenceRevision: evidence.revision,
        selectedPath: .browserReturn,
        runs: [
            ProofRun(label: "run-2", path: .browserReturn, outcome: .pass),
            ProofRun(label: "run-1", path: .nativeDirect, outcome: .pass),
        ],
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
