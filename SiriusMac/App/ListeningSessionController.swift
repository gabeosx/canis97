import Foundation
import Observation
import SiriusXMClient

/// The two application scene roles that consume the one listening session.
enum ListeningSurfaceRole: Equatable {
    case compact
    case library
}

/// A closed, semantic snapshot for an application surface. It intentionally
/// excludes provider, credential, session, transport, resource, and URL data.
struct ListeningSurfaceState: Equatable {
    let role: ListeningSurfaceRole
    let coordinatorIdentity: ObjectIdentifier
    let selectedChannelID: LiveChannelID?
    let activeChannelID: LiveChannelID?
    let playbackState: LivePlaybackState
    /// Confirmed program details are semantic display values only. They never
    /// contain provider identifiers, credentials, transport data, or URLs.
    let metadataPrimaryText: String?
    let metadataSecondaryText: String?
    let usesMetadataFallback: Bool
}

/// The app-lifetime owner for authentication, catalog browsing, and the sole
/// playback coordinator. SwiftUI scenes receive this controller; they never
/// construct an alternate authentication or media ownership path.
@MainActor
@Observable
final class ListeningSessionController {
    let composition: AuthenticationComposition
    let authenticationModel: AuthenticationPresentationModel
    let bridge: WebAuthenticationBridge
    let listeningModel: ListeningPresentationModel
    let playbackCoordinator: PlaybackCoordinator
    let libraryStore: LibraryStore

    private let remoteCommandCenter: any RemoteCommandCenterControlling
    private let nowPlayingPublisher: any NowPlayingInfoPublishing
    private var systemMediaController: SystemMediaController?

    private(set) var hasRequestedLibraryOpen = false
    private(set) var playbackQueue: PlaybackQueue?
    private(set) var libraryRevealRequest: LibraryRevealRequest?
    private var hasTriggeredAutomaticCatalogLoad = false
    private var hasShutdown = false
    private var lastObservedPlaybackState: LivePlaybackState = .awaitingLiveContract
    private var revealGeneration = 0

    init(
        composition: AuthenticationComposition = AuthenticationComposition(),
        authenticationModel: AuthenticationPresentationModel? = nil,
        libraryStore: LibraryStore? = nil,
        remoteCommandCenter: any RemoteCommandCenterControlling = SystemRemoteCommandCenterAdapter(),
        nowPlayingPublisher: any NowPlayingInfoPublishing = SystemNowPlayingInfoAdapter()
    ) {
        self.composition = composition
        bridge = composition.bridge
        self.authenticationModel = authenticationModel ?? AuthenticationPresentationModel(flow: composition.flow)
        playbackCoordinator = composition.playbackCoordinator
        listeningModel = ListeningPresentationModel(
            flow: composition.listeningFlow,
            playbackCoordinator: composition.playbackCoordinator
        )
        self.libraryStore = libraryStore ?? LibraryStore()
        self.remoteCommandCenter = remoteCommandCenter
        self.nowPlayingPublisher = nowPlayingPublisher
        observeAuthenticationReadiness()
        observeConfirmedPlayback()
    }

    var compactSurface: ListeningSurfaceState { surface(for: .compact) }
    var librarySurface: ListeningSurfaceState { surface(for: .library) }

    /// Returns whether this is the first request for the singleton library
    /// route. Repeated requests focus that route without creating new state.
    func requestLibraryOpen() -> Bool {
        guard !hasRequestedLibraryOpen else { return false }
        hasRequestedLibraryOpen = true
        return true
    }

    @discardableResult
    func tuneFromLibrary(_ channelID: LiveChannelID) -> Task<Void, Never>? {
        listeningModel.select(channelID)
        return listeningModel.tuneSelectedChannel()
    }

    /// Captures the origin collection before explicit tuning. The captured IDs
    /// are not entitlement authority and are never persisted.
    @discardableResult
    func tune(channelID: LiveChannelID, originIDs: [LiveChannelID]) -> Task<Void, Never>? {
        playbackQueue = PlaybackQueue(originIDs: originIDs, currentID: channelID)
        return listeningModel.tune(channelID)
    }

    var queueAvailability: QueueDirectionAvailability {
        let lineup = currentEntitledIDs
        return playbackQueue?.availability(currentEntitledIDs: lineup, fullLineup: lineup) ?? .none
    }

    @discardableResult
    func previous() -> Task<Void, Never>? {
        navigate(.previous)
    }

    @discardableResult
    func next() -> Task<Void, Never>? {
        navigate(.next)
    }

    func resetListeningBeforeAuthenticationCleanup() {
        listeningModel.reset()
    }

    /// The application composition, never a window, owns MediaPlayer's single
    /// process-wide registration. Tests supply fakes without touching macOS.
    func startSystemMediaControls() {
        if systemMediaController == nil {
            systemMediaController = SystemMediaController(
                commandCenter: remoteCommandCenter,
                nowPlayingPublisher: nowPlayingPublisher,
                actions: .init(
                    playPause: { [weak self] in self?.handleSystemPlayPause() ?? .commandFailed },
                    previous: { [weak self] in self?.handleSystemPrevious() ?? .commandFailed },
                    next: { [weak self] in self?.handleSystemNext() ?? .commandFailed }
                )
            )
        }
        systemMediaController?.start()
    }

