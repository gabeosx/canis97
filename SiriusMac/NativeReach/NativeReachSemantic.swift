import Foundation

/// Stable app-owned identifiers shared with the widget extension. This file is
/// deliberately Foundation-only and contains no provider or playback types.
enum NativeReachConstants {
    static let appGroupIdentifier = "group.com.canis97.player"
    static let cacheKey = "native-reach.snapshot.v1"
    static let widgetKind = "Canis97NowPlaying"
    static let spotlightDomain = "com.canis97.player.channels"
    static let urlScheme = "canis97"
    static let maximumFavoriteCount = 12
    static let maximumTextLength = 240
    static let maximumIdentityLength = 512
}

struct NativeReachChannel: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let displayNumber: Int?
    let category: String?
    let isFavorite: Bool

    init?(id: String, name: String?, displayNumber: Int?, category: String?, isFavorite: Bool) {
        guard let id = NativeReachSanitizer.text(id, maximumLength: NativeReachConstants.maximumIdentityLength)
        else { return nil }
        self.id = id
        self.name = NativeReachSanitizer.text(name, maximumLength: NativeReachConstants.maximumTextLength)
            ?? displayNumber.map { "Channel \($0)" }
            ?? "Saved channel"
        self.displayNumber = displayNumber.flatMap { (0...100_000).contains($0) ? $0 : nil }
        self.category = NativeReachSanitizer.text(category, maximumLength: NativeReachConstants.maximumTextLength)
        self.isFavorite = isFavorite
    }
}

enum NativeReachPlaybackStatus: String, Codable, Equatable, Sendable {
    case playing
    case paused
    case stopped
    case unavailable
}

struct NativeReachProgram: Codable, Equatable, Sendable {
    let title: String
    let artist: String?
    let startedAt: Date?

    init?(title: String?, artist: String?, startedAt: Date?) {
        guard let title = NativeReachSanitizer.text(title, maximumLength: NativeReachConstants.maximumTextLength)
        else { return nil }
        self.title = title
        self.artist = NativeReachSanitizer.text(artist, maximumLength: NativeReachConstants.maximumTextLength)
        self.startedAt = startedAt
    }
}

/// The complete extension cache. It contains only semantic display data and
/// local timestamps. It cannot authorize playback or reconstruct a request.
struct NativeReachSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let updatedAt: Date
    let playback: NativeReachPlaybackStatus
    let currentChannel: NativeReachChannel?
    let currentProgram: NativeReachProgram?
    let metadataObservedAt: Date?
    let favorites: [NativeReachChannel]

    init(
        updatedAt: Date,
        playback: NativeReachPlaybackStatus,
        currentChannel: NativeReachChannel?,
        currentProgram: NativeReachProgram?,
        metadataObservedAt: Date?,
        favorites: [NativeReachChannel]
    ) {
        schemaVersion = Self.schemaVersion
        self.updatedAt = updatedAt
        self.playback = playback
        self.currentChannel = currentChannel
        self.currentProgram = currentProgram
        self.metadataObservedAt = metadataObservedAt
        var seen = Set<String>()
        self.favorites = favorites
            .filter { seen.insert($0.id).inserted }
            .prefix(NativeReachConstants.maximumFavoriteCount)
            .map { $0 }
    }

    func freshness(at date: Date, staleAfter: TimeInterval = 5 * 60) -> NativeReachFreshness {
        guard updatedAt <= date.addingTimeInterval(60) else { return .unavailable }
        return date.timeIntervalSince(updatedAt) <= staleAfter ? .current : .stale
    }

    /// Returns the next useful widget timeline boundary without creating a polling loop.
    /// A current snapshot refreshes just after it becomes stale; an already-stale or
    /// untrustworthy timestamp receives one bounded follow-up entry.
    func nextWidgetRefresh(
        after date: Date,
        staleAfter: TimeInterval = 5 * 60,
        regularInterval: TimeInterval = 15 * 60,
        minimumDelay: TimeInterval = 60
    ) -> Date {
        let earliestRefresh = date.addingTimeInterval(max(1, minimumDelay))
        let regularRefresh = date.addingTimeInterval(max(minimumDelay, regularInterval))
        guard updatedAt.timeIntervalSinceReferenceDate.isFinite,
              freshness(at: date, staleAfter: staleAfter) != .unavailable
        else { return regularRefresh }
        let staleBoundary = updatedAt.addingTimeInterval(max(0, staleAfter) + 1)
        return max(earliestRefresh, min(staleBoundary, regularRefresh))
    }

    static func decoded(from data: Data) -> NativeReachSnapshot? {
        guard data.count <= 64 * 1024 else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(Self.self, from: data),
              snapshot.schemaVersion == schemaVersion,
              snapshot.favorites.count <= NativeReachConstants.maximumFavoriteCount,
              snapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.metadataObservedAt?.timeIntervalSinceReferenceDate.isFinite != false,
              let currentChannel = validated(snapshot.currentChannel),
              let currentProgram = validated(snapshot.currentProgram),
              let favorites = validated(snapshot.favorites),
              favorites.allSatisfy(\.isFavorite)
        else { return nil }
        return Self(
            updatedAt: snapshot.updatedAt,
            playback: snapshot.playback,
            currentChannel: currentChannel,
            currentProgram: currentProgram,
            metadataObservedAt: snapshot.metadataObservedAt,
            favorites: favorites
        )
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), data.count <= 64 * 1024 else { return nil }
        return data
    }

    private static func validated(_ channel: NativeReachChannel?) -> NativeReachChannel?? {
        guard let channel else { return .some(nil) }
        guard let validated = NativeReachChannel(
            id: channel.id,
            name: channel.name,
            displayNumber: channel.displayNumber,
            category: channel.category,
            isFavorite: channel.isFavorite
        ), validated == channel else { return nil }
        return .some(validated)
    }

    private static func validated(_ program: NativeReachProgram?) -> NativeReachProgram?? {
        guard let program else { return .some(nil) }
        guard program.startedAt?.timeIntervalSinceReferenceDate.isFinite != false,
              let validated = NativeReachProgram(
                title: program.title,
                artist: program.artist,
                startedAt: program.startedAt
              ), validated == program
        else { return nil }
        return .some(validated)
    }

    private static func validated(_ channels: [NativeReachChannel]) -> [NativeReachChannel]? {
        var identities = Set<String>()
        let validated = channels.compactMap { channel in
            NativeReachChannel(
                id: channel.id,
                name: channel.name,
                displayNumber: channel.displayNumber,
                category: channel.category,
                isFavorite: channel.isFavorite
            )
        }
        guard validated == channels,
              validated.allSatisfy({ identities.insert($0.id).inserted })
        else { return nil }
        return validated
    }
}

