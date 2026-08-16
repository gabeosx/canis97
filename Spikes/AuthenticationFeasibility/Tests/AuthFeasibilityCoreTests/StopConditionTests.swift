import Testing
@testable import AuthFeasibilityCore

@Test("the first stop is terminal and cannot be retried or replaced")
func terminalStopLatchesBlockedOutcome() {
    var ledger = TerminalRunLedger()
    #expect(ledger.record(.challenge) == .unsupported)
    #expect(ledger.record(.pass) == .unsupported)
    #expect(ledger.isTerminal)
}
