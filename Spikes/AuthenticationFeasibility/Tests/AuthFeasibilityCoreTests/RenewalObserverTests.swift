import Testing
@testable import AuthFeasibilityCore

@Test("blocked renewal branches do not inspect or verify provider work")
func blockedRenewalDoesNotInvokeVerifier() {
    var verificationCount = 0
    let observer = RenewalObserver(eligibility: .constructionIncomplete) {
        verificationCount += 1
        return true
    }

    #expect(observer.observe(.ordinaryProviderReplacement) == .notApplicable)
    #expect(verificationCount == 0)
}

@Test("only a verified distinct ordinary provider replacement counts as renewal")
func renewalRequiresVerifiedReplacement() {
    let verified = RenewalObserver(eligibility: .qualified) { true }
    let rejected = RenewalObserver(eligibility: .qualified) { false }

    #expect(verified.observe(.ordinaryProviderReplacement) == .renewed)
    #expect(rejected.observe(.ordinaryProviderReplacement) == .terminal(.ambiguous))
}

@Test("owner-ended renewal observation remains pending and never becomes a terminal decision")
func ownerEndedObservationIsRenewalPending() {
    var verificationCount = 0
    let observer = RenewalObserver(eligibility: .qualified) {
        verificationCount += 1
        return true
    }

    #expect(observer.observe(.ownerEnded) == .renewalPending)
    #expect(observer.observe(.ordinaryProviderReplacement) == .renewalPending)
    #expect(verificationCount == 0)
}

@Test("owner renewal status has only closed non-secret labels")
func renewalStatusUsesClosedOwnerLabels() {
    #expect(RenewalStatus(proof: .renewalPending).ownerVisibleText == "Renewal pending")
    #expect(RenewalStatus(proof: .renewed).ownerVisibleText == "Renewal verified")
    #expect(RenewalStatus(proof: .terminal(.ambiguous)).ownerVisibleText == "Terminal stop")
    #expect(RenewalStatus(proof: .notApplicable).ownerVisibleText == "Terminal stop")
}

@Test("protected renewal behavior latches a terminal result without retry")
func protectedRenewalBehaviorStopsOnce() {
    let observer = RenewalObserver(eligibility: .qualified) { true }

    #expect(observer.observe(.protectedBehavior) == .terminal(.protectedControl))
    #expect(observer.observe(.ordinaryProviderReplacement) == .terminal(.protectedControl))
}
