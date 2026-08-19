import Testing
@testable import SiriusXMClient

@Suite("Provider-neutral live playback contracts")
struct LivePlaybackCoordinatorTests {
    @Test("phase two contracts cannot create transport requests or provider-operation calls")
    func phaseTwoContractsRemainOfflineScaffolding() {
        for operation in SiriusXMRequestContract.liveListeningOperations {
            #expect(throws: SiriusXMRequestContractError.self) {
                try SiriusXMRequestContract.makeRequest(for: operation, authorization: "synthetic-token")
            }
        }
    }

    @Test("tune publishes only after a fake resolver and player both confirm")
    func publishesConfirmedTuneState() async {
        let channel = LiveChannelID("fixture-command")
        let resolver = RecordingResolver(results: [.ready])
        let player = BlockingEventDriver()
        let coordinator = LivePlaybackContractCoordinator(resolver: resolver, player: player, recoveryBudget: 2)

        let tune = Task { await coordinator.tune(channel) }
        await player.waitUntilStartRequested()

        #expect(await coordinator.currentState == .awaitingLiveContract)
        await player.confirmStart(for: channel)
        #expect(await tune.value == .playing(channel))
        #expect(await coordinator.currentState == .playing(channel))
    }

    @Test("a newer command ignores an obsolete confirmed completion")
    func ignoresSupersededCompletion() async {
        let first = LiveChannelID("fixture-first")
        let second = LiveChannelID("fixture-second")
        let resolver = RecordingResolver(results: [.ready, .ready])
        let player = PerChannelBlockingEventDriver()
        let coordinator = LivePlaybackContractCoordinator(resolver: resolver, player: player, recoveryBudget: 1)

        let firstTune = Task { await coordinator.tune(first) }
        await player.waitUntilStartRequested(for: first)
        let secondTune = Task { await coordinator.tune(second) }
        await player.waitUntilStartRequested(for: second)

        await player.confirmStart(for: first)
        await player.confirmStart(for: second)

        _ = await firstTune.value
        #expect(await secondTune.value == .playing(second))
        #expect(await coordinator.currentState == .playing(second))
    }

    @Test("same-channel recovery uses its finite budget and retains the selected identity")
    func recoveryIsFiniteAndKeepsTheSelection() async {
        let channel = LiveChannelID("fixture-recovery")
        let resolver = RecordingResolver(results: [.ready, .failed(.networkUnavailable), .failed(.networkUnavailable), .failed(.networkUnavailable)])
        let player = RecordingEventDriver()
        let coordinator = LivePlaybackContractCoordinator(resolver: resolver, player: player, recoveryBudget: 3)

        _ = await coordinator.tune(channel)
        #expect(await coordinator.recover() == .unavailable(.recoveryExhausted))
        #expect(await resolver.callCount == 4)
        #expect(await coordinator.selectedChannelID == channel)
        #expect(await coordinator.currentState == .unavailable(.recoveryExhausted))
    }

    @Test("cancelled recovery stops before later budget attempts")
    func cancellationStopsRecovery() async {
        let channel = LiveChannelID("fixture-cancel")
        let resolver = BlockingResolver()
        let coordinator = LivePlaybackContractCoordinator(resolver: resolver, player: RecordingEventDriver(), recoveryBudget: 3)

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitUntilStarted()
        await resolver.release(.ready)
        _ = await tune.value

        let recovery = Task { await coordinator.recover() }
        await resolver.waitUntilStarted()
        recovery.cancel()
        await resolver.release(.failed(.networkUnavailable))

        #expect(await recovery.value == .unavailable(.cancelled))
        #expect(await resolver.callCount == 2)
    }
}

private actor RecordingResolver: LivePlaybackResolving {
    private var results: [LivePlaybackResolution]
    private(set) var callCount = 0

    init(results: [LivePlaybackResolution]) { self.results = results }

    func resolve(_: LiveChannelID) async -> LivePlaybackResolution {
        callCount += 1
        return results.removeFirst()
    }
}

private actor BlockingResolver: LivePlaybackResolving {
    private var continuation: CheckedContinuation<LivePlaybackResolution, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var started = false
    private(set) var callCount = 0

    func resolve(_: LiveChannelID) async -> LivePlaybackResolution {
        callCount += 1
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release(_ result: LivePlaybackResolution) {
        started = false
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor RecordingEventDriver: LivePlaybackEventDriving {
    func start(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult { .confirmed(.playing(channelID)) }
    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }
}

private actor BlockingEventDriver: LivePlaybackEventDriving {
    private var startContinuation: CheckedContinuation<LivePlaybackDriverResult, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var started = false

    func start(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { startContinuation = $0 }
    }

    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }

    func waitUntilStartRequested() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func confirmStart(for channelID: LiveChannelID) {
        startContinuation?.resume(returning: .confirmed(.playing(channelID)))
        startContinuation = nil
    }
}

private actor PerChannelBlockingEventDriver: LivePlaybackEventDriving {
    private var continuations: [LiveChannelID: CheckedContinuation<LivePlaybackDriverResult, Never>] = [:]
    private var waiters: [LiveChannelID: CheckedContinuation<Void, Never>] = [:]
    private var started: Set<LiveChannelID> = []

    func start(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult {
        started.insert(channelID)
        waiters.removeValue(forKey: channelID)?.resume()
        return await withCheckedContinuation { continuations[channelID] = $0 }
    }

    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }

    func waitUntilStartRequested(for channelID: LiveChannelID) async {
        guard !started.contains(channelID) else { return }
        await withCheckedContinuation { waiters[channelID] = $0 }
    }

    func confirmStart(for channelID: LiveChannelID) {
        continuations.removeValue(forKey: channelID)?.resume(returning: .confirmed(.playing(channelID)))
    }
}
