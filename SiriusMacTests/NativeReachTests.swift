import Foundation
import XCTest
@testable import Canis97

final class NativeReachTests: XCTestCase {
    func testSemanticSnapshotRoundTripsWithoutTransportMaterial() throws {
        let channel = try XCTUnwrap(NativeReachChannel(
            id: "channel-8",
            name: "Orbit",
            displayNumber: 8,
            category: "Music",
            isFavorite: true
        ))
        let snapshot = NativeReachSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            playback: .playing,
            currentChannel: channel,
            currentProgram: NativeReachProgram(
                title: "A Little More Light",
                artist: "The Satellites",
                startedAt: Date(timeIntervalSince1970: 1_699_999_900)
            ),
            metadataObservedAt: Date(timeIntervalSince1970: 1_700_000_000),
            favorites: [channel]
        )

        let data = try XCTUnwrap(snapshot.encoded())
        XCTAssertEqual(NativeReachSnapshot.decoded(from: data), snapshot)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbidden in ["http", "authorization", "cookie", "token", "session", "playbackKey", "artworkKey"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden))
        }
    }

    func testSnapshotBoundsFavoritesAndRejectsOversizedOrWrongSchemaData() throws {
        var favorites: [NativeReachChannel] = []
        for index in 0..<20 {
            favorites.append(try XCTUnwrap(NativeReachChannel(
                id: "channel-\(index)",
                name: "Channel \(index)",
                displayNumber: index,
                category: nil,
                isFavorite: true
            )))
        }
        let snapshot = NativeReachSnapshot(
            updatedAt: .now,
            playback: .stopped,
            currentChannel: nil,
            currentProgram: nil,
            metadataObservedAt: nil,
            favorites: favorites
        )
        XCTAssertEqual(snapshot.favorites.count, NativeReachConstants.maximumFavoriteCount)
        XCTAssertNil(NativeReachSnapshot.decoded(from: Data(repeating: 0, count: 64 * 1024 + 1)))

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(snapshot.encoded())) as? [String: Any])
        object["schemaVersion"] = 99
        XCTAssertNil(NativeReachSnapshot.decoded(from: try JSONSerialization.data(withJSONObject: object)))

        object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(snapshot.encoded())) as? [String: Any])
        var firstFavorite = try XCTUnwrap((object["favorites"] as? [[String: Any]])?.first)
        firstFavorite["name"] = "  "
        object["favorites"] = [firstFavorite]
        XCTAssertNil(NativeReachSnapshot.decoded(from: try JSONSerialization.data(withJSONObject: object)))
    }

    func testDeepLinksRoundTripOpaqueChannelIdentityAndRejectUnknownRoutes() throws {
        let tune = NativeReachRoute.tune(channelID: "opaque/channel + 8")
        XCTAssertEqual(NativeReachRoute(url: try XCTUnwrap(tune.url)), tune)
        XCTAssertEqual(NativeReachRoute(url: try XCTUnwrap(NativeReachRoute.library.url)), .library)
        XCTAssertEqual(
            NativeReachRoute(url: try XCTUnwrap(NativeReachRoute.togglePlayback.url)),
            .togglePlayback
        )
        XCTAssertEqual(
            NativeReachRoute(url: try XCTUnwrap(NativeReachRoute.previousChannel.url)),
            .previousChannel
        )
        XCTAssertEqual(
            NativeReachRoute(url: try XCTUnwrap(NativeReachRoute.nextChannel.url)),
            .nextChannel
        )
        XCTAssertNil(NativeReachRoute(url: try XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertNil(NativeReachRoute(url: try XCTUnwrap(URL(string: "canis97://tune"))))
    }

    func testSpotlightDescriptorsContainOnlySemanticCatalogFields() throws {
        let channel = try XCTUnwrap(NativeReachChannel(
            id: "channel-8",
            name: "Orbit",
            displayNumber: 8,
            category: "Music",
            isFavorite: true
        ))
        let descriptor = try XCTUnwrap(NativeReachSpotlightDescriptor.channels([channel]).first)
        XCTAssertEqual(descriptor.identifier, "channel:channel-8")
        XCTAssertEqual(descriptor.title, "Orbit")
        XCTAssertEqual(descriptor.route, .tune(channelID: "channel-8"))
        XCTAssertTrue(descriptor.keywords.contains("favorite"))
    }

    func testWidgetFreshnessUsesLocalPublicationTimeAndFailsFutureValuesClosed() {
        let now = Date(timeIntervalSince1970: 2_000)
        let current = NativeReachSnapshot(
            updatedAt: now.addingTimeInterval(-60),
            playback: .stopped,
            currentChannel: nil,
            currentProgram: nil,
            metadataObservedAt: nil,
            favorites: []
        )
        XCTAssertEqual(current.freshness(at: now), .current)
        XCTAssertEqual(current.freshness(at: now.addingTimeInterval(600)), .stale)
        XCTAssertEqual(
            current.nextWidgetRefresh(after: now),
            now.addingTimeInterval(5 * 60 - 60 + 1)
        )
        XCTAssertEqual(
            current.nextWidgetRefresh(after: now.addingTimeInterval(600)),
            now.addingTimeInterval(660)
        )

        let future = NativeReachSnapshot(
            updatedAt: now.addingTimeInterval(120),
            playback: .stopped,
            currentChannel: nil,
            currentProgram: nil,
            metadataObservedAt: nil,
            favorites: []
        )
        XCTAssertEqual(future.freshness(at: now), .unavailable)
        XCTAssertEqual(
            future.nextWidgetRefresh(after: now),
            now.addingTimeInterval(15 * 60)
        )
    }
}
