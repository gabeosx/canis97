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

enum LibraryTab: String, CaseIterable, Identifiable {
    case channels
    case categories
    case favorites
    case recents

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct LibrarySearchQuery: Equatable {
    let value: String

    init(_ value: String) { self.value = value }

    var filtersVisibleCollection: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The authenticated library window. It projects only semantic catalog values
/// and local stable-ID state; selection never authorizes playback.
struct LibraryView: View {
    @Bindable var model: ListeningPresentationModel
    let libraryStore: LibraryStore
    let controller: ListeningSessionController?
    @State private var tab: LibraryTab
    @State private var query = ""

    init(controller: ListeningSessionController) {
        model = controller.listeningModel
        libraryStore = controller.libraryStore
        self.controller = controller
        _tab = State(initialValue: LibraryTab(rawValue: controller.libraryStore.selectedLibraryTab) ?? .channels)
    }

    init(model: ListeningPresentationModel, libraryStore: LibraryStore) {
        self.model = model
        self.libraryStore = libraryStore
        controller = nil
        _tab = State(initialValue: LibraryTab(rawValue: libraryStore.selectedLibraryTab) ?? .channels)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                Picker("Library", selection: $tab) {
                    ForEach(LibraryTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onChange(of: tab) { _, value in libraryStore.setSelectedLibraryTab(value.rawValue) }

                TextField("Search Channels", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Search visible library collection")

                libraryContent
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { _ = model.refresh() }
                }
            }
            .onChange(of: controller?.libraryRevealRequest) { _, request in
                guard let request else { return }
                tab = .channels
                if filteredChannels.contains(where: { $0.id == request.channelID }) == false {
                    query = ""
                }
                withAnimation(.easeInOut(duration: 0.12)) { proxy.scrollTo(request.channelID, anchor: .center) }
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .accessibilityLabel("Sirius Mac library")
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch model.state {
        case .idle:
            ContentUnavailableView("Refresh to load your channels", systemImage: "arrow.clockwise")
        case .loading where model.state.snapshot == nil:
            ProgressView("Loading channels")
        case let .failed(failure):
            VStack(spacing: 12) {
                ContentUnavailableView("Channels unavailable", systemImage: "exclamationmark.triangle", description: Text(failureCopy(failure)))
                Button("Try Again") { _ = model.refresh() }
            }
        default:
            List(filteredChannels, id: \.id, selection: selection) { channel in
                libraryRow(channel)
                    .id(channel.id)
                    .tag(channel.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { tune(channel) }
            }
            .listStyle(.inset)
            .onSubmit { if let selected = model.selectedChannelID, let channel = filteredChannels.first(where: { $0.id == selected }) { tune(channel) } }
        }
    }

    private var selection: Binding<LiveChannelID?> {
        Binding(get: { model.selectedChannelID }, set: { value in
            if let value { model.select(value) } else { model.clearSelection() }
        })
    }

    private var currentChannels: [LiveChannel] { model.state.snapshot?.channels ?? [] }

    private var tabChannels: [LiveChannel] {
        switch tab {
        case .channels: currentChannels
        case .categories: currentChannels.sorted { ($0.category ?? "") == ($1.category ?? "") ? $0.id.rawValue < $1.id.rawValue : ($0.category ?? "") < ($1.category ?? "") }
        case .favorites: currentChannels.filter { libraryStore.isFavorite($0.id) }
        case .recents:
            libraryStore.recents.compactMap { recent in currentChannels.first(where: { $0.id == recent.id }) }
        }
    }

    private var filteredChannels: [LiveChannel] {
        let search = LibrarySearchQuery(query)
        guard search.filtersVisibleCollection else { return tabChannels }
        let needle: (String) -> Bool = { value in value.localizedCaseInsensitiveContains(search.value) }
        return tabChannels.filter { channel in
            needle(channel.name ?? "") || needle(channel.category ?? "") || needle(channel.displayNumber.map(String.init) ?? "")
        }
    }

    private func libraryRow(_ channel: LiveChannel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayNumber.map(String.init) ?? "Channel")
                    .font(.caption)
                Text(channel.name ?? "Unnamed channel")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(channel.name ?? "Unnamed channel")
                if let category = channel.category {
                    Text(category).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(category)
                }
            }
            Spacer()
            if model.confirmedChannelID == channel.id { Label("Now Playing", systemImage: "speaker.wave.2.fill").labelStyle(.iconOnly).accessibilityLabel("Now Playing") }
            Button(libraryStore.isFavorite(channel.id) ? "Remove from Favorites" : "Add to Favorites") {
                libraryStore.setFavorite(LibraryChannelSnapshot(channel), isFavorite: !libraryStore.isFavorite(channel.id))
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: 44)
        .accessibilityLabel(channel.name ?? "Unnamed channel")
        .accessibilityValue(model.confirmedChannelID == channel.id ? "Now Playing" : "")
    }

    private func tune(_ channel: LiveChannel) {
        if let controller { _ = controller.tune(channelID: channel.id, originIDs: tabChannels.map(\.id)) }
        else { model.select(channel.id); _ = model.tuneSelectedChannel() }
    }

    private func failureCopy(_ failure: CatalogFailure) -> String {
        switch failure {
        case .authenticationUnavailable: "Sign in again to refresh channels."
        case .notEntitled: "This account is not currently entitled to listen."
        default: "The channel lineup could not be refreshed safely."
        }
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
