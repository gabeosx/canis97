import Testing
@testable import AuthFeasibilityCore

@Test("only two ordered same-path complete proof runs unlock a decision")
func exactTwoRunProofIsRequired() throws {
    let evidence = EvidenceRecord(
        revision: "empirical-proof-v2",
        roundedDate: "1970-01-01",
        browser: .complete,
        browserReference: "https://www.siriusxm.com",
        native: .unavailable,
        candidateCount: 1
    )
    let selection = try CandidateSelection.derive(evidence)
    #expect(selection.path == .browserReturn)

    let incomplete = OwnerResult(
        evidenceRevision: evidence.revision,
        selectedPath: .browserReturn,
        runs: [
            ProofRun.complete(label: "run-1", path: .browserReturn, renewed: false),
            ProofRun.complete(label: "run-2", path: .browserReturn, renewed: false),
        ],
        cooldown: "owner-confirmed"
    )
    #expect(isInvalid { try DecisionGate.derive(evidence: evidence, selection: selection, ownerResult: incomplete) })

    let complete = OwnerResult(
        evidenceRevision: evidence.revision,
        selectedPath: .browserReturn,
        runs: [
            ProofRun.complete(label: "run-1", path: .browserReturn, renewed: false),
            ProofRun.complete(label: "run-2", path: .browserReturn, renewed: true),
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
            ProofRun.complete(label: "run-2", path: .browserReturn, renewed: false),
            ProofRun.complete(label: "run-1", path: .nativeDirect, renewed: true),
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
