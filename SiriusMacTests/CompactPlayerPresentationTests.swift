import XCTest
@testable import SiriusMac
import SiriusXMClient

@MainActor
final class CompactPlayerPresentationTests: XCTestCase {
    func testConfirmedPlaybackMapsOnlySemanticSlots() {
        let presentation = CompactPlayerPresentation.confirmed(
            channel: CompactPlayerPresentation.ChannelIdentity(number: 42, name: "The Spectrum"),
            artwork: .placeholder,
            primaryMetadata: "A very real song title",
            secondaryMetadata: "A very real artist",
            playback: .playing,
            isFavorite: true,
            queueAvailability: .both
        )

        XCTAssertEqual(presentation.channelIdentity?.displayText, "42 · The Spectrum")
        XCTAssertEqual(presentation.artwork, .placeholder)
        XCTAssertEqual(presentation.primaryMetadata, "A very real song title")
        XCTAssertEqual(presentation.secondaryMetadata, "A very real artist")
        XCTAssertEqual(presentation.status, .playing)
        XCTAssertTrue(presentation.isFavorite)
        XCTAssertEqual(presentation.transport, .init(previousEnabled: true, playPause: .pause, nextEnabled: true))
    }

    func testNativeStyleUsesApprovedRolesWithoutBehavior() {
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.contentSize, .init(width: 400, height: 288))
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.dominantHex, "#111111")
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.secondaryHex, "#262626")
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.accentHex, "#C6FF00")
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.destructiveHex, "#FF453A")
        XCTAssertEqual(PlayerSemanticStyleRole.allCases, [.playerBackground, .metadataPanel, .accent, .destructive, .label, .body, .heading, .display])
    }

    func testViewActionsStayOutsideThePresentationValue() {
        XCTAssertEqual(
            CompactPlayerAction.allCases,
            [.previous, .playPause, .next, .toggleFavorite, .showLibrary, .toggleAlwaysOnTop]
        )
        XCTAssertFalse(CompactPlayerPresentation.self is AnyObject.Type)
    }

    func testEmptyPresentationHasNoFabricatedChannelOrMetadata() {
        let presentation = CompactPlayerPresentation.empty()

        XCTAssertEqual(presentation.emptyTitle, "Nothing Playing")
        XCTAssertEqual(presentation.primaryActionTitle, "Open Library")
        XCTAssertNil(presentation.channelIdentity)
        XCTAssertNil(presentation.primaryMetadata)
        XCTAssertNil(presentation.secondaryMetadata)
    }
}
