import SwiftUI
import SiriusXMClient

/// A compact native browser for semantic catalog snapshots. Row selection only
/// stores a stable identity; playback authority remains in a later tune flow.
struct ListeningView: View {
    @Bindable var model: ListeningPresentationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Channels", systemImage: "music.note.list")
                    .font(.title2)
                Spacer()
                freshnessLabel
                Button("Refresh") { _ = model.refresh() }
                    .disabled(isLoading)
            }

            content
            metadata
            playbackControls
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Entitled SiriusXM channels")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            ContentUnavailableView("Refresh to load your channels", systemImage: "arrow.clockwise")
        case .loading:
            ProgressView("Refreshing channels")
        case .empty:
            ContentUnavailableView("No entitled live channels", systemImage: "music.note")
        case let .failed(failure):
            ContentUnavailableView("Channels unavailable", systemImage: "exclamationmark.triangle", description: Text(failureCopy(failure)))
        case let .available(snapshot), let .stale(snapshot, _):
            List(snapshot.channels, id: \.id, selection: $model.selectedChannelID) { channel in
                ChannelRow(channel: channel)
                    .tag(channel.id)
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var freshnessLabel: some View {
        if let freshness = model.state.freshness {
            Label(
                freshness == .fresh ? "Current lineup" : "Stale lineup",
                systemImage: freshness == .fresh ? "checkmark.circle" : "clock.badge.exclamationmark"
            )
            .foregroundStyle(freshness == .fresh ? Color.secondary : Color.orange)
            .accessibilityLabel(freshness == .fresh ? "Current channel lineup" : "Stale channel lineup")
        }
    }

    private var isLoading: Bool {
        if case .loading = model.state { return true }
        return false
    }

    private var playbackControls: some View {
        HStack {
            Button("Tune") { _ = model.tuneSelectedChannel() }
                .disabled(model.selectedChannelID == nil)
            Button("Pause") { _ = model.pausePlayback() }
            Button("Resume Live") { _ = model.resumePlaybackAtLiveEdge() }
            Button("Stop") { _ = model.stopPlayback() }
            Spacer()
            Text(playbackCopy(model.playbackState))
                .foregroundStyle(.secondary)
                .accessibilityLabel(playbackCopy(model.playbackState))
        }
    }

    private var metadata: some View {
        let state = model.metadataPresentation.state
        return VStack(alignment: .leading, spacing: 4) {
            Text(metadataText(state.text))
                .accessibilityLabel("Current metadata: \(metadataText(state.text))")
            Text(metadataArtwork(state.artwork))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(metadataArtwork(state.artwork))
        }
        .accessibilityElement(children: .contain)
    }

    private func metadataText(_ text: LiveMetadataText) -> String {
        switch text {
        case let .current(value): value
        case let .stale(value): "Stale: \(value)"
        case let .channelFallback(id): "Channel \(id.rawValue)"
        case .unavailable: "Current program unavailable"
        }
    }

    private func metadataArtwork(_ artwork: LiveMetadataArtwork) -> String {
        switch artwork {
        case .current: "Current artwork available"
        case .stale: "Stale artwork"
        case .unavailable: "Artwork unavailable"
        }
    }

    private func playbackCopy(_ state: LivePlaybackState) -> String {
        switch state {
        case .awaitingLiveContract: "Playback unavailable"
        case .idle: "Ready"
        case .playing: "Playing"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .unavailable: "Playback unavailable"
        }
    }

    private func failureCopy(_ failure: CatalogFailure) -> String {
        switch failure {
        case .authenticationUnavailable: "Sign in again to refresh channels."
        case .notEntitled: "This account is not currently entitled to listen."
        case .cancelled: "The refresh was cancelled."
        case .unavailable, .collectionUnavailable, .malformedCandidate, .conflictingIdentity, .unsupportedResponse:
            "The channel lineup could not be refreshed safely."
        }
    }
}

private struct ChannelRow: View {
    let channel: LiveChannel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: channel.artwork == nil ? "music.note" : "photo")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name ?? channel.id.rawValue)
                if let category = channel.category {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let number = channel.displayNumber {
                Text(String(number))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(accessibilityName)
    }

    private var accessibilityName: String {
        let name = channel.name ?? channel.id.rawValue
        guard let number = channel.displayNumber else { return name }
        return "\(number), \(name)"
    }
}
