import Foundation
import Observation
import OSLog
import SiriusXMClient

/// The two application scene roles that consume the one listening session.
enum ListeningSurfaceRole: Equatable {
    case compact
    case library
}

enum LibraryWindowDirective: Equatable {
    case open
    case close
    case none
}

private enum MetadataAnnouncementState: Equatable {
    case loading
    case current
    case stale
    case unavailable
}

#if DEBUG
enum AuthenticationRenewalQualificationState: Equatable {
    case idle
    case inProgress
    case completed(AuthenticationRenewalQualificationOutcome, Date)

    var statusText: String {
        switch self {
        case .idle:
            "No forced renewal has run in this app launch."
        case .inProgress:
            "One renewal request is in progress. It will not retry."
        case let .completed(.replacementPersisted, date):
            "Replacement received and saved at \(date.formatted(date: .omitted, time: .standard))."
        case let .completed(.sessionUnavailable, date):
            "No active entitled session was available at \(date.formatted(date: .omitted, time: .standard))."
        case let .completed(.attemptInProgress, date):
            "Another authentication operation was active at \(date.formatted(date: .omitted, time: .standard))."
        case let .completed(.renewalUnavailable, date):
            "The one renewal attempt failed closed at \(date.formatted(date: .omitted, time: .standard))."
        case let .completed(.persistenceFailed, date):
            "A replacement could not be saved at \(date.formatted(date: .omitted, time: .standard))."
        case let .completed(.replacementUnchanged, date):
            "The endpoint did not produce a distinct replacement at \(date.formatted(date: .omitted, time: .standard))."
        }
    }
}
#endif

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

/// The single semantic transport contract shared by the library and Player
/// menu. Commands are enabled only for coordinator-confirmed playback; Stop
/// is the one exception because it also cancels an in-flight tune.
struct ListeningCommandAvailability: Equatable {
    let pause: Bool
    let resumeLive: Bool
    let stop: Bool
    let previous: Bool
    let next: Bool

    init(
        playbackState: LivePlaybackState,
        confirmedChannelID: LiveChannelID?,
        hasCancellablePlayback: Bool,
        queueAvailability: QueueDirectionAvailability,
        isTunePending: Bool = false
    ) {
        let isConfirmedPlaying: Bool
        if case let .playing(channelID?) = playbackState {
            isConfirmedPlaying = channelID == confirmedChannelID
        } else {
            isConfirmedPlaying = false
        }
        let isConfirmedPaused = playbackState == .paused && confirmedChannelID != nil
        let hasConfirmedPlayback = isConfirmedPlaying || isConfirmedPaused

        // Tuning is scheduled asynchronously. Keep command eligibility closed
        // from the synchronous request until the coordinator confirms or
        // terminates that request, otherwise two commands in the same run-loop
        // turn can both advance the queue.
        pause = isConfirmedPlaying && !isTunePending
        resumeLive = isConfirmedPaused && !isTunePending
        // A pending tune retains a selected coordinator channel even though it
        // has not become confirmed playback yet; Stop must remain available to
        // cancel that work without exposing other inert transport commands.
        stop = hasCancellablePlayback && playbackState != .stopped
        previous = !isTunePending && hasConfirmedPlayback && (queueAvailability == .previous || queueAvailability == .both)
        next = !isTunePending && hasConfirmedPlayback && (queueAvailability == .next || queueAvailability == .both)
    }

    var playPause: Bool { pause || resumeLive }
    var playPauseTitle: String { pause ? "Pause" : "Play" }
}

enum FavoriteCurrentSongDisabledReason: Equatable {
    case tunePending
    case noConfirmedPlayback
    case confirmedChannelUnavailable
    case metadataForAnotherChannel
    case metadataNotCurrent
    case missingTitle
    case missingArtist

    var accessibilityHint: String {
        switch self {
        case .tunePending: "Wait for the current channel to finish tuning"
        case .noConfirmedPlayback: "Play a confirmed channel before saving its current song"
        case .confirmedChannelUnavailable: "The confirmed channel is unavailable"
        case .metadataForAnotherChannel: "Current song metadata belongs to another channel"
        case .metadataNotCurrent: "Current song metadata is not current"
        case .missingTitle: "Current song title is unavailable"
        case .missingArtist: "Current song artist is unavailable"
        }
    }
}

enum FavoriteCurrentSongActionState: Equatable {
    case enabled(isFavorite: Bool)
    case disabled(FavoriteCurrentSongDisabledReason)

