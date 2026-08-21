import CoreGraphics
import SiriusXMClient

/// The finite, renderer-independent input for the compact player. It contains
/// only already-validated semantic values; action execution stays with the app.
struct CompactPlayerPresentation: Sendable, Equatable {
    struct ChannelIdentity: Sendable, Equatable {
        let number: Int?
        let name: String?

        var displayText: String {
            switch (number, name?.trimmingCharacters(in: .whitespacesAndNewlines)) {
            case let (number?, name?) where !name.isEmpty: "\(number) · \(name)"
            case let (number?, _): "Channel \(number)"
            case let (_, name?) where !name.isEmpty: name
            case (nil, _): "Current Channel"
            }
        }
    }

    enum Artwork: Sendable, Equatable {
        case data(ArtworkData)
        case placeholder
    }

    enum Status: Sendable, Equatable {
        case pending
        case playing
        case paused
        case stopped
        case unavailable(CompactRecoveryAction)
    }

    struct Transport: Sendable, Equatable {
        enum PlayPause: Sendable, Equatable { case play, pause }

        let previousEnabled: Bool
        let playPause: PlayPause
        let nextEnabled: Bool
    }

    let backgroundRole: PlayerSemanticStyleRole
    let channelIdentity: ChannelIdentity?
    let artwork: Artwork?
    let primaryMetadata: String?
    let secondaryMetadata: String?
    let status: Status?
    let isFavorite: Bool
    let transport: Transport?
    let emptyTitle: String?
    let primaryActionTitle: String?

    static func confirmed(
        channel: ChannelIdentity,
        artwork: Artwork,
        primaryMetadata: String?,
        secondaryMetadata: String?,
        playback: Status,
        isFavorite: Bool,
        queueAvailability: QueueDirectionAvailability
    ) -> Self {
        let availability = availability(queueAvailability)
        return Self(
            backgroundRole: .playerBackground,
            channelIdentity: channel,
            artwork: artwork,
            primaryMetadata: primaryMetadata,
            secondaryMetadata: secondaryMetadata,
            status: playback,
            isFavorite: isFavorite,
            transport: Transport(
                previousEnabled: availability.previous,
                playPause: playback == .playing ? .pause : .play,
                nextEnabled: availability.next
            ),
            emptyTitle: nil,
            primaryActionTitle: nil
        )
    }

    static func empty() -> Self {
        Self(
            backgroundRole: .playerBackground,
            channelIdentity: nil,
            artwork: nil,
            primaryMetadata: nil,
            secondaryMetadata: nil,
            status: nil,
            isFavorite: false,
            transport: nil,
            emptyTitle: "Nothing Playing",
            primaryActionTitle: "Open Library"
        )
    }

    static func project(
        channel: LiveChannel?,
        metadata: LiveMetadataState,
        primaryMetadata: String?,
        secondaryMetadata: String?,
        playback: LivePlaybackState,
        isFavorite: Bool,
        queueAvailability: QueueDirectionAvailability
    ) -> Self {
        guard let channel else { return empty() }
        let artwork: Artwork = switch metadata.artwork {
        case let .current(data), let .stale(data): .data(data)
        case .unavailable: .placeholder
        }
        return confirmed(
            channel: ChannelIdentity(number: channel.displayNumber, name: channel.name),
            artwork: artwork,
            primaryMetadata: primaryMetadata,
            secondaryMetadata: secondaryMetadata,
            playback: status(playback),
            isFavorite: isFavorite,
            queueAvailability: queueAvailability
        )
    }

    private static func status(_ playback: LivePlaybackState) -> Status {
        switch playback {
        case .awaitingLiveContract, .idle: .pending
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        case let .unavailable(failure): .unavailable(CompactRecoveryAction(failure: failure))
        }
    }

    private static func availability(_ value: QueueDirectionAvailability) -> (previous: Bool, next: Bool) {
        switch value {
        case .none: (false, false)
        case .previous: (true, false)
        case .next: (false, true)
        case .both: (true, true)
        }
    }
}

enum CompactRecoveryAction: Sendable, Equatable {
    case tryAgain
    case signInAgain
    case refreshLibrary

    init(failure: LiveListeningFailure) {
        switch failure {
        case .authorizationUnavailable, .entitlementUnavailable, .protectedControl:
            self = .signInAgain
        case .catalogUnavailable:
            self = .refreshLibrary
        case .selectionUnavailable, .resolutionUnavailable, .networkUnavailable,
             .bufferingUnavailable, .decoderUnavailable, .cancelled, .superseded,
             .recoveryExhausted, .unsupported:
            self = .tryAgain
        }
    }

    var title: String {
        switch self {
        case .tryAgain: "Try Again"
        case .signInAgain: "Sign In Again"
        case .refreshLibrary: "Refresh Library"
        }
    }
}

enum CompactPlayerAction: CaseIterable, Sendable, Equatable {
    case previous
    case playPause
    case next
    case toggleFavorite
    case showLibrary
    case toggleAlwaysOnTop
}

enum PlayerSemanticStyleRole: CaseIterable, Sendable, Equatable {
    case playerBackground
    case metadataPanel
    case accent
    case destructive
    case label
    case body
    case heading
    case display
}

/// Bounded native fallback tokens. Appearance data can choose these roles but
/// cannot supply labels, actions, system metadata, or accessibility semantics.
struct NativeCompactPlayerStyle: Sendable, Equatable {
    let contentSize: CGSize
    let dominantHex: String
    let secondaryHex: String
    let accentHex: String
    let destructiveHex: String
    let padding: CGFloat
    let sectionSpacing: CGFloat

    static let fallback = Self(
        contentSize: CGSize(width: 400, height: 288),
        dominantHex: "#111111",
        secondaryHex: "#262626",
        accentHex: "#C6FF00",
        destructiveHex: "#FF453A",
        padding: 16,
        sectionSpacing: 8
    )
}
