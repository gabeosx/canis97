import Foundation

@main
struct NativeReachSemanticChecks {
    static func main() throws {
        let favorite = require(NativeReachChannel(
            id: "favorite-8",
            name: "Orbit",
            displayNumber: 8,
            category: "Music",
            isFavorite: true
        ))
        let duplicate = favorite
        let second = require(NativeReachChannel(
            id: "favorite-12",
            name: "Public Radio",
            displayNumber: 12,
            category: "News",
            isFavorite: true
        ))
        let program = require(NativeReachProgram(
            title: "Morning Edition",
            artist: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let now = Date(timeIntervalSince1970: 1_700_000_120)
        let snapshot = NativeReachSnapshot(
            updatedAt: now,
            playback: .playing,
            currentChannel: second,
            currentProgram: program,
            metadataObservedAt: now.addingTimeInterval(-2),
            favorites: [favorite, duplicate, second]
        )

        precondition(snapshot.favorites.map(\.id) == [favorite.id, second.id])
        let encoded = require(snapshot.encoded())
        precondition(NativeReachSnapshot.decoded(from: encoded) == snapshot)
        let encodedText = require(String(data: encoded, encoding: .utf8)).lowercased()
        for forbidden in ["http", "authorization", "cookie", "token", "session", "playbackkey", "artworkkey"] {
            precondition(!encodedText.contains(forbidden))
        }

        precondition(snapshot.freshness(at: now.addingTimeInterval(60)) == .current)
        precondition(snapshot.freshness(at: now.addingTimeInterval(301)) == .stale)
        precondition(snapshot.nextWidgetRefresh(after: now) == now.addingTimeInterval(301))
        precondition(
            snapshot.nextWidgetRefresh(after: now.addingTimeInterval(600))
                == now.addingTimeInterval(660)
        )
        let future = NativeReachSnapshot(
            updatedAt: now.addingTimeInterval(61),
            playback: .stopped,
            currentChannel: nil,
            currentProgram: nil,
            metadataObservedAt: nil,
            favorites: []
        )
        precondition(future.freshness(at: now) == .unavailable)
        precondition(future.nextWidgetRefresh(after: now) == now.addingTimeInterval(900))

        let tuneRoute = NativeReachRoute.tune(channelID: "opaque/channel + 8")
        precondition(NativeReachRoute(url: require(tuneRoute.url)) == tuneRoute)
        precondition(NativeReachRoute(url: require(NativeReachRoute.library.url)) == .library)
        precondition(
            NativeReachRoute(url: require(NativeReachRoute.togglePlayback.url)) == .togglePlayback
        )
        precondition(
            NativeReachRoute(url: require(NativeReachRoute.previousChannel.url)) == .previousChannel
        )
        precondition(
            NativeReachRoute(url: require(NativeReachRoute.nextChannel.url)) == .nextChannel
        )
        precondition(NativeReachRoute(url: require(URL(string: "https://example.invalid"))) == nil)
        precondition(NativeReachRoute(url: require(URL(string: "canis97://tune"))) == nil)

        let spotlight = require(NativeReachSpotlightDescriptor.channels([favorite]).first)
        precondition(spotlight.identifier == "channel:favorite-8")
        precondition(spotlight.route == tuneRouteFor(favorite))
        precondition(spotlight.keywords.contains("favorite"))

        var object = require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 99
        let wrongSchema = try JSONSerialization.data(withJSONObject: object)
        precondition(NativeReachSnapshot.decoded(from: wrongSchema) == nil)

        object = require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var favorites = require(object["favorites"] as? [[String: Any]])
        favorites[0]["name"] = "  "
        object["favorites"] = favorites
        let malformedFavorite = try JSONSerialization.data(withJSONObject: object)
        precondition(NativeReachSnapshot.decoded(from: malformedFavorite) == nil)
        precondition(NativeReachSnapshot.decoded(from: Data(repeating: 0, count: 64 * 1024 + 1)) == nil)

        precondition(NativeReachChannel(id: "\u{0}", name: "bad", displayNumber: nil, category: nil, isFavorite: false) == nil)
        precondition(NativeReachProgram(title: "   ", artist: nil, startedAt: nil) == nil)

        print("PASS: bounded semantic cache, corruption rejection, freshness, deep links, and Spotlight descriptors")
    }

    private static func tuneRouteFor(_ channel: NativeReachChannel) -> NativeReachRoute {
        .tune(channelID: channel.id)
    }

    private static func require<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) -> T {
        guard let value else { fatalError("Expected value", file: file, line: line) }
        return value
    }
}
