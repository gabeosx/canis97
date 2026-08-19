import AVFoundation
import Foundation

/// The only app-facing resolved-media seam. This SPI is deliberately unable
/// to expose a URL, header, key, resource value, encoder, or persistence API.
/// Creating an item is not evidence that AVFoundation can play it; Plan 02-05
/// owns that native verification.
@_spi(Playback)
public protocol SiriusXMAppleMediaHandoff: Sendable {
    @MainActor func makePlayerItem() -> AVPlayerItem
}

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
    public let displayNumber: Int?
    public let category: String?

    public init(
        id: LiveChannelID,
        title: String,
        displayNumber: Int? = nil,
        category: String? = nil
    ) {
        self.id = id
        self.title = title
        self.displayNumber = displayNumber
        self.category = category
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

    /// Catalog snapshots remain browse-only until an independent authorization step succeeds.
    public var allowsPlaybackAuthorization: Bool { false }
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
    case entitlementUnavailable
    case catalogUnavailable
    case selectionUnavailable
    case resolutionUnavailable
    case networkUnavailable
    case bufferingUnavailable
    case decoderUnavailable
    case protectedControl
    case cancelled
    case superseded
    case recoveryExhausted
    case unsupported
}

/// An invented semantic class used only to decide whether a catalog candidate belongs in v1 lineup browsing.
enum LiveCatalogClassification: Sendable, Equatable {
    case standardLinear
    case appLinear
    case nonlinear
    case ambiguous
}

/// Provider-neutral presentation data for a future compatibility adapter.
struct LiveCatalogCandidate: Sendable, Equatable {
    let id: LiveChannelID
    let title: String
    let displayNumber: Int?
    let category: String?
    let classification: LiveCatalogClassification
}

/// Converts semantic candidates into stable browse data without claiming current playback authority.
struct LiveCatalogAdapter: Sendable {
    func makeSnapshot(
        from candidates: [LiveCatalogCandidate],
        freshness: LiveCatalogFreshness
    ) -> LiveCatalogSnapshot {
        let channels = candidates
            .filter { $0.classification == .standardLinear || $0.classification == .appLinear }
            .sorted(by: Self.isOrderedBefore)
            .map {
                LiveChannel(
                    id: $0.id,
                    title: $0.title,
                    displayNumber: $0.displayNumber,
                    category: $0.category
                )
            }
        return LiveCatalogSnapshot(channels: channels, freshness: freshness)
    }

    func retainingForBrowsing(_ snapshot: LiveCatalogSnapshot) -> LiveCatalogSnapshot {
        LiveCatalogSnapshot(channels: snapshot.channels, freshness: .stale)
    }

    private static func isOrderedBefore(_ lhs: LiveCatalogCandidate, _ rhs: LiveCatalogCandidate) -> Bool {
        let leftCategory = lhs.category ?? ""
        let rightCategory = rhs.category ?? ""
        if leftCategory != rightCategory { return leftCategory < rightCategory }

        let leftNumber = lhs.displayNumber ?? .max
        let rightNumber = rhs.displayNumber ?? .max
        if leftNumber != rightNumber { return leftNumber < rightNumber }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id.rawValue < rhs.id.rawValue
    }
}

enum LivePlaybackResolution: Sendable, Equatable {
    case ready
    case failed(LiveListeningFailure)
}

protocol LivePlaybackResolving: Sendable {
    func resolve(_ channelID: LiveChannelID) async -> LivePlaybackResolution
}

enum LivePlaybackDriverResult: Sendable, Equatable {
    case confirmed(LivePlaybackState)
    case failed(LiveListeningFailure)
}

