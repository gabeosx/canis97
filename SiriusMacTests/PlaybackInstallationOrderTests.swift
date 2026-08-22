import AVFoundation
import XCTest
@_spi(Playback) import SiriusXMClient
@testable import SiriusMac

@MainActor
final class PlaybackInstallationOrderTests: XCTestCase {
    func testRuntimeFailureTelemetryKeepsOnlyBoundedDomainAndCode() {
        XCTAssertEqual(
            PlaybackRuntimeTelemetry.failureLabel(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
            ),
            "item-failed-url-loading--1004-resource-unknown"
        )
        XCTAssertEqual(
            PlaybackRuntimeTelemetry.failureLabel(
                NSError(domain: "provider-secret.invalid", code: 7),
                resourceURI: "https://secret.invalid/playback/key/v1/secret-material"
            ),
            "item-failed-other-7-resource-key"
        )
        XCTAssertEqual(PlaybackRuntimeTelemetry.failureLabel(nil), "item-failed-no-error")
        XCTAssertEqual(
            PlaybackRuntimeTelemetry.resourceKind("https://secret.invalid/live/opaque.m3u8?token=secret"),
            "resource-manifest"
        )
        XCTAssertEqual(
            PlaybackRuntimeTelemetry.resourceKind("https://secret.invalid/live/opaque.aac?token=secret"),
            "resource-media"
        )
    }

    func testInitialTuneInstallsBeforeReadyRequestsPlayAndPublishesOnlyAfterConfirmation() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-install-first")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation()

        XCTAssertEqual(runtime.events.suffix(2), [.observed, .installed])
        XCTAssertTrue(runtime.emitReady())
        XCTAssertEqual(runtime.events.suffix(4), [.observed, .installed, .ready, .playRequested])
        XCTAssertEqual(coordinator.state, .idle)

        runtime.emitPlaying()
        _ = await tune.value

