import XCTest
@testable import SiriusMac
import SiriusXMClient

@MainActor
final class ListeningCompositionTests: XCTestCase {
    func testSelectedInventedChannelUsesTheSingleInjectedCoordinator() async {
        let driver = RecordingPlaybackDriver()
        let coordinator = PlaybackCoordinator(
            authorization: AlwaysAuthorizedPlaybackAuthorization(),
            driver: driver
        )
        let model = ListeningPresentationModel(playbackCoordinator: coordinator)
        let channel = LiveChannelID("fixture-channel-alpha")

        model.select(channel)
        await model.playSelectedChannel()

        let tunedChannelIDs = await driver.recordedChannelIDs()
        XCTAssertTrue(model.playbackCoordinator === coordinator)
        XCTAssertEqual(tunedChannelIDs, [channel])
        XCTAssertEqual(coordinator.state, .playing(channel))
    }

    func testStaleCatalogCanBeBrowsedButCannotAuthorizePlayback() async {
        let driver = RecordingPlaybackDriver()
        let coordinator = PlaybackCoordinator(
            authorization: UnavailablePlaybackAuthorization(),
            driver: driver
        )
        let model = ListeningPresentationModel(playbackCoordinator: coordinator)
        let channel = LiveChannelID("fixture-channel-stale")

        model.present(
            LiveCatalogSnapshot(
                channels: [LiveChannel(id: channel, title: "Fixture Stale")],
                freshness: .stale
            )
        )
        model.select(channel)
        await model.playSelectedChannel()

        let tuneCallCount = await driver.recordedTuneCallCount()
        XCTAssertEqual(model.catalog.freshness, .stale)
        XCTAssertEqual(tuneCallCount, 0)
        XCTAssertEqual(coordinator.state, .unavailable(.authorizationUnavailable))
    }

    func testConfirmedCommandsIgnoreSupersededCompletion() async {
        let driver = BlockingPlaybackDriver()
        let coordinator = PlaybackCoordinator(
            authorization: AlwaysAuthorizedPlaybackAuthorization(),
            driver: driver
        )
        let first = LiveChannelID("fixture-channel-first")
        let second = LiveChannelID("fixture-channel-second")

        let firstTune = Task { await coordinator.tune(first) }
        await driver.waitForTune(of: first)
        let secondTune = Task { await coordinator.tune(second) }
        await driver.waitForTune(of: second)

        await driver.confirmTune(of: first)
        await driver.confirmTune(of: second)
        _ = await firstTune.value
        _ = await secondTune.value

        XCTAssertEqual(coordinator.state, .playing(second))
    }

    func testDefaultCompositionAwaitsCompatibilityEvidenceWithoutWork() {
        let model = ListeningPresentationModel()

        XCTAssertEqual(model.playbackCoordinator.state, .awaitingLiveContract)
        XCTAssertEqual(model.catalog, .unavailable)
    }
}

private actor RecordingPlaybackDriver: LivePlaybackDriving {
    private(set) var tunedChannelIDs: [LiveChannelID] = []

    func recordedChannelIDs() -> [LiveChannelID] { tunedChannelIDs }

    func recordedTuneCallCount() -> Int { tunedChannelIDs.count }

    func tune(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult {
        tunedChannelIDs.append(channelID)
        return .confirmed(.playing(channelID))
    }

    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }
}

private struct AlwaysAuthorizedPlaybackAuthorization: LivePlaybackAuthorizing {
    func authorizePlayback(for _: LiveChannelID) async -> LivePlaybackAuthorization {
        .authorized
    }
}

private struct UnavailablePlaybackAuthorization: LivePlaybackAuthorizing {
    func authorizePlayback(for _: LiveChannelID) async -> LivePlaybackAuthorization {
        .unavailable
    }
}

private actor BlockingPlaybackDriver: LivePlaybackDriving {
    private var continuations: [LiveChannelID: CheckedContinuation<LivePlaybackDriverResult, Never>] = [:]
    private var waiters: [LiveChannelID: CheckedContinuation<Void, Never>] = [:]
    private var started: Set<LiveChannelID> = []

    func tune(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult {
        started.insert(channelID)
        waiters.removeValue(forKey: channelID)?.resume()
        return await withCheckedContinuation { continuations[channelID] = $0 }
    }

    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }

    func waitForTune(of channelID: LiveChannelID) async {
        guard !started.contains(channelID) else { return }
        await withCheckedContinuation { waiters[channelID] = $0 }
    }

    func confirmTune(of channelID: LiveChannelID) {
        continuations.removeValue(forKey: channelID)?.resume(returning: .confirmed(.playing(channelID)))
    }
}
