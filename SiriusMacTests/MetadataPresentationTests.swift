import XCTest
@testable import SiriusMac
import SiriusXMClient

@MainActor
final class MetadataPresentationTests: XCTestCase {
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
    private var requested: LiveChannelID?
    private var waiter: CheckedContinuation<Void, Never>?

    func metadata(for channelID: LiveChannelID) async -> MetadataAvailability {
        requested = channelID
        waiter?.resume()
        waiter = nil
        return .unavailable
    }

    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }
    func requestedChannel() -> LiveChannelID? { requested }
    func waitForRequest() async {
        if requested != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
}
