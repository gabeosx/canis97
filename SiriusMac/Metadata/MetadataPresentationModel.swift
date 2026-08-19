import Foundation
import Observation
import SiriusXMClient

protocol MetadataFlow: AnyObject, Sendable {
    func metadata(for channelID: LiveChannelID) async -> MetadataAvailability
    func artwork(for reference: ChannelArtworkReference) async -> ArtworkAvailability
}

extension SiriusXMClient: MetadataFlow {}

struct MetadataRefreshPolicy: Sendable, Equatable {
    let pollInterval: TimeInterval
    let staleAfter: TimeInterval
    let unavailableAfter: TimeInterval
    static let `default` = Self(pollInterval: 30, staleAfter: 90, unavailableAfter: 300)
}

/// Presentation-owned metadata lifecycle. It deliberately has no playback collaborator.
@MainActor
@Observable
final class MetadataPresentationModel {
    private let flow: any MetadataFlow
    private let policy: MetadataRefreshPolicy
    private var metadataTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var generation = 0
    private var refreshedAt: Date?
    private(set) var state: LiveMetadataState

    init(flow: any MetadataFlow = UnavailableMetadataFlow(), policy: MetadataRefreshPolicy = .default) {
        self.flow = flow
        self.policy = policy
        let channelID = LiveChannelID("semantic-unselected-channel")
        state = LiveMetadataState(channelID: channelID, text: .channelFallback(channelID), artwork: .unavailable, refreshedAt: nil)
    }

    func select(_ channelID: LiveChannelID) {
        generation &+= 1
        metadataTask?.cancel()
        artworkTask?.cancel()
        state = LiveMetadataState(channelID: channelID, text: .channelFallback(channelID), artwork: .unavailable, refreshedAt: nil)
        refreshedAt = nil
        let expected = generation
        metadataTask = Task { [weak self] in await self?.refreshLoop(channelID: channelID, generation: expected) }
    }

    func clear() {
        generation &+= 1
        metadataTask?.cancel()
        artworkTask?.cancel()
        metadataTask = nil
        artworkTask = nil
        let channelID = LiveChannelID("semantic-unselected-channel")
        state = LiveMetadataState(channelID: channelID, text: .channelFallback(channelID), artwork: .unavailable, refreshedAt: nil)
        refreshedAt = nil
    }

    private func refreshLoop(channelID: LiveChannelID, generation expected: Int) async {
        while !Task.isCancelled, generation == expected {
            await refresh(channelID: channelID, generation: expected)
            guard !Task.isCancelled, generation == expected else { return }
            try? await Task.sleep(for: .seconds(policy.pollInterval))
        }
    }

    private func refresh(channelID: LiveChannelID, generation expected: Int) async {
        let result = await flow.metadata(for: channelID)
        guard !Task.isCancelled, generation == expected else { return }
        switch result {
        case let .current(snapshot):
            let program = snapshot.program
            let text = presentationText(for: program, channelID: channelID)
            state = LiveMetadataState(channelID: channelID, text: text, artwork: .unavailable, refreshedAt: Date())
            refreshedAt = state.refreshedAt
            if let reference = program?.artwork {
                startArtworkFetch(for: reference, channelID: channelID, generation: expected)
            }
        case .unavailable, .failed:
            advanceFreshness(for: channelID)
        }
    }

    private func advanceFreshness(for channelID: LiveChannelID) {
        guard let refreshedAt else { return }
        let age = Date().timeIntervalSince(refreshedAt)
        if age >= policy.unavailableAfter {
            state = LiveMetadataState(channelID: channelID, text: .channelFallback(channelID), artwork: .unavailable, refreshedAt: nil)
        } else if age >= policy.staleAfter {
            state = LiveMetadataState(channelID: channelID, text: stale(state.text), artwork: stale(state.artwork), refreshedAt: refreshedAt)
        }
    }

    private func stale(_ text: LiveMetadataText) -> LiveMetadataText { if case let .current(value) = text { return .stale(value) }; return text }
    private func stale(_ artwork: LiveMetadataArtwork) -> LiveMetadataArtwork { if case let .current(value) = artwork { return .stale(value) }; return artwork }

    private func presentationText(for program: LiveProgramMetadata?, channelID: LiveChannelID) -> LiveMetadataText {
        guard let program, !program.title.isEmpty else { return .channelFallback(channelID) }
        if let artist = program.artist, !artist.isEmpty {
            return .current("\(artist) — \(program.title)")
        }
        return .current(program.title)
    }

    private func startArtworkFetch(
        for reference: ChannelArtworkReference,
        channelID: LiveChannelID,
        generation expected: Int
    ) {
        artworkTask?.cancel()
        let flow = flow
        artworkTask = Task { [weak self] in
            let result = await flow.artwork(for: reference)
            guard let self, !Task.isCancelled, self.generation == expected, self.state.channelID == channelID else { return }
            guard case let .current(artwork) = result else { return }
            self.state = LiveMetadataState(
                channelID: channelID,
                text: self.state.text,
                artwork: .current(artwork),
                refreshedAt: self.state.refreshedAt
            )
        }
    }
}

private final class UnavailableMetadataFlow: MetadataFlow, @unchecked Sendable {
    func metadata(for _: LiveChannelID) async -> MetadataAvailability { .unavailable }
    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }
}
