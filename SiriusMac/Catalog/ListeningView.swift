import SwiftUI
import AppKit
import SiriusXMClient

/// A compact native browser for semantic catalog snapshots. Row selection only
/// stores a stable identity; playback authority remains in a later tune flow.
struct ListeningView: View {
    @Bindable var model: ListeningPresentationModel
    let libraryStore: LibraryStore?
    @State private var isClearRecentsConfirmationPresented = false

    init(model: ListeningPresentationModel, libraryStore: LibraryStore? = nil) {
        self.model = model
        self.libraryStore = libraryStore
    }

    var channelSelection: Binding<LiveChannelID?> {
        Binding(
            get: { model.selectedChannelID },
            set: { selection in
                if let selection {
                    model.select(selection)
                } else {
                    model.clearSelection()
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Channels", systemImage: "music.note.list")
                    .font(.title2)
                Spacer()
                freshnessLabel
                Button("Refresh") { _ = model.refresh() }
                    .accessibilityIdentifier("listening.refresh")
                    .accessibilityLabel("Refresh Channels")
                    .disabled(isLoading)
                if libraryStore != nil {
                    Button("Clear Recents") {
                        isClearRecentsConfirmationPresented = true
                    }
                    .disabled(libraryStore?.recents.isEmpty ?? true)
                }
            }

            content
            recentSummary
            metadata
            playbackControls
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Entitled SiriusXM channels")
        .alert("Clear Recents?", isPresented: $isClearRecentsConfirmationPresented) {
            Button("Keep Recents", role: .cancel) {}
            Button("Clear Recents", role: .destructive) {
                libraryStore?.clearRecents()
            }
        } message: {
            Text("This removes your recently played channels from this Mac. Favorites will not be changed.")
        }
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
            List(snapshot.channels, id: \.id, selection: channelSelection) { channel in
                ChannelRow(
                    channel: channel,
                    isFavorite: libraryStore?.isFavorite(channel.id) ?? false,
                    onFavoriteChange: libraryStore.map { store in
                        { isFavorite in store.setFavorite(LibraryChannelSnapshot(channel), isFavorite: isFavorite) }
                    }
                )
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

    @ViewBuilder
    private var recentSummary: some View {
        if let libraryStore {
            if libraryStore.recents.isEmpty {
                Label("Channels you play will appear here.", systemImage: "clock")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Recents: Channels you play will appear here.")
            } else {
                Label("\(libraryStore.recents.count) recently played channel\(libraryStore.recents.count == 1 ? "" : "s")", systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var playbackControls: some View {
        HStack {
            Button("Tune") { _ = model.tuneSelectedChannel() }
                .accessibilityIdentifier("listening.tune")
                .accessibilityLabel("Tune selected channel")
                .disabled(model.selectedChannelID == nil)
            Button("Pause") { _ = model.pausePlayback() }
                .accessibilityIdentifier("listening.pause")
                .accessibilityLabel("Pause playback")
            Button("Resume Live") { _ = model.resumePlaybackAtLiveEdge() }
                .accessibilityIdentifier("listening.resume-live")
                .accessibilityLabel("Resume at live edge")
            Button("Stop") { _ = model.stopPlayback() }
                .accessibilityIdentifier("listening.stop")
                .accessibilityLabel("Stop playback")
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
            artworkView(state.artwork)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func artworkView(_ artwork: LiveMetadataArtwork) -> some View {
        switch artwork {
        case let .current(data), let .stale(data):
            NativeArtworkImage(artwork: data)
                .frame(width: 52, height: 52)
                .accessibilityLabel(metadataArtwork(artwork))
        case .unavailable:
            Text(metadataArtwork(artwork))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(metadataArtwork(artwork))
        }
    }

    private func metadataText(_ text: LiveMetadataText) -> String {
        return switch text {
        case let .current(value): value
        case let .stale(value): "Stale: \(value)"
        case .channelFallback:
            if let channelLabel = model.confirmedChannelLabel {
                "Current program unavailable on \(channelLabel)"
            } else {
                "Current program unavailable"
            }
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

struct NativeArtworkImage: View {
    let artwork: ArtworkData

    var body: some View {
        if let image = Self.decode(artwork) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Artwork unavailable")
        }
    }

    static func decode(_ artwork: ArtworkData) -> NSImage? {
        NSImage(data: artwork.bytes)
    }
}

private struct ChannelRow: View {
    let channel: LiveChannel
    let isFavorite: Bool
    let onFavoriteChange: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: channel.artwork == nil ? "music.note" : "photo")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(channelTitle)
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
            if let onFavoriteChange {
                Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                    onFavoriteChange(!isFavorite)
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                .accessibilityValue(isFavorite ? "Favorite" : "Not favorite")
                .overlay {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityLabel(isFavorite ? "\(accessibilityName), Favorite" : accessibilityName)
    }

    private var accessibilityName: String {
        guard let number = channel.displayNumber else { return channelTitle }
        return "\(number), \(channelTitle)"
    }

    private var channelTitle: String {
        let name = channel.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty, name != channel.id.rawValue else {
            return channel.displayNumber.map { "Channel \($0)" } ?? "Unnamed channel"
        }
        return name
    }
}
