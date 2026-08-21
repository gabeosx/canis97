import Foundation
import Observation
import SiriusXMClient

/// The two application scene roles that consume the one listening session.
enum ListeningSurfaceRole: Equatable {
    case compact
    case library
}

private enum MetadataAnnouncementState: Equatable {
    case loading
    case current
    case stale
    case unavailable
}

private extension LiveListeningFailure {
    /// Recovery-capable and bookkeeping failures are intentionally quiet. The
    /// announcer only reports a terminal state that has no further automatic
    /// playback path to wait for.
    var isTerminalAccessibilityFailure: Bool {
        switch self {
        case .catalogUnavailable, .selectionUnavailable, .resolutionUnavailable,
             .protectedControl, .recoveryExhausted, .unsupported:
            true
        case .authorizationUnavailable, .entitlementUnavailable, .networkUnavailable,
             .bufferingUnavailable, .decoderUnavailable, .cancelled, .superseded:
            false
        }
    }
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
    private let accessibilityAnnouncer: AccessibilityAnnouncer
    private var systemMediaController: SystemMediaController?

    private(set) var hasRequestedLibraryOpen = false
    private(set) var playbackQueue: PlaybackQueue?
    private(set) var libraryRevealRequest: LibraryRevealRequest?
    private var hasTriggeredAutomaticCatalogLoad = false
    private var hasShutdown = false
    private var lastObservedPlaybackState: LivePlaybackState = .awaitingLiveContract
    private var lastObservedMetadataAnnouncementState: MetadataAnnouncementState = .unavailable
    private var announcementGeneration = 0
    private var revealGeneration = 0

