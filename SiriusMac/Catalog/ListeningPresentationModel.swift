import Foundation
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

/// A listener-initiated tune whose cancellation is serialized at the same
/// main-actor boundary as queue navigation. Returning a raw `Task` cannot
/// provide that guarantee: its cancellation handler is nonisolated and must
/// schedule main-actor cleanup for a later turn.
@MainActor
final class ListeningTuneRequest {
    private let task: Task<Void, Never>
    private let cancelPlayback: @MainActor () -> Void
    private var hasCancelled = false

    init(task: Task<Void, Never>, cancelPlayback: @escaping @MainActor () -> Void) {
        self.task = task
        self.cancelPlayback = cancelPlayback
    }

    var value: Void {
        get async {
            await task.value
            // A coordinator event captures state synchronously at its source,
            // then applies that immutable publication on the model actor. Give
            // that queued presentation turn a chance to settle before callers
            // treat a completed request as an immediately navigable state.
            await Task.yield()
        }
    }

    /// Invalidate the coordinator generation before cancelling the worker
    /// task. That makes a cancellation immediately visible to navigation and
    /// prevents a resolver that ignores cancellation from installing later.
    func cancel() {
        guard !hasCancelled else { return }
        hasCancelled = true
        cancelPlayback()
        task.cancel()
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
    /// The returned cancellation handle has authority only while its matching
    /// tune remains active. It is deliberately separate from the coordinator's
    /// internal generation, which is an implementation detail of media work.
    private var activeTuneID: UUID?
    /// A monotonic, model-owned identity carried through PlaybackCoordinator's
    /// immutable state publications. Channel IDs are deliberately insufficient:
    /// a same-channel retune must not be confirmed by an older `.playing`.
    private var tuneGeneration = 0
    private var activeTuneGeneration: Int?
    private var lastAppliedCoordinatorGeneration = 0

    private(set) var state: ListeningPresentationState = .idle
    private(set) var playbackState: LivePlaybackState = .awaitingLiveContract
    let metadataPresentation: MetadataPresentationModel
    private(set) var selectedChannelID: LiveChannelID?
    private(set) var confirmedChannelID: LiveChannelID?
    /// This changes before the task that reaches PlaybackCoordinator is
    /// scheduled, closing the same-run-loop command race at every tune entry
    /// point (library, compact player, menu, and MediaPlayer).
    private(set) var isTunePending = false

    /// Standalone library previews/tests have no session controller. Keep
    /// their transport controls truthful with the same semantic contract;
    /// production surfaces use the controller's queue-aware projection.
    var commandAvailability: ListeningCommandAvailability {
        ListeningCommandAvailability(
            playbackState: playbackState,
            confirmedChannelID: confirmedChannelID,
            hasCancellablePlayback: playbackCoordinator?.selectedChannelID != nil,
            queueAvailability: .none,
            isTunePending: isTunePending
        )
    }

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
    func tuneSelectedChannel() -> ListeningTuneRequest? {
        guard let selectedChannelID else {
            playbackState = .unavailable(.selectionUnavailable)
            return nil
        }
        return tune(selectedChannelID)
    }

    /// Tunes an already selected semantic identity without mutating browse
    /// selection. Authorization remains entirely with PlaybackCoordinator.
    @discardableResult
    func tune(_ channelID: LiveChannelID) -> ListeningTuneRequest? {
        guard !isTunePending, let playbackCoordinator else {
            if playbackCoordinator == nil {
                playbackState = .unavailable(.unsupported)
            }
            return nil
        }

        let tuneID = UUID()
        tuneGeneration &+= 1
        let presentationGeneration = tuneGeneration
        activeTuneID = tuneID
        activeTuneGeneration = presentationGeneration
        isTunePending = true
        let task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await playbackCoordinator.tune(channelID, presentationGeneration: presentationGeneration)
            guard !Task.isCancelled else { return }
            self?.applyCompletedTuneState(
                playbackCoordinator.statePublication,
                for: tuneID,
                presentationGeneration: presentationGeneration
            )
        }
        return ListeningTuneRequest(task: task) { [weak self] in
            self?.cancelTune(id: tuneID)
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
        activeTuneID = nil
        activeTuneGeneration = nil
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        isTunePending = false
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
            self?.applyConfirmedPlaybackState(playbackCoordinator.statePublication)
        }
    }

