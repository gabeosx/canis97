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

@Test("concurrent cleanup callers share one teardown pass")
@MainActor
func concurrentCleanupIsCoalesced() async {
    let participant = CleanupParticipantSpy(suspendFirstStep: true)
    let coordinator = CleanupCoordinator(participant: participant)

    async let first = coordinator.cleanUp()
    async let second = coordinator.cleanUp()

    #expect(await first == .verified)
    #expect(await second == .verified)
    #expect(participant.steps == [.signOut, .cancelEphemeralClient, .tearDownBrowser, .tearDownPlayback, .clearVolatileState, .verifyLocalAbsence])
}

@MainActor
private final class CleanupParticipantSpy: VolatileCleanupParticipant {
    let failing: CleanupStep?
    let suspendFirstStep: Bool
    private(set) var steps: [CleanupStep] = []

    init(failing: CleanupStep? = nil, suspendFirstStep: Bool = false) {
        self.failing = failing
        self.suspendFirstStep = suspendFirstStep
    }

    func perform(_ step: CleanupStep) async -> Bool {
        steps.append(step)
        if suspendFirstStep, steps.count == 1 {
            await Task.yield()
        }
        return step != failing
    }
}