protocol LivePlaybackEventDriving: Sendable {
    func start(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult
    func pause() async -> LivePlaybackDriverResult
    func resumeLiveEdge() async -> LivePlaybackDriverResult
    func stop() async -> LivePlaybackDriverResult
}

/// An offline state machine that coordinates semantic collaborator outcomes, not media resources.
actor LivePlaybackContractCoordinator {
    private let resolver: any LivePlaybackResolving
    private let player: any LivePlaybackEventDriving
    private let recoveryBudget: Int
    private var generation = 0

    private(set) var currentState: LivePlaybackState = .awaitingLiveContract
    private(set) var selectedChannelID: LiveChannelID?

    init(
        resolver: any LivePlaybackResolving,
        player: any LivePlaybackEventDriving,
        recoveryBudget: Int
    ) {
        self.resolver = resolver
        self.player = player
        self.recoveryBudget = max(0, recoveryBudget)
    }

    func tune(_ channelID: LiveChannelID) async -> LivePlaybackState {
        let command = beginCommand(selecting: channelID)
        guard !Task.isCancelled else { return publish(.cancelled, for: command) }

        switch await resolver.resolve(channelID) {
        case .ready:
            guard !Task.isCancelled else { return publish(.cancelled, for: command) }
            return publish(await player.start(channelID), for: command)
        case let .failed(failure):
            return publish(failure, for: command)
        }
    }

    func pause() async -> LivePlaybackState {
        let command = beginCommand()
        guard !Task.isCancelled else { return publish(.cancelled, for: command) }
        return publish(await player.pause(), for: command)
    }

    func resumeLiveEdge() async -> LivePlaybackState {
        let command = beginCommand()
        guard !Task.isCancelled else { return publish(.cancelled, for: command) }
        return publish(await player.resumeLiveEdge(), for: command)
    }

    func stop() async -> LivePlaybackState {
        let command = beginCommand()
        guard !Task.isCancelled else { return publish(.cancelled, for: command) }
        return publish(await player.stop(), for: command)
    }

    func recover() async -> LivePlaybackState {
        guard let channelID = selectedChannelID else {
            return unavailable(.selectionUnavailable)
        }

        let command = beginCommand()
        for _ in 0..<recoveryBudget {
            guard !Task.isCancelled else { return publish(.cancelled, for: command) }
            guard isCurrent(command) else { return currentState }

            switch await resolver.resolve(channelID) {
            case .ready:
                guard !Task.isCancelled else { return publish(.cancelled, for: command) }
                let outcome = await player.start(channelID)
                guard isCurrent(command) else { return currentState }
                switch outcome {
                case .confirmed:
                    return publish(outcome, for: command)
                case let .failed(failure) where isTerminalRecoveryFailure(failure):
                    return publish(failure, for: command)
                case .failed:
                    continue
                }
            case let .failed(failure) where isTerminalRecoveryFailure(failure):
                return publish(failure, for: command)
            case .failed:
                continue
            }
        }

        return publish(.recoveryExhausted, for: command)
    }

    private func beginCommand(selecting channelID: LiveChannelID? = nil) -> Int {
        generation += 1
        if let channelID { selectedChannelID = channelID }
        return generation
    }

    private func isCurrent(_ command: Int) -> Bool { generation == command }

    private func publish(_ outcome: LivePlaybackDriverResult, for command: Int) -> LivePlaybackState {
        switch outcome {
        case let .confirmed(state):
            return publish(state, for: command)
        case let .failed(failure):
            return publish(failure, for: command)
        }
    }

    private func publish(_ failure: LiveListeningFailure, for command: Int) -> LivePlaybackState {
        guard isCurrent(command) else { return currentState }
        return unavailable(failure)
    }

    private func publish(_ state: LivePlaybackState, for command: Int) -> LivePlaybackState {
        guard isCurrent(command) else { return currentState }
        currentState = state
        return state
    }

    private func unavailable(_ failure: LiveListeningFailure) -> LivePlaybackState {
        let state = LivePlaybackState.unavailable(failure)
        currentState = state
        return state
    }

    private func isTerminalRecoveryFailure(_ failure: LiveListeningFailure) -> Bool {
        switch failure {
        case .authorizationUnavailable, .entitlementUnavailable, .protectedControl, .cancelled, .superseded, .unsupported:
            true
        case .catalogUnavailable, .selectionUnavailable, .resolutionUnavailable, .networkUnavailable, .bufferingUnavailable, .decoderUnavailable, .recoveryExhausted:
            false
        }
    }
}

/// Text is deliberately semantic; it contains no provider response field names.
public enum LiveMetadataText: Sendable, Equatable {
    case current(String)
    case stale(String)
    case channelFallback(LiveChannelID)
    case unavailable
}

/// Artwork is represented only by an app-owned display label until a supported adapter exists.
public enum LiveMetadataArtwork: Sendable, Equatable {
    case current(String)
    case stale(String)
    case unavailable
}

public struct LiveMetadataState: Sendable, Equatable {
    public let channelID: LiveChannelID
    public let text: LiveMetadataText
    public let artwork: LiveMetadataArtwork
    public let refreshedAt: Date?

