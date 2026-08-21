import AVFoundation
import XCTest
@_spi(Playback) import SiriusXMClient
@testable import SiriusMac

@MainActor
final class MetadataPresentationTests: XCTestCase {
    func testListeningControlsDeclareDistinctAccessibilityContractsOnTheirButtons() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "SiriusMac/Catalog/ListeningView.swift"),
            encoding: .utf8
        )
        let controls = [
            (title: "Refresh", identifier: "listening.refresh", label: "Refresh Channels"),
            (title: "Tune", identifier: "listening.tune", label: "Tune selected channel"),
            (title: "Pause", identifier: "listening.pause", label: "Pause playback"),
            (title: "Resume Live", identifier: "listening.resume-live", label: "Resume at live edge"),
            (title: "Stop", identifier: "listening.stop", label: "Stop playback"),
        ]

        XCTAssertEqual(Set(controls.map(\.identifier)).count, controls.count)

        for control in controls {
            let buttonPrefix = "Button(\"\(control.title)\")"
            let start = try XCTUnwrap(source.range(of: buttonPrefix)?.lowerBound)
            let remaining = String(source[start...])
            let nextButton = remaining.dropFirst(buttonPrefix.count).range(of: "Button(")?.lowerBound
            let buttonDefinition = nextButton.map { String(remaining[..<$0]) } ?? remaining

            XCTAssertTrue(
                buttonDefinition.contains(".accessibilityIdentifier(\"\(control.identifier)\")"),
                "\(control.title) must expose its stable identifier on the Button"
            )
            XCTAssertTrue(
                buttonDefinition.contains(".accessibilityLabel(\"\(control.label)\")"),
                "\(control.title) must expose its human-readable label on the Button"
            )
        }
    }

    func testViewSelectionBindingDoesNotStartMetadataUntilPlaybackIsConfirmed() async {
        let flow = ListeningMetadataFlowSpy()
        let model = ListeningPresentationModel(flow: flow)
        let view = ListeningView(model: model)
        let channel = LiveChannelID("fixture-channel")

        view.channelSelection.wrappedValue = channel
        await Task.yield()

        let metadataRequestCount = await flow.metadataRequestCount()
        XCTAssertEqual(metadataRequestCount, 0)
        XCTAssertEqual(model.selectedChannelID, channel)
    }

    func testConfirmedPlaybackUsesCatalogIdentityWithoutDisplayingOpaqueChannelID() async throws {
        let channel = LiveChannelID("194adbca-34d6-cb94-b153-3488ee563308")
        let flow = ConfirmedPlaybackCatalogFlow(
            snapshot: LiveCatalogSnapshot(
                channels: [LiveChannel(id: channel, name: "SiriusXM Hits 1", displayNumber: 2)],
                freshness: .fresh
            )
        )
        let runtime = MetadataTestPlaybackRuntime()
        let coordinator = PlaybackCoordinator(
            resolver: MetadataTestPlaybackResolver(),
            runtime: runtime
        )
        let model = ListeningPresentationModel(flow: flow, playbackCoordinator: coordinator)

        let refresh = try XCTUnwrap(model.refresh())
        await refresh.value
        model.select(channel)
        let tune = try XCTUnwrap(model.tuneSelectedChannel())
        await runtime.waitForObservation()
        runtime.confirmReady()
        runtime.confirmPlaying()
        await tune.value

        for _ in 0 ..< 10 {
            if model.confirmedChannelLabel == "2 · SiriusXM Hits 1" { break }
            await Task.yield()
        }

        XCTAssertEqual(model.confirmedChannelLabel, "2 · SiriusXM Hits 1")
        XCTAssertFalse(model.confirmedChannelLabel?.contains(channel.rawValue) ?? false)
        await flow.waitForMetadataRequests(count: 1)
        let metadataRequestCount = await flow.metadataRequestCount()
        XCTAssertEqual(metadataRequestCount, 1)
    }

    func testBrowsingAwayAndPauseRetainConfirmedMetadataUntilStop() async throws {
        let activeChannel = LiveChannelID("fixture-active-channel")
        let browsedChannel = LiveChannelID("fixture-browsed-channel")
        let flow = ConfirmedPlaybackCatalogFlow(
            snapshot: LiveCatalogSnapshot(
                channels: [
                    LiveChannel(id: activeChannel, name: "Active Channel", displayNumber: 2),
                    LiveChannel(id: browsedChannel, name: "Browsed Channel", displayNumber: 3),
                ],
                freshness: .fresh
            )
        )
        let runtime = MetadataTestPlaybackRuntime()
        let coordinator = PlaybackCoordinator(
            resolver: MetadataTestPlaybackResolver(),
            runtime: runtime
        )
        let model = ListeningPresentationModel(flow: flow, playbackCoordinator: coordinator)

        let refresh = try XCTUnwrap(model.refresh())
        await refresh.value
        model.select(activeChannel)
        let tune = try XCTUnwrap(model.tuneSelectedChannel())
        await runtime.waitForObservation()
        runtime.confirmReady()
        runtime.confirmPlaying()
        await tune.value
        await flow.waitForMetadataRequests(count: 1)

        model.select(browsedChannel)
        await Task.yield()
        XCTAssertEqual(model.selectedChannelID, browsedChannel)
        XCTAssertEqual(model.metadataPresentation.state.channelID, activeChannel)
        let metadataRequestCount = await flow.metadataRequestCount()
        XCTAssertEqual(metadataRequestCount, 1)

        let pause = try XCTUnwrap(model.pausePlayback())
        runtime.confirmPaused()
        await pause.value
        for _ in 0 ..< 10 {
            if model.playbackState == .paused { break }
            await Task.yield()
        }
        XCTAssertEqual(model.metadataPresentation.state.channelID, activeChannel)

        let stop = try XCTUnwrap(model.stopPlayback())
        await stop.value
        XCTAssertNil(model.confirmedChannelID)
        XCTAssertEqual(model.metadataPresentation.state.channelID, LiveChannelID("semantic-unselected-channel"))
    }

    func testCurrentMetadataStartsSeparateArtworkRequestAndPublishesValidatedBytes() async {
        let artwork = ArtworkData(bytes: Data([0xFF, 0xD8, 0xFF, 0xD9]), mediaType: .jpeg)
        let reference = ChannelArtworkReference()
        let channel = LiveChannelID("fixture-channel")
        let flow = MetadataFlowSpy(
            metadata: .current(MetadataSnapshot(
                channelID: channel,
                program: LiveProgramMetadata(title: "Jóga", artist: "Björk", artwork: reference)
            )),
            artwork: .current(artwork)
        )
        let model = MetadataPresentationModel(flow: flow)

        model.select(channel)
        await flow.waitForArtworkRequest()

        XCTAssertEqual(model.state.text, .current("Björk — Jóga"))
        XCTAssertEqual(model.state.artwork, .current(artwork))
        let artworkRequestCount = await flow.artworkRequestCount()
        XCTAssertEqual(artworkRequestCount, 1)
    }

    func testNativeArtworkBoundaryDecodesValidatedBytesAndRejectsInvalidData() throws {
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlZtbkAAAAASUVORK5CYII="))
        let valid = ArtworkData(bytes: png, mediaType: .png)
        let invalid = ArtworkData(bytes: Data([0x00]), mediaType: .png)

        XCTAssertNotNil(NativeArtworkImage.decode(valid))
        XCTAssertNil(NativeArtworkImage.decode(invalid))
    }

    func testBlockedRefreshExpiresCurrentMetadataIndependently() async {
        let channel = LiveChannelID("fixture-channel")
        let clock = MutableMetadataClock()
        let sleeper = ControllableMetadataSleeper()
        let flow = BlockingRefreshMetadataFlow(initial: .current(MetadataSnapshot(
            channelID: channel,
            program: LiveProgramMetadata(title: "Current title")
        )))
        let model = MetadataPresentationModel(flow: flow, clock: clock, sleeper: sleeper)

        model.select(channel)
        await flow.waitForMetadataRequests(count: 1)
        await sleeper.waitForSleep(duration: 90)
        await sleeper.waitForSleep(duration: 30)

        clock.advance(by: 90)
        await sleeper.releaseSleep(duration: 90)
        await settleTasks()
        XCTAssertEqual(model.state.text, .stale("Current title"))

        await sleeper.releaseSleep(duration: 30)
        await flow.waitForMetadataRequests(count: 2)
        await sleeper.waitForSleep(duration: 210)
        clock.advance(by: 210)
        await sleeper.releaseSleep(duration: 210)
        await settleTasks()

        XCTAssertEqual(model.state.text, .channelFallback(channel))
        XCTAssertEqual(model.state.artwork, .unavailable)
        model.clear()
        await flow.releaseBlockedRefresh()
    }

    func testUnavailableRefreshImmediatelyMarksRetainedMetadataStale() async {
        let channel = LiveChannelID("fixture-stale-metadata")
        let sleeper = ControllableMetadataSleeper()
        let flow = SequentialMetadataFlow(results: [
            .current(MetadataSnapshot(
                channelID: channel,
                program: LiveProgramMetadata(title: "Current title")
            )),
            .unavailable,
        ])
        let model = MetadataPresentationModel(flow: flow, sleeper: sleeper)

        model.select(channel)
        await flow.waitForMetadataRequests(count: 1)
        await sleeper.waitForSleep(duration: 30)
        await sleeper.releaseSleep(duration: 30)
        await flow.waitForMetadataRequests(count: 2)
        await settleTasks()

        XCTAssertEqual(model.availability, .unavailable)
        XCTAssertEqual(model.state.text, .stale("Current title"))
        XCTAssertEqual(model.nowPlayingSemanticMetadata.currentProgram, "Current title")
        model.clear()
    }

    func testSelectionStartsMetadataWithoutPlaybackMutationAuthority() async {
        let flow = MetadataFlowSpy()
        let model = MetadataPresentationModel(flow: flow)
        let channel = LiveChannelID("fixture-channel")

        model.select(channel)
        await flow.waitForRequest()

        let requested = await flow.requestedChannel()
        XCTAssertEqual(requested, channel)
        XCTAssertEqual(model.state.channelID, channel)
        XCTAssertEqual(model.state.text, .channelFallback(channel))
    }

    func testUnavailableUpstreamMetadataKeepsTruthfulFallbackWithClosedDiagnosticState() async {
        let flow = MetadataFlowSpy(metadata: .unavailable)
        let model = MetadataPresentationModel(flow: flow)
        let channel = LiveChannelID("fixture-unavailable-metadata")

        model.select(channel)
        await flow.waitForRequest()

        XCTAssertEqual(model.state.text, .channelFallback(channel))
        XCTAssertEqual(model.availability, .unavailable)
        XCTAssertNil(model.programTitle)
        XCTAssertNil(model.programArtist)
    }

    func testPolicyUsesDocumentedFixedCeilings() {
        XCTAssertEqual(MetadataRefreshPolicy.default.pollInterval, 30)
        XCTAssertEqual(MetadataRefreshPolicy.default.staleAfter, 90)
        XCTAssertEqual(MetadataRefreshPolicy.default.unavailableAfter, 300)
    }

    private func settleTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

