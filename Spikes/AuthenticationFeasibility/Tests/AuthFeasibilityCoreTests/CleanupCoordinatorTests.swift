import Testing
@testable import AuthFeasibilityCore

@Test("cleanup has a fixed teardown order and is idempotent after verified absence")
@MainActor
func cleanupIsOrderedVerifiedAndIdempotent() async {
    let participant = CleanupParticipantSpy()
    let coordinator = CleanupCoordinator(participant: participant)

    #expect(await coordinator.cleanUp() == .verified)
    #expect(await coordinator.cleanUp() == .verified)
    #expect(participant.steps == [.signOut, .cancelEphemeralClient, .tearDownBrowser, .tearDownPlayback, .clearVolatileState, .verifyLocalAbsence])
}

@Test("failed absence verification cannot be reported as cleanup complete")
@MainActor
func cleanupFailureRemainsClosed() async {
    let participant = CleanupParticipantSpy(failing: .verifyLocalAbsence)
    let coordinator = CleanupCoordinator(participant: participant)

    #expect(await coordinator.cleanUp() == .failed)
    #expect(await coordinator.cleanUp() == .failed)
    #expect(participant.steps.last == .verifyLocalAbsence)
}

@MainActor
private final class CleanupParticipantSpy: VolatileCleanupParticipant {
    let failing: CleanupStep?
    private(set) var steps: [CleanupStep] = []

    init(failing: CleanupStep? = nil) {
        self.failing = failing
    }

    func perform(_ step: CleanupStep) async -> Bool {
        steps.append(step)
        return step != failing
    }
}
