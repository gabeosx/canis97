import Foundation
import Observation
import SiriusXMClient

/// Provider-neutral selection state for the smallest authorized-listening composition.
@MainActor
@Observable
final class ListeningPresentationModel {
    let playbackCoordinator: PlaybackCoordinator
    private(set) var catalog: LiveCatalogPresentation = .unavailable
    private(set) var selectedChannelID: LiveChannelID?

    init(playbackCoordinator: PlaybackCoordinator = PlaybackCoordinator()) {
        self.playbackCoordinator = playbackCoordinator
    }

    func present(_ snapshot: LiveCatalogSnapshot) {
        catalog = .snapshot(snapshot)
    }

    func select(_ channelID: LiveChannelID) {
        selectedChannelID = channelID
    }

    func playSelectedChannel() async {
        guard let selectedChannelID else {
            return
        }
        await playbackCoordinator.tune(selectedChannelID)
    }
}