    var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }

    var isFavorite: Bool {
        if case let .enabled(isFavorite) = self { return isFavorite }
        return false
    }

    var title: String {
        switch self {
        case let .enabled(isFavorite):
            isFavorite ? "Remove Current Song from Favorite Songs" : "Favorite Current Song"
        case .disabled:
            "Favorite Current Song"
        }
    }

    var accessibilityLabel: String { title }

    var accessibilityValue: String {
        switch self {
        case let .enabled(isFavorite):
            isFavorite ? "Saved to Favorite Songs" : "Not saved to Favorite Songs"
        case .disabled:
            "Unavailable"
        }
    }

    var accessibilityHint: String {
        switch self {
        case let .enabled(isFavorite):
            isFavorite
                ? "Removes the confirmed current song from Favorite Songs"
                : "Saves the confirmed current song to Favorite Songs"
        case let .disabled(reason):
            reason.accessibilityHint
        }
    }
}

/// The app-lifetime owner for authentication, catalog browsing, and the sole
/// playback coordinator. SwiftUI scenes receive this controller; they never
/// construct an alternate authentication or media ownership path.
@MainActor
@Observable
final class ListeningSessionController {
#if DEBUG
    private static let renewalQualificationLogger = Logger(
        subsystem: ProductIdentity.appLogSubsystem,
        category: "authentication-qualification"
    )
#endif
    let composition: AuthenticationComposition
    let authenticationModel: AuthenticationPresentationModel
    let bridge: WebAuthenticationBridge
    let listeningModel: ListeningPresentationModel
    let playbackCoordinator: PlaybackCoordinator
    let libraryStore: LibraryStore
    let supportDiagnostics: SupportDiagnosticJournal

    private let remoteCommandCenter: any RemoteCommandCenterControlling
    private let nowPlayingPublisher: any NowPlayingInfoPublishing
    private let accessibilityAnnouncer: AccessibilityAnnouncer
    private var systemMediaController: SystemMediaController?

    private(set) var hasRequestedLibraryOpen = false
    private(set) var playbackQueue: PlaybackQueue?
    private(set) var libraryRevealRequest: LibraryRevealRequest?
    private(set) var librarySearchFocusGeneration = 0
#if DEBUG
    private(set) var authenticationRenewalQualificationState: AuthenticationRenewalQualificationState = .idle
    private var authenticationRenewalQualificationTask: Task<Void, Never>?
#endif
    private var hasTriggeredAutomaticCatalogLoad = false
    private var hasShutdown = false
    private var lastObservedPlaybackState: LivePlaybackState = .idle
    private var lastObservedAuthenticationDiagnosticState: AuthenticationPresentationState = .signedOut
    private var lastObservedCatalogDiagnosticState: ListeningPresentationState = .idle
    private var lastObservedMetadataAnnouncementState: MetadataAnnouncementState = .unavailable
    private var announcementGeneration = 0
    private var revealGeneration = 0

    init(
        composition: AuthenticationComposition = AuthenticationComposition(),
        authenticationModel: AuthenticationPresentationModel? = nil,
        libraryStore: LibraryStore? = nil,
        supportDiagnostics: SupportDiagnosticJournal = SupportDiagnosticJournal(),
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
        self.supportDiagnostics = supportDiagnostics
        self.remoteCommandCenter = remoteCommandCenter
        self.nowPlayingPublisher = nowPlayingPublisher
        self.accessibilityAnnouncer = accessibilityAnnouncer
        let supportDiagnostics = supportDiagnostics
        bridge.setRenewalDiagnosticHandler { diagnostic in
            supportDiagnostics.recordRenewalAttempt(diagnostic)
        }
        composition.credentialSource.setStoredCredentialLoadDiagnosticHandler { diagnostic in
            supportDiagnostics.recordStoredCredentialLoad(diagnostic)
        }
        composition.credentialSource.setNativeAuthenticationDiagnosticHandler { diagnostic in
            supportDiagnostics.recordNativeAuthenticationAttempt(diagnostic)
        }
        supportDiagnostics.recordAuthenticationState(
            self.authenticationModel.state.supportStateLabel,
            successful: self.authenticationModel.state.isSuccessfulForSupport
        )
        bridge.setAutomaticCredentialReadyHandler { [weak self] in
            self?.authenticationModel.useAutomaticallyDetectedSession()
        }
        observeAuthenticationReadiness()
        observeAuthenticationDiagnostics()
        observeCatalogDiagnostics()
        observeConfirmedPlayback()
        observeMetadataAccessibilityState()
    }

