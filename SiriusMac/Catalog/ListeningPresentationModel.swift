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
    let metadataPresentation: MetadataPresentationModel
    private(set) var selectedChannelID: LiveChannelID?
    private(set) var confirmedChannelID: LiveChannelID?

    /// A listener-facing identity for the confirmed channel. The opaque stable
    /// ID remains a lookup key only; it is never normal display text.
    var confirmedChannelLabel: String? {
        guard let confirmedChannelID,
              let channel = state.snapshot?.channels.first(where: { $0.id == confirmedChannelID })
        else { return nil }

        let name = channel.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usableName = name.flatMap { $0.isEmpty || $0 == confirmedChannelID.rawValue ? nil : $0 }
        return switch (channel.displayNumber, usableName) {
        case let (number?, name?): "\(number) · \(name)"
        case let (number?, nil): "Channel \(number)"
        case let (nil, name?): name
        case (nil, nil): nil
        }
    }

    init(flow: any ListeningFlow, playbackCoordinator: PlaybackCoordinator? = nil) {
        self.flow = flow
        self.playbackCoordinator = playbackCoordinator
        self.metadataPresentation = (flow as? any MetadataFlow).map { MetadataPresentationModel(flow: $0) } ?? MetadataPresentationModel()
        observePlaybackState()
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

    func clearSelection() {
        selectedChannelID = nil
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
            self?.applyConfirmedPlaybackState(playbackCoordinator.state)
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
        playbackCoordinator?.invalidateForSessionEnd()
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        selectedChannelID = nil
        state = .idle
        playbackState = .awaitingLiveContract
        confirmedChannelID = nil
        metadataPresentation.clear()
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
            self?.applyConfirmedPlaybackState(playbackCoordinator.state)
        }
    }

    /// Playback confirmation arrives after a user command returns. Track the
    /// coordinator itself so AVFoundation observations, not just button tasks,
    /// update the rendered semantic state.
    private func observePlaybackState() {
        guard let playbackCoordinator else { return }
        applyConfirmedPlaybackState(playbackCoordinator.state)
        withObservationTracking {
            _ = playbackCoordinator.state
        } onChange: { [weak self, playbackCoordinator] in
            Task { @MainActor [weak self, playbackCoordinator] in
                guard let self else { return }
                self.applyConfirmedPlaybackState(playbackCoordinator.state)
                self.observePlaybackState()
            }
        }
    }

    private func applyConfirmedPlaybackState(_ state: LivePlaybackState) {
        playbackState = state
        switch state {
        case let .playing(channelID?):
            guard confirmedChannelID != channelID else { return }
            confirmedChannelID = channelID
            metadataPresentation.select(channelID)
        case .paused:
            // Pause retains the last confirmed active channel and its metadata.
            return
        case .awaitingLiveContract, .idle, .playing(nil), .stopped, .unavailable:
            guard confirmedChannelID != nil else { return }
            confirmedChannelID = nil
            metadataPresentation.clear()
        }
    }
}
