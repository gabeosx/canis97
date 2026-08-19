import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Provider-neutral metadata refresh contracts")
struct MetadataRefreshCoordinatorTests {
    @Test("artwork-only metadata remains independent from text presentation")
    func artworkOnlyMetadataKeepsChannelTextFallback() async {
        let channel = LiveChannelID("fixture-artwork-only")
        let refresher = RecordingMetadataRefresher(results: [.current(text: nil, artworkLabel: "Fixture artwork")])
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: FixedMetadataClock())

        _ = await coordinator.select(channel)
        let state = await coordinator.refresh()

        #expect(state.text == .channelFallback(channel))
        #expect(state.artwork == .current("Fixture artwork"))
    }

    @Test("metadata uses channel identity as a fallback and text/artwork become current independently")
    func currentMetadataUsesIndependentRepresentations() async {
        let channel = LiveChannelID("fixture-metadata")
        let clock = FixedMetadataClock(now: Date(timeIntervalSince1970: 42))
        let refresher = RecordingMetadataRefresher(results: [.current(text: "Fixture title", artworkLabel: nil)])
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: clock)

        #expect(await coordinator.select(channel).text == .channelFallback(channel))
        let state = await coordinator.refresh()

        #expect(state.text == .current("Fixture title"))
        #expect(state.artwork == .unavailable)
        #expect(state.refreshedAt == Date(timeIntervalSince1970: 42))
    }

    @Test("unavailable refreshes transition last known metadata through stale to unavailable")
    func unavailableMetadataDoesNotLookCurrentForever() async {
        let channel = LiveChannelID("fixture-stale")
        let refresher = RecordingMetadataRefresher(results: [
            .current(text: "Fixture title", artworkLabel: "Fixture artwork"),
            .unavailable,
            .unavailable,
        ])
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: FixedMetadataClock())

        _ = await coordinator.select(channel)
        _ = await coordinator.refresh()
        let stale = await coordinator.refresh()
        let unavailable = await coordinator.refresh()

        #expect(stale.text == .stale("Fixture title"))
        #expect(stale.artwork == .stale("Fixture artwork"))
        #expect(unavailable.text == .unavailable)
        #expect(unavailable.artwork == .unavailable)
    }

    @Test("a superseded metadata completion cannot overwrite the newly selected channel")
    func ignoresStaleChannelCompletion() async {
        let first = LiveChannelID("fixture-old")
        let second = LiveChannelID("fixture-new")
        let refresher = BlockingMetadataRefresher()
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: FixedMetadataClock())

        _ = await coordinator.select(first)
        let refresh = Task { await coordinator.refresh() }
        await refresher.waitUntilStarted()
        _ = await coordinator.select(second)
        await refresher.release(.current(text: "Old title", artworkLabel: "Old artwork"))
        _ = await refresh.value

        #expect(await coordinator.currentState.channelID == second)
        #expect(await coordinator.currentState.text == .channelFallback(second))
    }

    @Test("metadata refresh has no audio collaborator or audio mutation surface")
    func metadataStaysOutsideAudioControl() async {
        let channel = LiveChannelID("fixture-isolated")
        let refresher = RecordingMetadataRefresher(results: [.current(text: nil, artworkLabel: "Fixture artwork")])
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: FixedMetadataClock())

        _ = await coordinator.select(channel)
        _ = await coordinator.refresh()

        #expect(await refresher.requestedChannelIDs == [channel])
        #expect(await coordinator.currentState.channelID == channel)
    }
}

private struct FixedMetadataClock: LiveMetadataClock {
    let instant: Date

    init(now: Date = Date(timeIntervalSince1970: 1)) { instant = now }
    func now() -> Date { instant }
}

private actor RecordingMetadataRefresher: LiveMetadataRefreshing {
    private var results: [LiveMetadataRefreshResult]
    private(set) var requestedChannelIDs: [LiveChannelID] = []

    init(results: [LiveMetadataRefreshResult]) { self.results = results }

    func refresh(for channelID: LiveChannelID) async -> LiveMetadataRefreshResult {
        requestedChannelIDs.append(channelID)
        return results.removeFirst()
    }
}

private actor BlockingMetadataRefresher: LiveMetadataRefreshing {
    private var continuation: CheckedContinuation<LiveMetadataRefreshResult, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var started = false

    func refresh(for _: LiveChannelID) async -> LiveMetadataRefreshResult {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release(_ result: LiveMetadataRefreshResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