        XCTAssertEqual(coordinator.state, .playing(channel))
    }

    func testSynchronousReadyDuringObservationWaitsForInitialInstallBeforePlaying() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime(readySynchronouslyDuringObservation: true)
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-initial-ready-before-install")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation()
        _ = await tune.value

        XCTAssertEqual(runtime.events.suffix(4), [.observed, .ready, .installed, .playRequested])
        XCTAssertEqual(runtime.playRequestCount, 1)
        XCTAssertTrue(runtime.emitReady())
        XCTAssertEqual(runtime.playRequestCount, 1)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testInstallAndReadyDoNotOptimisticallyPublishPlaying() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-confirmed-only")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(runtime.emitReady())
        XCTAssertEqual(coordinator.state, .idle)

        runtime.emitPlaying()
        _ = await tune.value
        XCTAssertEqual(coordinator.state, .playing(channel))
    }

    func testStateObserverReceivesSameGenerationPublicationsInlineInSourceOrder() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-publication-order")
        var publications: [PlaybackStatePublication] = []
        coordinator.setStateObserver { publications.append($0) }

        let tune = Task { await coordinator.tune(channel, presentationGeneration: 17) }
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .failed(.networkUnavailable))
        _ = await tune.value

        let commandPublications = publications.filter { $0.presentationGeneration == 17 }
        XCTAssertEqual(commandPublications.count, 2)
        XCTAssertEqual(commandPublications[0].generation, commandPublications[1].generation)
        XCTAssertEqual(commandPublications.map(\.state), [
            .awaitingLiveContract,
            .unavailable(.networkUnavailable),
        ])
    }

    func testResolutionFailureOrMissingItemInstallsAndPlaysNothing() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let failedChannel = LiveChannelID("fixture-resolution-failure")

        let failureTune = Task { await coordinator.tune(failedChannel) }
        await resolver.waitForResolution(of: failedChannel)
        await resolver.complete(failedChannel, with: .failed(.networkUnavailable))
        _ = await failureTune.value

        XCTAssertEqual(runtime.installCount, 0)
        XCTAssertEqual(runtime.playRequestCount, 0)
        XCTAssertEqual(coordinator.state, .unavailable(.networkUnavailable))

        let missingItemChannel = LiveChannelID("fixture-missing-item")
        let missingItemTune = Task { await coordinator.tune(missingItemChannel) }
        await resolver.waitForResolution(of: missingItemChannel)
        await resolver.complete(missingItemChannel, with: .available(InstallOrderMediaHandoff(makeItem: false)))
        _ = await missingItemTune.value

        XCTAssertEqual(runtime.installCount, 0)
        XCTAssertEqual(runtime.playRequestCount, 0)
        XCTAssertEqual(coordinator.state, .unavailable(.resolutionUnavailable))
    }

    func testResumeAtLiveEdgeReresolvesAndUsesTheSameInstallBeforeReadyOrder() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-resume-install-first")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel, count: 1)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 1)
        XCTAssertTrue(runtime.emitReady())
        runtime.emitPlaying()
        _ = await tune.value

        let resume = Task { await coordinator.resumeLiveEdge() }
        await resolver.waitForResolution(of: channel, count: 2)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 2)

        XCTAssertEqual(runtime.events.suffix(2), [.observed, .installed])
        XCTAssertTrue(runtime.emitReady())
        runtime.emitPlaying()
        _ = await resume.value

        let resolutionCount = await resolver.calls(for: channel)
        XCTAssertEqual(resolutionCount, 2)
        XCTAssertEqual(runtime.installCount, 2)
        XCTAssertEqual(coordinator.state, .playing(channel))
    }

    func testSynchronousReadyDuringObservationWaitsForResumeInstallBeforePlaying() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime(readySynchronouslyDuringObservation: true)
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-resume-ready-before-install")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel, count: 1)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 1)
        runtime.emitPlaying()
        _ = await tune.value

        let resume = Task { await coordinator.resumeLiveEdge() }
        await resolver.waitForResolution(of: channel, count: 2)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 2)
        _ = await resume.value

        let resolutionCount = await resolver.calls(for: channel)
        XCTAssertEqual(runtime.events.suffix(4), [.observed, .ready, .installed, .playRequested])
        XCTAssertEqual(runtime.playRequestCount, 2)
        XCTAssertEqual(resolutionCount, 2)
    }

    func testRecoveryInstallsBeforeReadyAndOnlyConfirmedPlayingCompletesTheIncident() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime()
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            runtime: runtime,
            recoveryPolicy: PlaybackRecoveryPolicy(maximumReResolutions: 1, stallGrace: 0, backoffs: [0])
        )
        let channel = LiveChannelID("fixture-recovery-install-first")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel, count: 1)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 1)
        XCTAssertTrue(runtime.emitReady())
        runtime.emitPlaying()
        _ = await tune.value

        coordinator.handleRecoverySignal(.decoderFailed)
        await resolver.waitForResolution(of: channel, count: 2)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 2)

        XCTAssertEqual(runtime.events.suffix(2), [.observed, .installed])
        XCTAssertTrue(runtime.emitReady())
        XCTAssertEqual(coordinator.state, .playing(channel))

        runtime.emitPlaying()
        XCTAssertEqual(coordinator.state, .playing(channel))
    }

    func testSynchronousReadyDuringObservationWaitsForRecoveredInstallBeforePlaying() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime(readySynchronouslyDuringObservation: true)
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            runtime: runtime,
            recoveryPolicy: PlaybackRecoveryPolicy(maximumReResolutions: 1, stallGrace: 0, backoffs: [0])
        )
        let channel = LiveChannelID("fixture-recovery-ready-before-install")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel, count: 1)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 1)
        runtime.emitPlaying()
        _ = await tune.value

        coordinator.handleRecoverySignal(.decoderFailed)
        await resolver.waitForResolution(of: channel, count: 2)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 2)

        XCTAssertEqual(runtime.events.suffix(4), [.observed, .ready, .installed, .playRequested])
        XCTAssertEqual(runtime.playRequestCount, 2)
        XCTAssertEqual(coordinator.state, .playing(channel))

        runtime.emitPlaying()
        XCTAssertEqual(coordinator.state, .playing(channel))
    }

    func testPauseStopSwitchAndSessionEndMakeLateCallbacksInertAndAreIdempotent() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let model = ListeningPresentationModel(flow: InstallOrderCatalogFlow(), playbackCoordinator: coordinator)
        let first = LiveChannelID("fixture-late-first")
        let second = LiveChannelID("fixture-late-second")

        let firstTune = Task { await coordinator.tune(first) }
        await resolver.waitForResolution(of: first)
        await resolver.complete(first, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 1)

        await coordinator.pause()
        let playsAfterPause = runtime.playRequestCount
        XCTAssertFalse(runtime.emitReady(observation: 0, includingCancelled: true))
        runtime.emitPlaying(observation: 0, includingCancelled: true)
        XCTAssertEqual(runtime.playRequestCount, playsAfterPause)
        XCTAssertEqual(coordinator.state, .idle)
        _ = await firstTune.value

        let secondTune = Task { await coordinator.tune(second) }
        await resolver.waitForResolution(of: second)
        await resolver.complete(second, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 2)
        let installsBeforeSwitchCallback = runtime.installCount
        runtime.emitReady(observation: 0, includingCancelled: true)
        XCTAssertEqual(runtime.installCount, installsBeforeSwitchCallback)
        XCTAssertEqual(runtime.playRequestCount, playsAfterPause)

        model.reset()
        let clearsAfterSessionEnd = runtime.clearCount
        model.reset()
        await coordinator.stop()
        let clearsAfterFirstStop = runtime.clearCount
        await coordinator.stop()
        runtime.emitReady(observation: 1, includingCancelled: true)
        runtime.emitPlaying(observation: 1, includingCancelled: true)
        runtime.emitFailure(.decoderUnavailable, observation: 1, includingCancelled: true)
        _ = await secondTune.value

        XCTAssertEqual(clearsAfterFirstStop, clearsAfterSessionEnd + 1)
        XCTAssertEqual(runtime.clearCount, clearsAfterFirstStop)
        XCTAssertEqual(runtime.playRequestCount, playsAfterPause)
        XCTAssertEqual(coordinator.state, .stopped)
        XCTAssertNil(coordinator.selectedChannelID)
    }

    func testOlderRecoveryReadyCannotPlayOrClearANewerTune() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime()
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            runtime: runtime,
            recoveryPolicy: PlaybackRecoveryPolicy(maximumReResolutions: 1, stallGrace: 0, backoffs: [0])
        )
        let recoveredChannel = LiveChannelID("fixture-recovery-race")
        let newerChannel = LiveChannelID("fixture-newer-tune")

        let initialTune = Task { await coordinator.tune(recoveredChannel) }
        await resolver.waitForResolution(of: recoveredChannel, count: 1)
        await resolver.complete(recoveredChannel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 1)
        XCTAssertTrue(runtime.emitReady())
        runtime.emitPlaying()
        _ = await initialTune.value

        coordinator.handleRecoverySignal(.resourceExpired)
        await resolver.waitForResolution(of: recoveredChannel, count: 2)
        await resolver.complete(recoveredChannel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation(count: 2)

        let newerTune = Task { await coordinator.tune(newerChannel) }
        await resolver.waitForResolution(of: newerChannel)
        let playRequestsBeforeLateReady = runtime.playRequestCount
        XCTAssertFalse(runtime.emitReady(observation: 1, includingCancelled: true))
        XCTAssertEqual(runtime.playRequestCount, playRequestsBeforeLateReady)
        XCTAssertEqual(coordinator.selectedChannelID, newerChannel)

        await coordinator.stop()
        // The resolver double deliberately models a provider operation that
        // does not observe cancellation. Release it after stop so the tune
        // task can verify its generation guard and the XCTest host can exit.
        await resolver.complete(newerChannel, with: .available(InstallOrderMediaHandoff()))
        _ = await newerTune.value
    }
}