    /// Playback confirmation arrives after a user command returns. Track the
    /// coordinator itself so AVFoundation observations, not just button tasks,
    /// update the rendered semantic state.
    private func observePlaybackState() {
        guard let playbackCoordinator else { return }
        playbackCoordinator.setStateObserver { [weak self] publication in
            // `publication` is captured at the coordinator boundary. Deferring
            // a reread of coordinator.state into Task would couple this event
            // to a later command and reintroduce the same-channel race.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyConfirmedPlaybackState(publication)
            }
        }
    }

    private func applyConfirmedPlaybackState(_ publication: PlaybackStatePublication) {
        // An active presentation request accepts only its own coordinator
        // publication. This prevents queued observations from a prior command
        // (including a same-channel retune) from clearing its pending gate or
        // replacing confirmed metadata.
        if let activeTuneGeneration,
           publication.presentationGeneration != activeTuneGeneration {
            return
        }
        guard publication.generation >= lastAppliedCoordinatorGeneration else { return }
        lastAppliedCoordinatorGeneration = publication.generation

        let state = publication.state
        playbackState = state
        switch state {
        case let .playing(channelID?):
            retireActiveTuneIfMatching(publication)
            if activeTuneID == nil {
                isTunePending = false
            }
            guard confirmedChannelID != channelID else { return }
            confirmedChannelID = channelID
            metadataPresentation.select(channelID)
        case .paused:
            // Pause retains the last confirmed active channel and its metadata.
            retireActiveTuneIfMatching(publication)
            if activeTuneID == nil {
                isTunePending = false
            }
            return
        case .awaitingLiveContract:
            // A replacement tune is pending; continue to identify the last
            // confirmed channel until the coordinator produces a terminal or
            // newly confirmed state.
            return
        case .idle, .playing(nil), .stopped, .unavailable:
            // A terminal publication from the active generation is conclusive
            // even when it arrives after `tune` returned awaiting an item
            // observation (for example AVFoundation item failure).
            retireActiveTuneIfMatching(publication)
            if activeTuneID == nil {
                isTunePending = false
            }
            guard confirmedChannelID != nil else { return }
            confirmedChannelID = nil
            metadataPresentation.clear()
        }
    }

    /// Applies a task's terminal result only while it still owns the active
    /// request. A resolver that finishes after a cancellation or replacement
    /// must not retire the newer request's pending gate.
    private func applyCompletedTuneState(
        _ publication: PlaybackStatePublication,
        for tuneID: UUID,
        presentationGeneration: Int
    ) {
        guard activeTuneID == tuneID,
              activeTuneGeneration == presentationGeneration,
              publication.presentationGeneration == presentationGeneration
        else { return }
        applyConfirmedPlaybackState(publication)
        if publication.state != .awaitingLiveContract {
            retireActiveTune(id: tuneID)
        }
    }

    /// This is intentionally synchronous: the coordinator invalidates stale
    /// resolver work before a same-turn queue navigation reads `isTunePending`.
    /// An obsolete handle cannot reach the coordinator because its identity no
    /// longer matches the one active request.
    private func cancelTune(id tuneID: UUID) {
        guard activeTuneID == tuneID, let playbackCoordinator else { return }
        retireActiveTune(id: tuneID)
        playbackCoordinator.cancelPendingTune()
        applyConfirmedPlaybackState(playbackCoordinator.statePublication)
    }

    private func retireActiveTuneIfMatching(_ publication: PlaybackStatePublication) {
        guard publication.presentationGeneration == activeTuneGeneration,
              let activeTuneID
        else { return }
        retireActiveTune(id: activeTuneID)
    }

    private func retireActiveTune(id tuneID: UUID) {
        guard activeTuneID == tuneID else { return }
        activeTuneID = nil
        activeTuneGeneration = nil
        isTunePending = false
    }
}