private actor MetadataFlowSpy: MetadataFlow {
    private let metadataResult: MetadataAvailability
    private let artworkResult: ArtworkAvailability
    private var requested: LiveChannelID?
    private var artworkRequests = 0
    private var metadataWaiter: CheckedContinuation<Void, Never>?
    private var artworkWaiter: CheckedContinuation<Void, Never>?

    init(
        metadata: MetadataAvailability = .unavailable,
        artwork: ArtworkAvailability = .unavailable
    ) {
        metadataResult = metadata
        artworkResult = artwork
    }

    func metadata(for channelID: LiveChannelID) async -> MetadataAvailability {
        requested = channelID
        metadataWaiter?.resume()
        metadataWaiter = nil
        return metadataResult
    }

    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability {
        artworkRequests += 1
        artworkWaiter?.resume()
        artworkWaiter = nil
        return artworkResult
    }
    func requestedChannel() -> LiveChannelID? { requested }
    func artworkRequestCount() -> Int { artworkRequests }
    func waitForRequest() async {
        if requested != nil { return }
        await withCheckedContinuation { metadataWaiter = $0 }
    }
    func waitForArtworkRequest() async {
        if artworkRequests > 0 { return }
        await withCheckedContinuation { artworkWaiter = $0 }
    }
}