    var compactSurface: ListeningSurfaceState { surface(for: .compact) }
    var librarySurface: ListeningSurfaceState { surface(for: .library) }

    var commandAvailability: ListeningCommandAvailability {
        ListeningCommandAvailability(
            playbackState: listeningModel.playbackState,
            confirmedChannelID: listeningModel.confirmedChannelID,
            hasCancellablePlayback: playbackCoordinator.selectedChannelID != nil,
            queueAvailability: queueAvailability,
            isTunePending: listeningModel.isTunePending
        )
    }

    var favoriteCurrentSongActionState: FavoriteCurrentSongActionState {
        guard let candidate = favoriteCurrentSongCandidate else {
            return .disabled(favoriteCurrentSongDisabledReason)
        }
        return .enabled(isFavorite: libraryStore.isFavoriteSong(candidate))
    }

    /// Returns whether this is the first request for the singleton library
    /// route. Repeated requests focus that route without creating new state.
    func requestLibraryOpen() -> Bool {
        guard !hasRequestedLibraryOpen else { return false }
        hasRequestedLibraryOpen = true
        return true
    }

    /// Makes the library window lifecycle session-scoped. Signing out closes
    /// the authenticated library surface and rearms its automatic presentation
    /// for the next ready session; repeated ready observations remain inert.
    func libraryWindowDirective(authenticationIsReady: Bool) -> LibraryWindowDirective {
        guard authenticationIsReady else {
            hasRequestedLibraryOpen = false
            return .close
        }
        return requestLibraryOpen() ? .open : .none
    }

    /// A generation-tagged request keeps focus ownership inside the singleton
    /// library scene rather than letting playback or another window steal it.
    func requestLibrarySearchFocus() {
        librarySearchFocusGeneration &+= 1
        _ = requestLibraryOpen()
    }

    @discardableResult
    func toggleConfirmedPlayback() -> Task<Void, Never>? {
        let availability = commandAvailability
        if availability.pause {
            return listeningModel.pausePlayback()
        } else if availability.resumeLive {
            return listeningModel.resumePlaybackAtLiveEdge()
        } else {
            return nil
        }
    }

    @discardableResult
    func tuneSelectedLibraryChannel() -> ListeningTuneRequest? {
        listeningModel.tuneSelectedChannel()
    }

    @discardableResult
    func tuneFromLibrary(_ channelID: LiveChannelID) -> ListeningTuneRequest? {
        listeningModel.select(channelID)
        return listeningModel.tuneSelectedChannel()
    }

    /// Captures the origin collection before explicit tuning. The captured IDs
    /// are not entitlement authority and are never persisted.
    @discardableResult
    func tune(channelID: LiveChannelID, originIDs: [LiveChannelID]) -> ListeningTuneRequest? {
        guard !listeningModel.isTunePending,
              let tune = listeningModel.tune(channelID)
        else { return nil }

        playbackQueue = PlaybackQueue(originIDs: originIDs, currentID: channelID)
        return tune
    }

    var queueAvailability: QueueDirectionAvailability {
        let lineup = currentCatalogIDs
        return playbackQueue?.availability(currentAvailableIDs: lineup, fullLineup: lineup) ?? .none
    }

    @discardableResult
    func previous() -> ListeningTuneRequest? {
        navigate(.previous)
    }

    @discardableResult
    func next() -> ListeningTuneRequest? {
        navigate(.next)
    }

    func resetListeningBeforeAuthenticationCleanup() {
        listeningModel.reset()
    }

#if DEBUG
    var canQualifyAuthenticationRenewal: Bool {
        guard composition.renewalQualificationClient != nil,
              authenticationModel.isReady,
              authenticationRenewalQualificationTask == nil,
              !listeningModel.isTunePending,
              listeningModel.state != .loading
        else { return false }

        switch listeningModel.playbackState {
        case .idle, .stopped:
            return true
        case .awaitingLiveContract, .playing, .paused, .unavailable:
            return false
        }
    }