@MainActor
private final class InstallGatedPlaybackRuntime: PlaybackPlayerRuntime {
    enum Event: Equatable {
        case observed
        case installed
        case ready
        case playRequested
        case clear
    }

    private final class Observation: PlaybackItemObserving {
        var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }

    private final class Callbacks {
        let item: AVPlayerItem
        let observation: Observation
        let onReady: @MainActor @Sendable () -> Void
        let onPlaying: @MainActor @Sendable () -> Void
        let onPaused: @MainActor @Sendable () -> Void
        let onFailure: @MainActor @Sendable (LiveListeningFailure) -> Void

        init(
            item: AVPlayerItem,
            observation: Observation,
            onReady: @escaping @MainActor @Sendable () -> Void,
            onPlaying: @escaping @MainActor @Sendable () -> Void,
            onPaused: @escaping @MainActor @Sendable () -> Void,
            onFailure: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
        ) {
            self.item = item
            self.observation = observation
            self.onReady = onReady
            self.onPlaying = onPlaying
            self.onPaused = onPaused
            self.onFailure = onFailure
        }
    }

    private var installedItem: AVPlayerItem?
    private var callbacks: [Callbacks] = []
    private(set) var events: [Event] = []
    private(set) var installCount = 0
    private(set) var playRequestCount = 0
    private(set) var clearCount = 0
    private var observationCount = 0
    private let readySynchronouslyDuringObservation: Bool

