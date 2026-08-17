import Testing
@testable import AuthFeasibilityCore

@Test("complete browser proof requires the fixed semantic sequence and verified cleanup")
func completeBrowserPreflightRequiresEveryStep() {
    var preflight = BrowserProofPreflight()
    let events: [SafeProbeEvent] = [
        .cleanAppBoundReturn,
        .authenticated,
        .entitled,
        .tuneKeyAuthorized,
        .audiblePlayback,
        .renewed,
        .signedOut,
        .cleanupVerified,
    ]

    for event in events.dropLast() {
        #expect(preflight.consume(event) == .awaitingNextStep)
    }
    #expect(preflight.consume(events.last!) == .complete)
    #expect(preflight.consume(.cleanupVerified) == .complete)
}

@Test("renewal pending closes incomplete after cleanup and never serializes complete")
func renewalPendingNeverCompletesBrowserPreflight() {
    var preflight = BrowserProofPreflight()
    for event in [SafeProbeEvent.cleanAppBoundReturn, .authenticated, .entitled, .tuneKeyAuthorized, .audiblePlayback, .renewalPending, .signedOut] {
        #expect(preflight.consume(event) == .awaitingNextStep)
    }

    #expect(preflight.consume(.cleanupVerified) == .renewalPending)
    #expect(!preflight.canSerializeComplete)
}

@Test("unsupported reordered duplicated and failed-cleanup states cannot complete")
func unsafePreflightStatesLatchTerminalOrIncomplete() {
    var reordered = BrowserProofPreflight()
    #expect(reordered.consume(.entitled) == .terminal(.ambiguous))
    #expect(reordered.consume(.cleanAppBoundReturn) == .terminal(.ambiguous))

    var cleanupFailed = BrowserProofPreflight()
    for event in [SafeProbeEvent.cleanAppBoundReturn, .authenticated, .entitled, .tuneKeyAuthorized, .audiblePlayback, .renewed, .signedOut] {
        _ = cleanupFailed.consume(event)
    }
    #expect(cleanupFailed.consume(.cleanupFailed) == .incomplete)
    #expect(!cleanupFailed.canSerializeComplete)
}