    /// Sends one native renewal request through the active client and its real
    /// Keychain store. The UI must make this an explicit owner action; this
    /// method never retries or starts catalog/playback work afterward.
    @discardableResult
    func qualifyAuthenticationRenewalOnce() -> Task<Void, Never>? {
        guard canQualifyAuthenticationRenewal,
              let client = composition.renewalQualificationClient
        else { return nil }

        authenticationRenewalQualificationState = .inProgress
        Self.renewalQualificationLogger.notice("owner-initiated renewal qualification started")
        let task = Task { @MainActor [weak self] in
            let outcome = await client.qualifyCurrentCredentialRenewal()
            guard let self, !Task.isCancelled else { return }
            self.authenticationRenewalQualificationState = .completed(outcome, Date())
            self.authenticationRenewalQualificationTask = nil
            Self.renewalQualificationLogger.notice(
                "owner-initiated renewal qualification completed outcome=\(outcome.rawValue, privacy: .public)"
            )
        }
        authenticationRenewalQualificationTask = task
        return task
    }
#endif

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

    /// This desired-state action intentionally only crosses from confirmed
    /// metadata into the library facade; it has no tuning or media authority.
    @discardableResult
    func setFavoriteCurrentSong(isFavorite: Bool) -> FavoriteSongMutationResult {
        guard let candidate = favoriteCurrentSongCandidate else { return .failed }
        return setSongFavorite(candidate, isFavorite: isFavorite)
    }

    /// Favorite-song rows use the same desired-state route as the current-song
    /// action. This intentionally has no playback, queue, or system-media work.
    @discardableResult
    func setSongFavorite(_ snapshot: FavoriteSongSnapshot, isFavorite: Bool) -> FavoriteSongMutationResult {
        let result = libraryStore.setSongFavorite(snapshot, isFavorite: isFavorite)
        switch result {
        case .saved:
            accessibilityAnnouncer.announce(.songFavoriteAdded(generation: nextAnnouncementGeneration()))
        case .removed:
            accessibilityAnnouncer.announce(.songFavoriteRemoved(generation: nextAnnouncementGeneration()))
        case .failed:
            accessibilityAnnouncer.announce(.songFavoriteMutationFailed(generation: nextAnnouncementGeneration()))
        }
        return result
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

    private func observeAuthenticationDiagnostics() {
        withObservationTracking {
            _ = authenticationModel.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.hasShutdown else { return }
                self.recordAuthenticationDiagnosticIfNeeded()
                self.observeAuthenticationDiagnostics()
            }
        }
    }

    private func recordAuthenticationDiagnosticIfNeeded() {
        let state = authenticationModel.state
        guard state != lastObservedAuthenticationDiagnosticState else { return }
        lastObservedAuthenticationDiagnosticState = state
        supportDiagnostics.recordAuthenticationState(
            state.supportStateLabel,
            successful: state.isSuccessfulForSupport
        )
        guard let code = state.supportDiagnosticCode else { return }
        supportDiagnostics.record(code)
    }