    init(readySynchronouslyDuringObservation: Bool = false) {
        self.readySynchronouslyDuringObservation = readySynchronouslyDuringObservation
    }

    func observe(
        _ item: AVPlayerItem,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) -> any PlaybackItemObserving {
        let observation = Observation()
        installedItem = nil
        callbacks.append(Callbacks(
            item: item,
            observation: observation,
            onReady: onReady,
            onPlaying: onPlaying,
            onPaused: onPaused,
            onFailure: onFailure
        ))
        observationCount += 1
        events.append(.observed)
        if readySynchronouslyDuringObservation {
            events.append(.ready)
            onReady()
        }
        return observation
    }

    func install(_ item: AVPlayerItem) {
        installedItem = item
        installCount += 1
        events.append(.installed)
    }

    func requestPlay() {
        playRequestCount += 1
        events.append(.playRequested)
    }

    func requestPause() {
        callbacks.last?.onPaused()
    }

    func clearCurrentItem() {
        installedItem = nil
        clearCount += 1
        events.append(.clear)
    }

    func waitForObservation(count expectedCount: Int = 1) async {
        while observationCount < expectedCount {
            await Task.yield()
        }
    }

    @discardableResult
    func emitReady(observation index: Int? = nil, includingCancelled: Bool = false) -> Bool {
        let callbacks = callbacks[index ?? callbacks.count - 1]
        guard let installedItem, callbacks.item === installedItem,
              includingCancelled || !callbacks.observation.isCancelled
        else { return false }
        events.append(.ready)
        callbacks.onReady()
        return true
    }

    func emitPlaying(observation index: Int? = nil, includingCancelled: Bool = false) {
        let callbacks = callbacks[index ?? callbacks.count - 1]
        guard includingCancelled || !callbacks.observation.isCancelled else { return }
        callbacks.onPlaying()
    }

    func emitFailure(
        _ failure: LiveListeningFailure,
        observation index: Int? = nil,
        includingCancelled: Bool = false
    ) {
        let callbacks = callbacks[index ?? callbacks.count - 1]
        guard includingCancelled || !callbacks.observation.isCancelled else { return }
        callbacks.onFailure(failure)
    }
}

private actor InstallOrderCatalogFlow: ListeningFlow {
    func catalog() async -> CatalogAvailability { .unavailable }
}

private actor InstallOrderResolver: PlaybackResolving {
    private var callsByChannel: [LiveChannelID: Int] = [:]
    private var continuations: [LiveChannelID: [CheckedContinuation<PlaybackResourceResolution, Never>]] = [:]

    func resolve(for channelID: LiveChannelID) async -> PlaybackResourceResolution {
        callsByChannel[channelID, default: 0] += 1
        return await withCheckedContinuation { continuation in
            continuations[channelID, default: []].append(continuation)
        }
    }

    func waitForResolution(of channelID: LiveChannelID, count expectedCount: Int = 1) async {
        while callsByChannel[channelID, default: 0] < expectedCount {
            await Task.yield()
        }
    }

    func complete(_ channelID: LiveChannelID, with result: PlaybackResourceResolution) {
        guard var pending = continuations[channelID], !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        continuations[channelID] = pending
        continuation.resume(returning: result)
    }

    func calls(for channelID: LiveChannelID) -> Int {
        callsByChannel[channelID, default: 0]
    }
}

private struct InstallOrderMediaHandoff: SiriusXMAppleMediaHandoff {
    let makeItem: Bool

    init(makeItem: Bool = true) {
        self.makeItem = makeItem
    }

    func makePlayerItem() -> AVPlayerItem? {
        makeItem ? AVPlayerItem(asset: AVURLAsset(url: URL(fileURLWithPath: "/dev/null"))) : nil
    }
}
