import Foundation

/// A stable semantic identity for one selectable live channel.
///
/// The identity is deliberately opaque: it is not a provider request parameter,
/// resource location, or representation of an upstream entity.
public struct LiveChannelID: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { "LiveChannelID(semantic)" }
}

/// Presentation-only channel data supplied by a future compatibility adapter.
public struct LiveChannel: Sendable, Equatable, Hashable {
    public let id: LiveChannelID
    public let title: String

    public init(id: LiveChannelID, title: String) {
        self.id = id
        self.title = title
    }
}

/// The observed freshness of semantic catalog data, independent of authorization.
public enum LiveCatalogFreshness: Sendable, Equatable {
    case fresh
    case stale
}

/// A browsable catalog value that cannot authorize playback by itself.
public struct LiveCatalogSnapshot: Sendable, Equatable {
    public let channels: [LiveChannel]
    public let freshness: LiveCatalogFreshness

    public init(channels: [LiveChannel], freshness: LiveCatalogFreshness) {
        self.channels = channels
        self.freshness = freshness
    }
}

/// Closed catalog presentation state before a live compatibility adapter exists.
public enum LiveCatalogPresentation: Sendable, Equatable {
    case unavailable
    case snapshot(LiveCatalogSnapshot)

    public var freshness: LiveCatalogFreshness? {
        guard case let .snapshot(snapshot) = self else { return nil }
        return snapshot.freshness
    }
}

/// Confirmed playback state; none of these cases retains a resolved media resource.
public enum LivePlaybackState: Sendable, Equatable {
    case awaitingLiveContract
    case idle
    case playing(LiveChannelID?)
    case paused
    case stopped
    case unavailable(LiveListeningFailure)
}

/// Closed, provider-agnostic reasons that a listening action did not become active.
public enum LiveListeningFailure: Sendable, Equatable {
    case authorizationUnavailable
    case selectionUnavailable
    case resolutionUnavailable
    case cancelled
    case superseded
    case recoveryExhausted
    case unsupported
}