    private func observeCatalogDiagnostics() {
        withObservationTracking {
            _ = listeningModel.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.hasShutdown else { return }
                self.recordCatalogDiagnosticIfNeeded()
                self.observeCatalogDiagnostics()
            }
        }
    }

    private func recordCatalogDiagnosticIfNeeded() {
        let state = listeningModel.state
        guard state != lastObservedCatalogDiagnosticState else { return }
        lastObservedCatalogDiagnosticState = state
        let failure: CatalogFailure? = switch state {
        case let .failed(failure), let .stale(_, failure): failure
        case .idle, .loading, .available, .empty: nil
        }
        guard let code = failure?.supportDiagnosticCode else { return }
        supportDiagnostics.record(code)
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
        if case let .unavailable(failure) = state,
           let code = failure.supportDiagnosticCode {
            supportDiagnostics.record(code)
        }
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
            supportDiagnostics.record(.metadataRefreshFailed)
            accessibilityAnnouncer.announce(.metadataStale(generation: nextAnnouncementGeneration()))
        case .unavailable:
            supportDiagnostics.record(.metadataUnavailable)
            if lastObservedMetadataAnnouncementState != .loading {
                accessibilityAnnouncer.announce(.metadataUnavailable(generation: nextAnnouncementGeneration()))
            }
        case .loading, .current:
            break
        }
    }

    private var metadataAnnouncementState: MetadataAnnouncementState {
        let metadata = listeningModel.metadataPresentation
        guard metadata.availability != .loading else { return .loading }
        switch metadata.state.text {
        case .current: return .current
        case .stale: return .stale
        case .channelFallback, .unavailable: return .unavailable
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
            _ = listeningModel.isTunePending
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
        setSystemCommandAvailability(using: systemMediaController)

        switch state {
        case .awaitingLiveContract:
            // Preserve the last confirmed state while a replacement tune is pending.
            guard listeningModel.confirmedChannelID != nil else {
                systemMediaController.publish(nil)
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
        case .paused:
            guard listeningModel.confirmedChannelID != nil,
                  let channelName = listeningModel.confirmedChannelLabel
            else {
                systemMediaController.publish(nil)
                return
            }
            let info = listeningModel.metadataPresentation.nowPlayingSemanticMetadata.systemNowPlayingInfo(
                channelName: channelName,
                playbackState: .paused
            )
            systemMediaController.publish(info)
        case .idle, .playing(nil), .stopped, .unavailable:
            systemMediaController.publish(nil)
        }
    }

    private func setSystemCommandAvailability(using systemMediaController: SystemMediaController) {
        let availability = commandAvailability
        systemMediaController.setSupportedCommandAvailability(
            playPause: availability.playPause,
            previous: availability.previous,
            next: availability.next
        )
    }

    private var currentCatalogIDs: [LiveChannelID] {
        listeningModel.state.snapshot?.channels.map(\.id) ?? []
    }

    private func navigate(_ direction: QueueDirection) -> ListeningTuneRequest? {
        guard !listeningModel.isTunePending,
              var queue = playbackQueue,
              let channelID = queue.candidate(
                  direction,
                  currentAvailableIDs: currentCatalogIDs,
                  fullLineup: currentCatalogIDs
              )
        else { return nil }

        guard let tune = listeningModel.tune(channelID) else { return nil }

        playbackQueue = queue
        revealGeneration += 1
        libraryRevealRequest = LibraryRevealRequest(channelID: channelID, generation: revealGeneration)
        return tune
    }

    private func handleSystemPlayPause() -> SystemRemoteCommandStatus {
        guard commandAvailability.playPause else { return .commandFailed }
        return toggleConfirmedPlayback() == nil ? .commandFailed : .success
    }

    private func handleSystemPrevious() -> SystemRemoteCommandStatus {
        guard commandAvailability.previous else { return .commandFailed }
        return previous() == nil ? .commandFailed : .success
    }

    private func handleSystemNext() -> SystemRemoteCommandStatus {
        guard commandAvailability.next else { return .commandFailed }
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

    private var favoriteCurrentSongCandidate: FavoriteSongSnapshot? {
        guard !listeningModel.isTunePending,
              let confirmedChannelID = listeningModel.confirmedChannelID,
              isConfirmedPlayableState(for: confirmedChannelID),
              let channel = listeningModel.state.snapshot?.channels.first(where: { $0.id == confirmedChannelID }),
              let sourceChannel = FavoriteSongSourceChannel(
                rawIdentity: channel.id.rawValue,
                name: channel.name,
                displayNumber: channel.displayNumber
              )
        else { return nil }

        let metadata = listeningModel.metadataPresentation
        guard metadata.state.channelID == confirmedChannelID,
              metadata.availability == .current,
              case .current = metadata.state.text,
              let title = metadata.programTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              let artist = metadata.programArtist?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              !artist.isEmpty
        else { return nil }

        // The public client has no verified semantic album field today.
        return FavoriteSongSnapshot(title: title, artist: artist, albumName: nil, sourceChannel: sourceChannel)
    }

    private var favoriteCurrentSongDisabledReason: FavoriteCurrentSongDisabledReason {
        guard !listeningModel.isTunePending else { return .tunePending }
        guard let confirmedChannelID = listeningModel.confirmedChannelID,
              isConfirmedPlayableState(for: confirmedChannelID)
        else { return .noConfirmedPlayback }
        guard listeningModel.state.snapshot?.channels.contains(where: { $0.id == confirmedChannelID }) == true else {
            return .confirmedChannelUnavailable
        }
        let metadata = listeningModel.metadataPresentation
        guard metadata.state.channelID == confirmedChannelID else { return .metadataForAnotherChannel }
        guard metadata.availability == .current,
              case .current = metadata.state.text
        else { return .metadataNotCurrent }
        guard metadata.programTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .missingTitle
        }
        guard metadata.programArtist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .missingArtist
        }
        return .metadataNotCurrent
    }

    private func isConfirmedPlayableState(for channelID: LiveChannelID) -> Bool {
        switch listeningModel.playbackState {
        case let .playing(playingChannelID?): playingChannelID == channelID
        case .paused: true
        case .awaitingLiveContract, .idle, .playing(nil), .stopped, .unavailable: false
        }
    }
}

