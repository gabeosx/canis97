import XCTest
import SiriusXMClient
@testable import SiriusMac

@MainActor
final class PlaybackQueueTests: XCTestCase {
    func testCapturePreservesOriginOrderAndCurrentIndex() {
        let ids = channelIDs("one", "two", "three")
        let queue = PlaybackQueue(originIDs: ids, currentID: ids[1])
        XCTAssertEqual(queue.capturedIDs, ids)
        XCTAssertEqual(queue.currentIndex, 1)
    }

    func testCaptureDoesNotChangeWhenVisibleCollectionsChange() {
        let ids = channelIDs("one", "two", "three")
        let queue = PlaybackQueue(originIDs: ids, currentID: ids[1])
        XCTAssertEqual(queue.capturedIDs, ids)
        XCTAssertNotEqual(queue.capturedIDs, channelIDs("three"))
    }

    func testNavigationSkipsRemovedIDsAndNeverWraps() {
        let ids = channelIDs("one", "two", "three", "four")
        var queue = PlaybackQueue(originIDs: ids, currentID: ids[1])
        let entitled = [ids[0], ids[1], ids[3]]
        XCTAssertEqual(queue.candidate(.next, currentEntitledIDs: entitled, fullLineup: ids), ids[3])
        XCTAssertNil(queue.candidate(.next, currentEntitledIDs: entitled, fullLineup: ids))
        XCTAssertEqual(queue.candidate(.previous, currentEntitledIDs: entitled, fullLineup: ids), ids[1])
        XCTAssertEqual(queue.candidate(.previous, currentEntitledIDs: entitled, fullLineup: ids), ids[0])
        XCTAssertNil(queue.candidate(.previous, currentEntitledIDs: entitled, fullLineup: ids))
    }

    func testZeroAndOneItemQueuesDisableUnavailableDirections() {
        let id = LiveChannelID("only")
        XCTAssertEqual(PlaybackQueue(originIDs: [], currentID: nil).availability(currentEntitledIDs: [], fullLineup: []), .none)
        XCTAssertEqual(PlaybackQueue(originIDs: [id], currentID: id).availability(currentEntitledIDs: [id], fullLineup: [id]), .none)
    }

    func testFallsBackToCurrentFullLineupOnlyWhenCapturedQueueHasNoUsableID() {
        let captured = channelIDs("removed-one", "removed-two")
        let lineup = channelIDs("alpha", "beta", "gamma")
        var queue = PlaybackQueue(originIDs: captured, currentID: captured[0])
        XCTAssertEqual(queue.candidate(.next, currentEntitledIDs: lineup, fullLineup: lineup), lineup[0])
        XCTAssertEqual(queue.candidate(.next, currentEntitledIDs: lineup, fullLineup: lineup), lineup[1])
    }

    func testRevealRequestCarriesOnlyStableIdentityAndGeneration() {
        let request = LibraryRevealRequest(channelID: LiveChannelID("reveal-me"), generation: 7)
        XCTAssertEqual(request.channelID, LiveChannelID("reveal-me"))
        XCTAssertEqual(request.generation, 7)
    }

    private func channelIDs(_ values: String...) -> [LiveChannelID] { values.map(LiveChannelID.init) }
}