    /// Application termination owns playback invalidation, but intentionally
    /// never erases credentials. Explicit authentication cleanup remains the
    /// only path that can alter stored credential material.
    func shutdown() {
        guard !hasShutdown else { return }
        hasShutdown = true
        systemMediaController?.shutdown()
        listeningModel.reset()
    }

    /// Starts one initial catalog request for each transition into a ready,
    /// entitled listening session. Manual refresh remains the explicit recovery
    /// path after a failed result; observation repeats cannot start a race.
    func loadCatalogWhenReady() {
        guard authenticationModel.isReady else {
            hasTriggeredAutomaticCatalogLoad = false
            return
        }
        guard !hasTriggeredAutomaticCatalogLoad else { return }
        hasTriggeredAutomaticCatalogLoad = true
        _ = listeningModel.refresh()
    }

    private func observeAuthenticationReadiness() {
        loadCatalogWhenReady()
        withObservationTracking {
            _ = authenticationModel.isReady
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadCatalogWhenReady()
                self.observeAuthenticationReadiness()
            }
        }
    }

    /// Records a recent from an actual coordinator-confirmed transition, never
    /// from a selection or command. Repeated reads of the same state are inert.
    private func observeConfirmedPlayback() {
        withObservationTracking {
            _ = listeningModel.playbackState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordConfirmedPlaybackIfNeeded()
                self.observeConfirmedPlayback()
            }
        }
    }

    private func recordConfirmedPlaybackIfNeeded() {
        let state = listeningModel.playbackState
        guard state != lastObservedPlaybackState else { return }
        lastObservedPlaybackState = state
        guard case let .playing(channelID?) = state,
              let channel = listeningModel.state.snapshot?.channels.first(where: { $0.id == channelID })
        else { return }
        libraryStore.recordConfirmedPlayback(LibraryChannelSnapshot(channel))
    }

    private var currentEntitledIDs: [LiveChannelID] {
        listeningModel.state.snapshot?.channels.map(\.id) ?? []
    }

    private func navigate(_ direction: QueueDirection) -> Task<Void, Never>? {
        guard var queue = playbackQueue,
              let channelID = queue.candidate(
                  direction,
                  currentEntitledIDs: currentEntitledIDs,
                  fullLineup: currentEntitledIDs
              )
        else { return nil }

        playbackQueue = queue
        revealGeneration += 1
        libraryRevealRequest = LibraryRevealRequest(channelID: channelID, generation: revealGeneration)
        return listeningModel.tune(channelID)
    }

    private func handleSystemPlayPause() -> SystemRemoteCommandStatus {
        switch listeningModel.playbackState {
        case .playing:
            return listeningModel.pausePlayback() == nil ? .commandFailed : .success
        case .paused:
            guard listeningModel.confirmedChannelID != nil else { return .commandFailed }
            return listeningModel.resumePlaybackAtLiveEdge() == nil ? .commandFailed : .success
        case .awaitingLiveContract, .idle, .stopped, .unavailable:
            return .commandFailed
        }
    }

    private func handleSystemPrevious() -> SystemRemoteCommandStatus {
        guard queueAvailability == .previous || queueAvailability == .both else { return .commandFailed }
        return previous() == nil ? .commandFailed : .success
    }

    private func handleSystemNext() -> SystemRemoteCommandStatus {
        guard queueAvailability == .next || queueAvailability == .both else { return .commandFailed }
        return next() == nil ? .commandFailed : .success
    }

    private func surface(for role: ListeningSurfaceRole) -> ListeningSurfaceState {
        let playbackState = listeningModel.playbackState
        let activeChannelID = listeningModel.confirmedChannelID
        let metadata = confirmedMetadataPresentation()
        return ListeningSurfaceState(
            role: role,
            coordinatorIdentity: ObjectIdentifier(playbackCoordinator),
            selectedChannelID: listeningModel.selectedChannelID,
            activeChannelID: activeChannelID,
            playbackState: playbackState,
            metadataPrimaryText: metadata.primary,
            metadataSecondaryText: metadata.secondary,
            usesMetadataFallback: metadata.isFallback
        )
    }

    private func confirmedMetadataPresentation() -> (primary: String?, secondary: String?, isFallback: Bool) {
        guard listeningModel.confirmedChannelID != nil else { return (nil, nil, false) }

        let metadata = listeningModel.metadataPresentation
        if metadata.availability == .loading {
            return ("Loading current program…", listeningModel.confirmedChannelLabel, false)
        }
        switch metadata.state.text {
        case let .current(value):
            return (metadata.programTitle ?? value, metadata.programArtist, false)
        case let .stale(value):
            return ("Last updated earlier: \(metadata.programTitle ?? value)", metadata.programArtist, false)
        case .channelFallback, .unavailable:
            return ("Current program unavailable", listeningModel.confirmedChannelLabel, true)
        }
    }
}