    init(
        composition: AuthenticationComposition = AuthenticationComposition(),
        authenticationModel: AuthenticationPresentationModel? = nil,
        libraryStore: LibraryStore? = nil,
        remoteCommandCenter: any RemoteCommandCenterControlling = SystemRemoteCommandCenterAdapter(),
        nowPlayingPublisher: any NowPlayingInfoPublishing = SystemNowPlayingInfoAdapter(),
        accessibilityAnnouncer: AccessibilityAnnouncer = AccessibilityAnnouncer()
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
        self.accessibilityAnnouncer = accessibilityAnnouncer
        observeAuthenticationReadiness()
        observeConfirmedPlayback()
        observeMetadataAccessibilityState()
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

    /// Favorite controls send their desired state through this shared route so
    /// a successful store mutation can be announced exactly once.
    func setFavorite(_ snapshot: LibraryChannelSnapshot, isFavorite: Bool) {
        let wasFavorite = libraryStore.isFavorite(snapshot.id)
        libraryStore.setFavorite(snapshot, isFavorite: isFavorite)
        guard wasFavorite != isFavorite, libraryStore.isFavorite(snapshot.id) == isFavorite else { return }
        accessibilityAnnouncer.announce(
            isFavorite
                ? .favoriteAdded(generation: nextAnnouncementGeneration())
                : .favoriteRemoved(generation: nextAnnouncementGeneration())
        )
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
        publishConfirmedSystemMediaState()
        observeSystemMediaState()
    }

    /// Application termination owns playback invalidation, but intentionally
    /// never erases credentials. Explicit authentication cleanup remains the
    /// only path that can alter stored credential material.
    func shutdown() {
        guard !hasShutdown else { return }
        hasShutdown = true
        systemMediaController?.shutdown()
        accessibilityAnnouncer.shutdown()
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
                guard !self.hasShutdown else { return }
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
                guard !self.hasShutdown else { return }
                self.recordConfirmedPlaybackIfNeeded()
                self.observeConfirmedPlayback()
            }
        }
    }

    private func recordConfirmedPlaybackIfNeeded() {
        let state = listeningModel.playbackState
        guard state != lastObservedPlaybackState else { return }
        let previousState = lastObservedPlaybackState
        lastObservedPlaybackState = state
        announceConfirmedPlaybackTransition(from: previousState, to: state)
        guard case let .playing(channelID?) = state,
              let channel = listeningModel.state.snapshot?.channels.first(where: { $0.id == channelID })
        else { return }
        libraryStore.recordConfirmedPlayback(LibraryChannelSnapshot(channel))
    }

    private func announceConfirmedPlaybackTransition(from previous: LivePlaybackState, to current: LivePlaybackState) {
        switch current {
        case let .playing(channelID?) where confirmedChannelChanged(from: previous, to: channelID):
            accessibilityAnnouncer.announce(.tuned(generation: nextAnnouncementGeneration()))
        case .playing where previous == .paused:
            accessibilityAnnouncer.announce(.playing(generation: nextAnnouncementGeneration()))
        case .paused:
            accessibilityAnnouncer.announce(.paused(generation: nextAnnouncementGeneration()))
        case let .unavailable(failure) where failure.isTerminalAccessibilityFailure:
            accessibilityAnnouncer.announce(.playbackFailed(generation: nextAnnouncementGeneration()))
        case .awaitingLiveContract, .idle, .playing, .stopped, .unavailable:
            break
        }
    }

    private func confirmedChannelChanged(from previous: LivePlaybackState, to channelID: LiveChannelID) -> Bool {
        guard case let .playing(previousChannelID?) = previous else { return true }
        return previousChannelID != channelID
    }

    private func observeMetadataAccessibilityState() {
        withObservationTracking {
            _ = listeningModel.metadataPresentation.availability
            _ = listeningModel.metadataPresentation.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.hasShutdown else { return }
                self.announceMetadataAccessibilityTransitionIfNeeded()
                self.observeMetadataAccessibilityState()
            }
        }
    }

    private func announceMetadataAccessibilityTransitionIfNeeded() {
        let current = metadataAnnouncementState
        defer { lastObservedMetadataAnnouncementState = current }
        guard current != lastObservedMetadataAnnouncementState else { return }
        switch current {
        case .stale:
            accessibilityAnnouncer.announce(.metadataStale(generation: nextAnnouncementGeneration()))
        case .unavailable where lastObservedMetadataAnnouncementState != .loading:
            accessibilityAnnouncer.announce(.metadataUnavailable(generation: nextAnnouncementGeneration()))
        case .loading, .current, .unavailable:
            break
        }
    }

    private var metadataAnnouncementState: MetadataAnnouncementState {
        let metadata = listeningModel.metadataPresentation
        guard metadata.availability != .loading else { return .loading }
        switch metadata.state.text {
        case .current: .current
        case .stale: .stale
        case .channelFallback, .unavailable: .unavailable
        }
    }

    private func nextAnnouncementGeneration() -> Int {
        announcementGeneration &+= 1
        return announcementGeneration
    }

    /// MediaPlayer only follows coordinator-confirmed state. In particular, a
    /// browse selection or an in-flight tune must retain the last confirmed
    /// Now Playing presentation rather than publishing unconfirmed information.
    private func observeSystemMediaState() {
        guard systemMediaController != nil else { return }
        withObservationTracking {
            _ = listeningModel.playbackState
            _ = listeningModel.confirmedChannelID
            _ = listeningModel.state
            let metadata = listeningModel.metadataPresentation
            _ = metadata.availability
            _ = metadata.programTitle
            _ = metadata.programArtist
            _ = metadata.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.publishConfirmedSystemMediaState()
                self.observeSystemMediaState()
            }
        }
    }

    private func publishConfirmedSystemMediaState() {
        guard let systemMediaController else { return }
        let state = listeningModel.playbackState

        switch state {
        case .awaitingLiveContract:
            // Preserve the last confirmed state while a replacement tune is pending.
            guard listeningModel.confirmedChannelID != nil else {
                systemMediaController.publish(nil)
                systemMediaController.setSupportedCommandAvailability(playPause: false, previous: false, next: false)
                return
            }
            return
        case let .playing(channelID?):
            guard listeningModel.confirmedChannelID == channelID,
                  let channelName = listeningModel.confirmedChannelLabel
            else {
                return
            }
            let info = listeningModel.metadataPresentation.nowPlayingSemanticMetadata.systemNowPlayingInfo(
                channelName: channelName,
                playbackState: .playing
            )
            systemMediaController.publish(info)
            setConfirmedSystemCommandAvailability(using: systemMediaController)
        case .paused:
            guard listeningModel.confirmedChannelID != nil,
                  let channelName = listeningModel.confirmedChannelLabel
            else {
                systemMediaController.publish(nil)
                systemMediaController.setSupportedCommandAvailability(playPause: false, previous: false, next: false)
                return
            }
            let info = listeningModel.metadataPresentation.nowPlayingSemanticMetadata.systemNowPlayingInfo(
                channelName: channelName,
                playbackState: .paused
            )
            systemMediaController.publish(info)
            setConfirmedSystemCommandAvailability(using: systemMediaController)
        case .idle, .playing(nil), .stopped, .unavailable:
            systemMediaController.publish(nil)
            systemMediaController.setSupportedCommandAvailability(playPause: false, previous: false, next: false)
        }
    }

    private func setConfirmedSystemCommandAvailability(using systemMediaController: SystemMediaController) {
        switch queueAvailability {
        case .none:
            systemMediaController.setSupportedCommandAvailability(playPause: true, previous: false, next: false)
        case .previous:
            systemMediaController.setSupportedCommandAvailability(playPause: true, previous: true, next: false)
        case .next:
            systemMediaController.setSupportedCommandAvailability(playPause: true, previous: false, next: true)
        case .both:
            systemMediaController.setSupportedCommandAvailability(playPause: true, previous: true, next: true)
        }
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