enum NativeReachFreshness: Equatable, Sendable {
    case current
    case stale
    case unavailable
}

struct NativeReachSpotlightDescriptor: Equatable, Sendable {
    let identifier: String
    let title: String
    let subtitle: String?
    let keywords: [String]
    let route: NativeReachRoute

    static func channels(_ channels: [NativeReachChannel]) -> [Self] {
        channels.map { channel in
            let number = channel.displayNumber.map(String.init)
            return Self(
                identifier: "channel:\(channel.id)",
                title: channel.name,
                subtitle: [number.map { "Channel \($0)" }, channel.category, channel.isFavorite ? "Favorite" : nil]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                keywords: [channel.name, number, channel.category, channel.isFavorite ? "favorite" : nil]
                    .compactMap { $0 },
                route: .tune(channelID: channel.id)
            )
        }
    }
}

enum NativeReachRoute: Equatable, Sendable {
    case library
    case togglePlayback
    case previousChannel
    case nextChannel
    case tune(channelID: String)

    var url: URL? {
        var components = URLComponents()
        components.scheme = NativeReachConstants.urlScheme
        switch self {
        case .library:
            components.host = "library"
        case .togglePlayback:
            components.host = "playback-toggle"
        case .previousChannel:
            components.host = "previous-channel"
        case .nextChannel:
            components.host = "next-channel"
        case let .tune(channelID):
            guard NativeReachSanitizer.text(channelID, maximumLength: NativeReachConstants.maximumIdentityLength) != nil
            else { return nil }
            components.host = "tune"
            components.queryItems = [URLQueryItem(name: "channel", value: channelID)]
        }
        return components.url
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == NativeReachConstants.urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        switch components.host?.lowercased() {
        case "library":
            self = .library
        case "playback-toggle":
            self = .togglePlayback
        case "previous-channel":
            self = .previousChannel
        case "next-channel":
            self = .nextChannel
        case "tune":
            guard let rawID = components.queryItems?.first(where: { $0.name == "channel" })?.value,
                  let channelID = NativeReachSanitizer.text(
                    rawID,
                    maximumLength: NativeReachConstants.maximumIdentityLength
                  )
            else { return nil }
            self = .tune(channelID: channelID)
        default:
            return nil
        }
    }
}

private enum NativeReachSanitizer {
    static func text(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        return trimmed
    }
}
