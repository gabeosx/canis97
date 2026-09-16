import Foundation

/// One complete replacement of metadata for the caller's ordered catalog identities.
/// Missing feed coverage is normal. This value has no playback authorization.
public struct LiveNowSnapshot: Sendable, Equatable {
    /// Local response observation time, not an authoritative provider clock.
    public let observedAt: Date
    /// One result per input identity, in input order, including repeated identities.
    public let channels: [LiveNowChannel]

    public init(observedAt: Date, channels: [LiveNowChannel]) {
        self.observedAt = observedAt
        self.channels = channels
    }
}

/// Metadata coverage for one caller-supplied entitled catalog identity.
public struct LiveNowChannel: Sendable, Equatable {
    public let channelID: LiveChannelID
    public let state: LiveNowChannelState

    public init(channelID: LiveChannelID, state: LiveNowChannelState) {
        self.channelID = channelID
        self.state = state
    }
}

public enum LiveNowChannelState: Sendable, Equatable {
    case current(LiveNowProgram)
    /// Absent from the feed, empty, or containing only future items.
    case unavailable
    /// This channel contains malformed or conflicting current metadata.
    case unsupported
}

/// Display text and start time only; no artwork or media authority is retained.
public struct LiveNowProgram: Sendable, Equatable {
    public let title: String
    /// Optional artist or host display text; absence does not imply music or talk.
    public let artist: String?
    public let kind: LiveNowContentKind
    public let startedAt: Date

    public init(title: String, artist: String? = nil, kind: LiveNowContentKind, startedAt: Date) {
        self.title = title
        self.artist = artist
        self.kind = kind
        self.startedAt = startedAt
    }
}

public enum LiveNowContentKind: Sendable, Equatable {
    /// A current item. The observed feed does not reliably distinguish music,
    /// advertisements, and nonmusic items, so no music classification is inferred.
    case item
    /// A current show label used only when there is no eligible current item.
    case show
}

/// A refresh either replaces the entire snapshot or fails without publishing data.
public enum LiveNowAvailability: Sendable, Equatable {
    case current(LiveNowSnapshot)
    case failed(LiveNowFailure)
}

/// Closed failures of the volatile private metadata protocol. None grants playback.
public enum LiveNowFailure: Sendable, Equatable {
    case authenticationUnavailable
    case notEntitled
    case unsupportedResponse
    case networkUnavailable
    case rateLimited
    case protectedControl
    case cancelled
    case superseded
}
