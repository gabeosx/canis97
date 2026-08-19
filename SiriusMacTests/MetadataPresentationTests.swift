import XCTest
@testable import SiriusMac
import SiriusXMClient

@MainActor
final class MetadataPresentationTests: XCTestCase {
    func testViewSelectionBindingStartsExactlyOneSemanticMetadataRequest() async {
        let flow = ListeningMetadataFlowSpy()
        let model = ListeningPresentationModel(flow: flow)
        let view = ListeningView(model: model)
        let channel = LiveChannelID("fixture-channel")

        view.channelSelection.wrappedValue = channel
        await flow.waitForMetadataRequests(count: 1)

        let metadataRequestCount = await flow.metadataRequestCount()
        XCTAssertEqual(metadataRequestCount, 1)
        XCTAssertEqual(model.selectedChannelID, channel)
        XCTAssertEqual(model.metadataPresentation.state.channelID, channel)
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

    func testPolicyUsesDocumentedFixedCeilings() {
        XCTAssertEqual(MetadataRefreshPolicy.default.pollInterval, 30)
        XCTAssertEqual(MetadataRefreshPolicy.default.staleAfter, 90)
        XCTAssertEqual(MetadataRefreshPolicy.default.unavailableAfter, 300)
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