private actor ListeningMetadataFlowSpy: ListeningFlow, MetadataFlow {
    private var metadataRequests = 0
    private var metadataWaiters: [CheckedContinuation<Void, Never>] = []

    func catalog() async -> CatalogAvailability { .unavailable }

    func metadata(for _: LiveChannelID) async -> MetadataAvailability {
        metadataRequests += 1
        metadataWaiters.forEach { $0.resume() }
        metadataWaiters.removeAll()
        return .unavailable
    }

    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }

    func metadataRequestCount() -> Int { metadataRequests }

    func waitForMetadataRequests(count: Int) async {
        if metadataRequests >= count { return }
        await withCheckedContinuation { metadataWaiters.append($0) }
    }
}

private actor ConfirmedPlaybackCatalogFlow: ListeningFlow, MetadataFlow {
    private let snapshot: LiveCatalogSnapshot
    private var metadataRequests = 0
    private var metadataWaiters: [CheckedContinuation<Void, Never>] = []

    init(snapshot: LiveCatalogSnapshot) {
        self.snapshot = snapshot
    }

    func catalog() async -> CatalogAvailability { .snapshot(snapshot) }

    func metadata(for _: LiveChannelID) async -> MetadataAvailability {
        metadataRequests += 1
        metadataWaiters.forEach { $0.resume() }
        metadataWaiters.removeAll()
        return .unavailable
    }

    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }

    func metadataRequestCount() -> Int { metadataRequests }

    func waitForMetadataRequests(count: Int) async {
        if metadataRequests >= count { return }
        await withCheckedContinuation { metadataWaiters.append($0) }
    }
}

