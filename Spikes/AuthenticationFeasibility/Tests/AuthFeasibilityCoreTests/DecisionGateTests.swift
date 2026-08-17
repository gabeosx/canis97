import Testing
@testable import AuthFeasibilityCore

@Test("historical v2 owner evidence is rejected by the v3 gate")
func historicalOwnerEvidenceCannotAuthorizePhaseOne() throws {
    let historical = OwnerResult(
        evidenceRevision: "phase-0-empirical-v2",
        selectedPath: .unsupported,
        runs: [],
        cooldown: "not-applicable"
    )

    #expect(throws: ContractError.self) {
        try OwnerResultV3.parse(historical.canonicalText)
    }
}

@Test("v3 owner result requires exactly two ordered browser-return runs and cooldown")
func v3OwnerResultRejectsPartialAndContradictoryRuns() throws {
    let runOne = V3ProofRun.complete(label: "run-1")
    let runTwo = V3ProofRun.complete(label: "run-2")

    #expect(isInvalid { try OwnerResultV3(runs: [runOne], cooldown: "owner-confirmed").validate() })
    #expect(isInvalid { try OwnerResultV3(runs: [runOne, runTwo, runTwo], cooldown: "owner-confirmed").validate() })
    #expect(isInvalid { try OwnerResultV3(runs: [runTwo, runOne], cooldown: "owner-confirmed").validate() })
    #expect(isInvalid { try OwnerResultV3(runs: [runOne, runTwo], cooldown: "not-applicable").validate() })

    let mixed = V3ProofRun(
        label: "run-2",
        path: .nativeDirect,
        outcome: .pass,
        authentication: "complete",
        entitlement: "complete",
        signedOut: "complete",
        cleanup: "verified"
    )
    #expect(isInvalid { try OwnerResultV3(runs: [runOne, mixed], cooldown: "owner-confirmed").validate() })

    let incomplete = V3ProofRun(
        label: "run-2",
        path: .browserReturn,
        outcome: .pass,
        authentication: "complete",
        entitlement: "not-observed",
        signedOut: "complete",
        cleanup: "verified"
    )
    #expect(isInvalid { try OwnerResultV3(runs: [runOne, incomplete], cooldown: "owner-confirmed").validate() })
}

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
