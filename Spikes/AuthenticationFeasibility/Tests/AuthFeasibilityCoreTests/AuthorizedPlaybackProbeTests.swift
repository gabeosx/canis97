import Testing
@testable import AuthFeasibilityCore

@Test("blocked playback branches do not construct volatile playback work")
@MainActor
func blockedPlaybackDoesNotConstructRuntime() async {
    let runtime = PlaybackRuntimeSpy()
    let pending = AuthorizedPlaybackProbe(eligibility: .environmentPending, runtime: runtime)
    let rejected = AuthorizedPlaybackProbe(eligibility: .ownerRejected, runtime: runtime)

    #expect(await pending.prove(expectedAuthorization: .expected, ownerConfirmation: .audible) == .notApplicable)
    #expect(await rejected.prove(expectedAuthorization: .expected, ownerConfirmation: .audible) == .notApplicable)
    #expect(runtime.prepareCount == 0)
    #expect(runtime.clearCount == 0)
}

@Test("qualified playback requires expected key authorization, ready media, and owner audible confirmation")
@MainActor
func qualifiedPlaybackRequiresAllBoundedProofSteps() async {
    let runtime = PlaybackRuntimeSpy(readiness: .ready)
    let probe = AuthorizedPlaybackProbe(eligibility: .qualified, runtime: runtime)

    #expect(await probe.prove(expectedAuthorization: .expected, ownerConfirmation: .notConfirmed) == .incomplete)
    #expect(runtime.prepareCount == 1)
    #expect(runtime.clearCount == 1)

    #expect(await probe.prove(expectedAuthorization: .expected, ownerConfirmation: .audible) == .incomplete)
    #expect(runtime.prepareCount == 1)
    #expect(runtime.clearCount == 1)
}

@Test("unsafe playback outcomes are terminal, cannot retry, and clear volatile state")
@MainActor
func unsafePlaybackStopsOnceAndClearsState() async {
    let runtime = PlaybackRuntimeSpy(readiness: .failed(.protectedControl))
    let probe = AuthorizedPlaybackProbe(eligibility: .qualified, runtime: runtime)

    #expect(await probe.prove(expectedAuthorization: .expected, ownerConfirmation: .audible) == .terminal(.protectedControl))
    #expect(await probe.prove(expectedAuthorization: .expected, ownerConfirmation: .audible) == .terminal(.protectedControl))
    #expect(runtime.prepareCount == 1)
    #expect(runtime.clearCount == 1)
}

@MainActor
private final class PlaybackRuntimeSpy: AuthorizedPlaybackRuntime {
    var readiness: PlaybackReadiness
    private(set) var prepareCount = 0
    private(set) var clearCount = 0

    init(readiness: PlaybackReadiness = .ready) {
        self.readiness = readiness
    }

    func prepareExpectedAuthorization() async -> PlaybackReadiness {
        prepareCount += 1
        return readiness
    }

    func clearVolatileState() {
        clearCount += 1
    }
}
