import Foundation
import Observation
import SiriusXMClient

/// Main-actor presentation ownership for metadata that remains independent from audio control.
@MainActor
@Observable
final class MetadataPresentationModel {
    private let coordinator: MetadataRefreshCoordinator

    private(set) var state: LiveMetadataState

    init(coordinator: MetadataRefreshCoordinator = MetadataRefreshCoordinator()) {
        self.coordinator = coordinator
        let channelID = LiveChannelID("semantic-unselected-channel")
        state = LiveMetadataState(
            channelID: channelID,
            text: .channelFallback(channelID),
            artwork: .unavailable,
            refreshedAt: nil
        )
    }

    func select(_ channelID: LiveChannelID) async {
        state = await coordinator.select(channelID)
    }

    func refresh() async {
        state = await coordinator.refresh()
    }
}
