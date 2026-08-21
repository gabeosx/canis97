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

    private(set) var hasRequestedLibraryOpen = false
    private var hasTriggeredAutomaticCatalogLoad = false
    private var lastObservedPlaybackState: LivePlaybackState = .awaitingLiveContract

    init(
        composition: AuthenticationComposition = AuthenticationComposition(),
        authenticationModel: AuthenticationPresentationModel? = nil,
        libraryStore: LibraryStore? = nil
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

    func resetListeningBeforeAuthenticationCleanup() {
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