private extension AuthenticationPresentationState {
    var supportStateLabel: String {
        switch self {
        case .localCredentialMissing: "local-credential-missing"
        case .localCredentialInvalid: "local-credential-invalid"
        case .localCredentialUnavailable: "local-credential-unavailable"
        case .webSessionResetFailed: "web-session-reset-failed"
        case .waitingForWebView: "waiting-for-web-sign-in"
        case .webCredentialMissing: "web-credential-missing"
        case .webCredentialMalformed: "web-credential-malformed"
        case .webCredentialAmbiguous: "web-credential-ambiguous"
        case .verifyingAuthentication: "verifying-authentication"
        case .verifyingEntitlement: "verifying-entitlement"
        case .authenticatedButNotEntitled: "authenticated-not-entitled"
        case .entitled: "authenticated-entitled"
        case .restoreCompleted: "stored-session-restored"
        case .profileAuthorizationRejected: "profile-authorization-rejected"
        case .entitlementAuthorizationRejected: "entitlement-authorization-rejected"
        case .credentialNotDurable: "credential-persistence-failed"
        case .rejected: "authentication-rejected"
        case .challengeRequired: "challenge-required"
        case .unsupported: "authentication-unsupported"
        case .signedOut: "signed-out"
        case .cleanupFailed: "cleanup-failed"
        case .finishingCleanup: "finishing-cleanup"
        }
    }

    var isSuccessfulForSupport: Bool {
        switch self {
        case .entitled, .restoreCompleted: true
        default: false
        }
    }

    var supportDiagnosticCode: SupportDiagnosticCode? {
        switch self {
        case .localCredentialUnavailable: .authenticationStoredSessionUnavailable
        case .localCredentialInvalid: .authenticationStoredSessionInvalid
        case .profileAuthorizationRejected, .rejected: .authenticationRejected
        case .entitlementAuthorizationRejected, .authenticatedButNotEntitled: .entitlementUnavailable
        case .challengeRequired: .authenticationChallengeRequired
        case .unsupported, .webCredentialMalformed, .webCredentialAmbiguous: .authenticationUnsupportedResponse
        case .webSessionResetFailed: .authenticationWebSessionResetFailed
        case .credentialNotDurable: .authenticationCredentialPersistenceFailed
        case .cleanupFailed: .authenticationCleanupFailed
        case .localCredentialMissing, .waitingForWebView, .webCredentialMissing,
             .verifyingAuthentication, .verifyingEntitlement, .entitled, .restoreCompleted,
             .signedOut, .finishingCleanup:
            nil
        }
    }
}

private extension CatalogFailure {
    var supportDiagnosticCode: SupportDiagnosticCode? {
        switch self {
        case .unavailable: .catalogUnavailable
        case .authenticationUnavailable: .catalogAuthenticationUnavailable
        case .notEntitled: .catalogNotEntitled
        case .partialLineup: .catalogPartialLineup
        case .paginationUnavailable: .catalogPaginationIncomplete
        case .collectionUnavailable: .catalogCollectionMissing
        case .malformedCandidate: .catalogMalformedChannel
        case .conflictingIdentity: .catalogConflictingIdentity
        case .unsupportedResponse: .catalogUnsupportedResponse
        case .cancelled: nil
        }
    }
}

private extension LiveListeningFailure {
    var supportDiagnosticCode: SupportDiagnosticCode? {
        switch self {
        case .authorizationUnavailable: .streamAuthorizationUnavailable
        case .entitlementUnavailable: .streamEntitlementUnavailable
        case .catalogUnavailable: .streamCatalogUnavailable
        case .selectionUnavailable: .streamSelectionUnavailable
        case .resolutionUnavailable: .streamResolutionUnavailable
        case .protectedControl: .streamProtectedControl
        case .networkUnavailable: .playbackNetworkUnavailable
        case .bufferingUnavailable: .playbackBufferingUnavailable
        case .decoderUnavailable: .playbackDecoderUnavailable
        case .recoveryExhausted: .playbackRecoveryExhausted
        case .unsupported: .playbackUnsupported
        case .cancelled, .superseded: nil
        }
    }
}
