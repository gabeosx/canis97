import AVFoundation
import XCTest
@_spi(Playback) import SiriusXMClient
@testable import SiriusMac

@MainActor
final class PlaybackInstallationOrderTests: XCTestCase {
    func testInitialTuneInstallsBeforeReadyRequestsPlayAndPublishesOnlyAfterConfirmation() async {
        let resolver = InstallOrderResolver()
        let runtime = InstallGatedPlaybackRuntime()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-install-first")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(InstallOrderMediaHandoff()))
        await runtime.waitForObservation()

        XCTAssertEqual(runtime.events, [.observed, .installed])
        XCTAssertTrue(runtime.emitReady())
        XCTAssertEqual(runtime.events, [.observed, .installed, .ready, .playRequested])
        XCTAssertEqual(coordinator.state, .idle)

        runtime.emitPlaying()
        _ = await tune.value

        XCTAssertEqual(coordinator.state, .playing(channel))
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

    private var observedItem: AVPlayerItem?
    private var installedItem: AVPlayerItem?
    private var observation: Observation?
    private var onReady: (@MainActor @Sendable () -> Void)?
    private var onPlaying: (@MainActor @Sendable () -> Void)?
    private var onPaused: (@MainActor @Sendable () -> Void)?
    private var onFailure: (@MainActor @Sendable (LiveListeningFailure) -> Void)?
    private(set) var events: [Event] = []
    private(set) var installCount = 0
    private(set) var playRequestCount = 0
    private var observationCount = 0

    func observe(
        _ item: AVPlayerItem,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) -> any PlaybackItemObserving {
        let observation = Observation()
        observedItem = item
        installedItem = nil
        self.observation = observation
        self.onReady = onReady
        self.onPlaying = onPlaying
        self.onPaused = onPaused
        self.onFailure = onFailure
        observationCount += 1
        events.append(.observed)
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
        onPaused?()
    }

    func clearCurrentItem() {
        installedItem = nil
        events.append(.clear)
    }

    func waitForObservation(count expectedCount: Int = 1) async {
        while observationCount < expectedCount {
            await Task.yield()
        }
    }

    @discardableResult
    func emitReady() -> Bool {
        guard let observedItem, let installedItem, observedItem === installedItem,
              observation?.isCancelled == false
        else { return false }
        events.append(.ready)
        onReady?()
        return true
    }

    func emitPlaying() {
        guard observation?.isCancelled == false else { return }
        onPlaying?()
    }
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
