import Foundation
@testable import SiriusXMClient

private actor ArtworkFlow: MetadataFlow {
    private(set) var metadataRequests = 0
    private(set) var references: [ChannelArtworkReference] = []
    private var pending: [Int: CheckedContinuation<ArtworkAvailability, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func metadata(for _: LiveChannelID) async -> MetadataAvailability {
        metadataRequests += 1
        return .unavailable
    }

    func artwork(for reference: ChannelArtworkReference) async -> ArtworkAvailability {
        let index = references.count
        references.append(reference)
        return await withCheckedContinuation { continuation in
            pending[index] = continuation
            let ready = waiters.filter { $0.0 <= references.count }
            waiters.removeAll { $0.0 <= references.count }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard references.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func release(_ index: Int, _ value: ArtworkAvailability) {
        pending.removeValue(forKey: index)!.resume(returning: value)
    }
}

private struct FixtureClock: MetadataClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_000) }
}

@main
private struct MetadataArtworkTests {
    @MainActor
    static func main() async {
        let channel = LiveChannelID("fixture-channel")
        let referenceA = ChannelArtworkReference(relativeReference: "/fixture-a")
        let referenceB = ChannelArtworkReference(relativeReference: "/fixture-b")
        let imageA = ArtworkData(bytes: Data([1]), mediaType: .png)
        let imageB = ArtworkData(bytes: Data([2]), mediaType: .png)
        let flow = ArtworkFlow()
        let model = MetadataPresentationModel(flow: flow, clock: FixtureClock())
        model.select(channel, automaticallyRefresh: false)

        func snapshot(_ reference: ChannelArtworkReference?, title: String = "Song") -> LiveNowSnapshot {
            LiveNowSnapshot(observedAt: FixtureClock().now(), channels: [
                LiveNowChannel(channelID: channel, state: .current(LiveNowProgram(
                    title: title, artist: "Artist", kind: .item,
                    startedAt: .distantPast, artwork: reference
                )))
            ])
        }

        model.applyLiveNow(snapshot(referenceA), failure: nil)
        await flow.waitForRequests(1)
        await flow.release(0, .current(imageA))
        await settle()
        precondition(model.state.artwork == .current(imageA), "Shared metadata must load song artwork")
        model.applyLiveNow(snapshot(referenceA), failure: nil)
        await settle()
        precondition(model.state.artwork == .current(imageA), "Unchanged artwork must stay visible")
        let firstCount = await flow.references.count
        precondition(firstCount == 1, "Unchanged artwork must not refetch")

        model.applyLiveNow(snapshot(referenceB, title: "Next Song"), failure: nil)
        precondition(model.state.artwork == .unavailable, "A new track must clear the previous image immediately")
        await flow.waitForRequests(2)
        model.applyLiveNow(snapshot(nil, title: "No Image"), failure: nil)
        await flow.release(1, .current(imageB))
        await settle()
        precondition(model.state.artwork == .unavailable, "A late image cannot attach to a different program")

        model.applyLiveNow(snapshot(referenceA), failure: nil)
        await flow.waitForRequests(3)
        model.applyLiveNow(snapshot(referenceB), failure: nil)
        await flow.waitForRequests(4)
        await flow.release(2, .current(imageA))
        await settle()
        precondition(model.state.artwork == .unavailable, "A superseded image must not publish")
        await flow.release(3, .current(imageB))
        await settle()
        precondition(model.state.artwork == .current(imageB))
        model.applyLiveNow(snapshot(referenceB), failure: .networkUnavailable)
        precondition(model.state.artwork == .stale(imageB), "Recoverable failures retain only stale artwork")
        model.applyLiveNow(nil, failure: .notEntitled)
        precondition(model.state.artwork == .unavailable, "Access loss clears artwork")

        model.applyLiveNow(snapshot(referenceA), failure: nil)
        await flow.waitForRequests(5)
        model.clear()
        await flow.release(4, .current(imageA))
        await settle()
        precondition(model.state.artwork == .unavailable, "Stop rejects late artwork")
        let metadataRequests = await flow.metadataRequests
        precondition(metadataRequests == 0, "Artwork must not start another metadata poll")
        print("Metadata artwork lifecycle: PASS")
    }

    @MainActor
    private static func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }
}