private struct MetadataTestPlaybackResolver: PlaybackResolving {
    func resolve(for _: LiveChannelID) async -> PlaybackResourceResolution {
        .available(MetadataTestMediaHandoff())
    }
}

private final class MetadataTestMediaHandoff: SiriusXMAppleMediaHandoff, @unchecked Sendable {
    @MainActor
    func makePlayerItem() -> AVPlayerItem? {
        AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
    }
}

@MainActor
private final class MetadataTestPlaybackRuntime: PlaybackPlayerRuntime {
    private var ready: (@MainActor @Sendable () -> Void)?
    private var playing: (@MainActor @Sendable () -> Void)?
    private var paused: (@MainActor @Sendable () -> Void)?
    private var observationWaiter: CheckedContinuation<Void, Never>?

    func observe(
        _: AVPlayerItem,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused: @escaping @MainActor @Sendable () -> Void,
        onFailure _: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) -> any PlaybackItemObserving {
        ready = onReady
        playing = onPlaying
        paused = onPaused
        observationWaiter?.resume()
        observationWaiter = nil
        return MetadataTestPlaybackObservation()
    }

    func install(_: AVPlayerItem) {}
    func requestPlay() {}
    func requestPause() {}
    func clearCurrentItem() {}

    func waitForObservation() async {
        guard ready == nil else { return }
        await withCheckedContinuation { observationWaiter = $0 }
    }

    func confirmReady() { ready?() }
    func confirmPlaying() { playing?() }
    func confirmPaused() { paused?() }
}

@MainActor
private final class MetadataTestPlaybackObservation: PlaybackItemObserving {
    func cancel() {}
}

private final class MutableMetadataClock: MetadataClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant = Date(timeIntervalSince1970: 0)

    func now() -> Date { lock.withLock { instant } }

    func advance(by interval: TimeInterval) {
        lock.withLock { instant.addTimeInterval(interval) }
    }
}

private actor ControllableMetadataSleeper: MetadataSleeping {
    private var waits: [TimeInterval: [CheckedContinuation<Void, Error>]] = [:]

    func sleep(for duration: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { waits[duration, default: []].append($0) }
    }

    func waitForSleep(duration: TimeInterval) async {
        while waits[duration, default: []].isEmpty {
            await Task.yield()
        }
    }

    func releaseSleep(duration: TimeInterval) {
        guard var continuations = waits[duration], !continuations.isEmpty else { return }
        let continuation = continuations.removeFirst()
        waits[duration] = continuations
        continuation.resume()
    }
}

private actor BlockingRefreshMetadataFlow: MetadataFlow {
    private let initial: MetadataAvailability
    private var metadataRequests = 0
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var blockedRefresh: CheckedContinuation<MetadataAvailability, Never>?

    init(initial: MetadataAvailability) { self.initial = initial }

    func metadata(for _: LiveChannelID) async -> MetadataAvailability {
        metadataRequests += 1
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        if metadataRequests == 1 { return initial }
        return await withCheckedContinuation { blockedRefresh = $0 }
    }

    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }

    func waitForMetadataRequests(count: Int) async {
        if metadataRequests >= count { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseBlockedRefresh() {
        blockedRefresh?.resume(returning: .unavailable)
        blockedRefresh = nil
    }
}

private actor SequentialMetadataFlow: MetadataFlow {
    private var results: [MetadataAvailability]
    private var metadataRequests = 0
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    init(results: [MetadataAvailability]) { self.results = results }

    func metadata(for _: LiveChannelID) async -> MetadataAvailability {
        metadataRequests += 1
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        return results.isEmpty ? .unavailable : results.removeFirst()
    }

    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }

    func waitForMetadataRequests(count: Int) async {
        if metadataRequests >= count { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }
}
