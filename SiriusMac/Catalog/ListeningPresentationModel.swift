import Observation
import SiriusXMClient

/// The app-local semantic catalog boundary. Views never construct requests or
/// inspect provider responses; they ask this flow for a closed catalog result.
protocol ListeningFlow: AnyObject, Sendable {
    func catalog() async -> CatalogAvailability
}

extension SiriusXMClient: ListeningFlow {}

enum ListeningPresentationState: Equatable {
    case idle
    case loading
    case available(LiveCatalogSnapshot)
    case stale(snapshot: LiveCatalogSnapshot, failure: CatalogFailure)
    case empty(freshness: CatalogFreshness)
    case failed(CatalogFailure)

    var snapshot: LiveCatalogSnapshot? {
        switch self {
        case let .available(snapshot), let .stale(snapshot, _): snapshot
        case .idle, .loading, .empty, .failed: nil
        }
    }

    var freshness: CatalogFreshness? {
        switch self {
        case let .available(snapshot): snapshot.freshness
        case let .stale(snapshot, _): snapshot.freshness
        case let .empty(freshness): freshness
        case .idle, .loading, .failed: nil
        }
    }
}

/// Main-actor state for browsing an already semantic, entitled channel lineup.
@MainActor
@Observable
final class ListeningPresentationModel {
    private let flow: any ListeningFlow
    private let playbackCoordinator: PlaybackCoordinator?
    private var refreshTask: Task<Void, Never>?
    private var generation = 0

    private(set) var state: ListeningPresentationState = .idle
    private(set) var playbackState: LivePlaybackState = .awaitingLiveContract
    var selectedChannelID: LiveChannelID?

    init(flow: any ListeningFlow, playbackCoordinator: PlaybackCoordinator? = nil) {
        self.flow = flow
        self.playbackCoordinator = playbackCoordinator
    }

    static func makeIfEntitled(
        _ authenticationState: AuthenticationPresentationState,
        flow: any ListeningFlow
    ) -> ListeningPresentationModel? {
        guard authenticationState == .entitled else { return nil }
        return ListeningPresentationModel(flow: flow)
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard refreshTask == nil else { return nil }

        generation += 1
        let refreshGeneration = generation
        state = .loading
        let flow = flow
        let task = Task { [weak self] in
            let availability = await flow.catalog()
            guard let self,
                  !Task.isCancelled,
                  self.generation == refreshGeneration
            else { return }
            self.apply(availability)
            self.refreshTask = nil
        }
        refreshTask = task
        return task
    }

    func select(_ channelID: LiveChannelID) {
        selectedChannelID = channelID
    }

    @discardableResult
    func tuneSelectedChannel() -> Task<Void, Never>? {
        guard let playbackCoordinator else {
            playbackState = .unavailable(.unsupported)
            return nil
        }
        guard let selectedChannelID else {
            playbackState = .unavailable(.selectionUnavailable)
            return nil
        }
        return Task { [weak self] in
            await playbackCoordinator.tune(selectedChannelID)
            self?.playbackState = playbackCoordinator.state
        }
    }

    @discardableResult
    func pausePlayback() -> Task<Void, Never>? {
        command { coordinator in await coordinator.pause() }
    }

    @discardableResult
    func resumePlaybackAtLiveEdge() -> Task<Void, Never>? {
        command { coordinator in await coordinator.resumeLiveEdge() }
    }

    @discardableResult
    func stopPlayback() -> Task<Void, Never>? {
        command { coordinator in await coordinator.stop() }
    }

    func reset() {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        selectedChannelID = nil
        state = .idle
        playbackState = .awaitingLiveContract
    }

    private func apply(_ availability: CatalogAvailability) {
        switch availability {
        case let .snapshot(snapshot):
            state = snapshot.channels.isEmpty ? .empty(freshness: snapshot.freshness) : .available(snapshot)
        case let .stale(snapshot, failure):
            state = snapshot.channels.isEmpty ? .empty(freshness: .stale) : .stale(snapshot: snapshot, failure: failure)
        case let .failed(failure):
            state = .failed(failure)
        case .unavailable:
            state = .failed(.unavailable)
        }
    }

    private func command(
        _ operation: @escaping @MainActor @Sendable (PlaybackCoordinator) async -> Void
    ) -> Task<Void, Never>? {
        guard let playbackCoordinator else {
            playbackState = .unavailable(.unsupported)
            return nil
        }
        return Task { [weak self] in
            await operation(playbackCoordinator)
            self?.playbackState = playbackCoordinator.state
        }
    }
}
