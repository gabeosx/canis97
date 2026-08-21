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

    private(set) var hasRequestedLibraryOpen = false

    init(composition: AuthenticationComposition = AuthenticationComposition()) {
        self.composition = composition
        bridge = composition.bridge
        authenticationModel = AuthenticationPresentationModel(flow: composition.flow)
        playbackCoordinator = composition.playbackCoordinator
        listeningModel = ListeningPresentationModel(
            flow: composition.listeningFlow,
            playbackCoordinator: composition.playbackCoordinator
        )
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

    private func surface(for role: ListeningSurfaceRole) -> ListeningSurfaceState {
        let playbackState = listeningModel.playbackState
        let activeChannelID: LiveChannelID?
        if case let .playing(channelID) = playbackState {
            activeChannelID = channelID
        } else {
            activeChannelID = nil
        }
        return ListeningSurfaceState(
            role: role,
            coordinatorIdentity: ObjectIdentifier(playbackCoordinator),
            selectedChannelID: listeningModel.selectedChannelID,
            activeChannelID: activeChannelID,
            playbackState: playbackState
        )
    }
}
