import Foundation
import Testing
@testable import AuthFeasibilityCore
@testable import AuthFeasibilityHarness

@Test("only an exact digest-bound approval can prepare the owner-operated browser")
@MainActor
func browserConstructionRequiresExactApproval() throws {
    let contract = AuthExperimentContract.readyForBrowserExperiment()
    let approval = try ExperimentApproval.record(for: contract)

    let session = try WebLoginSession(contract: contract, approval: approval)

    #expect(session.state == .awaitingOwnerStart)
    #expect(session.observedEvent(for: URL(string: "https://www.siriusxm.com/library")!) == .ordinaryFirstPartyNavigation)
    #expect(session.observedEvent(for: URL(string: "siriusmac-auth://browser-return")!) == .matchedAppBoundReturn)
    #expect(session.observedEvent(for: URL(string: "https://example.invalid/")!) == .terminal(.offProvenanceNavigation))

    var changed = contract
    changed.browser.stopBounds = .open
    #expect(throws: ContractError.self) {
        try WebLoginSession(contract: changed, approval: approval)
    }
}

@Test("browser construction fails closed for a digest mismatch")
@MainActor
func browserConstructionRejectsDigestMismatch() throws {
    let contract = AuthExperimentContract.readyForBrowserExperiment()
    var changed = contract
    changed.browser.authenticationExpectation = .open
    let approval = try ExperimentApproval.record(for: contract)

    #expect(throws: ContractError.self) {
        try WebLoginSession(contract: changed, approval: approval)
    }
}