    public init(channelID: LiveChannelID, text: LiveMetadataText, artwork: LiveMetadataArtwork, refreshedAt: Date?) {
        self.channelID = channelID
        self.text = text
        self.artwork = artwork
        self.refreshedAt = refreshedAt
    }
}

public enum LiveMetadataRefreshResult: Sendable, Equatable {
    case current(text: String?, artworkLabel: String?)
    case unavailable
}

public protocol LiveMetadataRefreshing: Sendable {
    func refresh(for channelID: LiveChannelID) async -> LiveMetadataRefreshResult
}

public protocol LiveMetadataClock: Sendable {
    func now() -> Date
}

public struct SystemLiveMetadataClock: LiveMetadataClock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct UnavailableMetadataRefresher: LiveMetadataRefreshing {
    public init() {}
    public func refresh(for _: LiveChannelID) async -> LiveMetadataRefreshResult { .unavailable }
}

/// Refreshes metadata independently from playback and retains no audio-control collaborator.
public actor MetadataRefreshCoordinator {
    private let refresher: any LiveMetadataRefreshing
    private let clock: any LiveMetadataClock
    private var generation = 0

    public private(set) var currentState: LiveMetadataState

    public init(
        refresher: any LiveMetadataRefreshing = UnavailableMetadataRefresher(),
        clock: any LiveMetadataClock = SystemLiveMetadataClock()
    ) {
        self.refresher = refresher
        self.clock = clock
        let channelID = LiveChannelID("semantic-unselected-channel")
        self.currentState = Self.fallbackState(for: channelID)
    }

    @discardableResult
    public func select(_ channelID: LiveChannelID) -> LiveMetadataState {
        generation += 1
        currentState = Self.fallbackState(for: channelID)
        return currentState
    }

    @discardableResult
    public func refresh() async -> LiveMetadataState {
        let command = generation
        let channelID = currentState.channelID
        let result = await refresher.refresh(for: channelID)
        guard generation == command else { return currentState }

        switch result {
        case let .current(text, artworkLabel):
            currentState = LiveMetadataState(
                channelID: channelID,
                text: text.map(LiveMetadataText.current) ?? .channelFallback(channelID),
                artwork: artworkLabel.map(LiveMetadataArtwork.current) ?? .unavailable,
                refreshedAt: clock.now()
            )
        case .unavailable:
            currentState = Self.advanceUnavailableState(from: currentState)
        }
        return currentState
    }

    private static func fallbackState(for channelID: LiveChannelID) -> LiveMetadataState {
        LiveMetadataState(channelID: channelID, text: .channelFallback(channelID), artwork: .unavailable, refreshedAt: nil)
    }

    private static func advanceUnavailableState(from state: LiveMetadataState) -> LiveMetadataState {
        LiveMetadataState(
            channelID: state.channelID,
            text: staleOrUnavailable(state.text),
            artwork: staleOrUnavailable(state.artwork),
            refreshedAt: state.refreshedAt
        )
    }

    private static func staleOrUnavailable(_ text: LiveMetadataText) -> LiveMetadataText {
        switch text {
        case let .current(value): .stale(value)
        case .stale, .channelFallback, .unavailable: .unavailable
        }
    }

    private static func staleOrUnavailable(_ artwork: LiveMetadataArtwork) -> LiveMetadataArtwork {
        switch artwork {
        case let .current(value): .stale(value)
        case .stale, .unavailable: .unavailable
        }
    }
}
