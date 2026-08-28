import SwiftUI
import AppKit
import SiriusXMClient

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

private struct ChannelArtworkImage: View {
    let reference: ChannelArtworkReference?
    @Bindable var artworkStore: ArtworkStore

    var body: some View {
        let state = artworkStore.loadState(for: reference)
        Group {
            if let artwork = artworkStore.artwork(for: reference) {
                NativeArtworkImage(artwork: artwork)
            } else {
                Image(systemName: state == .unavailable ? "photo.badge.exclamationmark" : "photo")
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(artworkAccessibilityLabel(for: state))
            }
        }
        .task(id: reference) {
            await artworkStore.load(reference)
        }
    }

    private func artworkAccessibilityLabel(for state: ChannelArtworkLoadState) -> String {
        switch state {
        case .noReference: "No channel artwork provided"
        case .idle, .loading: "Channel artwork loading"
        case .available: "Channel artwork"
        case .unavailable: "Channel artwork unavailable"
        }
    }
}

enum LibraryTab: String, CaseIterable, Identifiable {
    case channels
    case categories
    case favorites
    case favoriteSongs
    case recents

    var id: String { rawValue }
    var title: String {
        switch self {
        case .channels: "Channels"
        case .categories: "Categories"
        case .favorites: "Favorites"
        case .favoriteSongs: "Favorite Songs"
        case .recents: "Recents"
        }
    }
}

struct LibrarySearchQuery: Equatable {
    let value: String

    init(_ value: String) { self.value = value }

    var filtersVisibleCollection: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct FavoriteSongSearch: Equatable {
    private let query: LibrarySearchQuery

    init(_ value: String) {
        query = LibrarySearchQuery(value)
    }

    func matches(_ snapshot: FavoriteSongSnapshot) -> Bool {
        guard query.filtersVisibleCollection else { return true }
        let matches = { (value: String) in
            value.localizedCaseInsensitiveContains(query.value)
        }
        return matches(snapshot.title)
            || matches(snapshot.artist)
            || snapshot.albumName.map(matches) == true
            || matches(FavoriteSongRow.sourcePresentation(for: snapshot))
    }
}

@MainActor
protocol SongFavoriteClipboardWriting {
    func copy(_ text: String)
}

@MainActor
final class SystemSongFavoriteClipboardWriter: SongFavoriteClipboardWriting {
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct LibraryRevealDisposition: Equatable {
    let tab: LibraryTab
    let clearsSearch: Bool
}

enum LibraryRevealPolicy {
    /// Queue navigation should preserve the collection the subscriber is
    /// browsing whenever that collection can represent the requested channel.
    /// Channels is only the fallback needed to fulfill an otherwise impossible
    /// reveal; a search is cleared only when it hides the requested row.
    static func disposition(
        currentTab: LibraryTab,
        currentCollectionIDs: [LiveChannelID],
        visibleIDs: [LiveChannelID],
        targetID: LiveChannelID
    ) -> LibraryRevealDisposition {
        guard currentCollectionIDs.contains(targetID) else {
            return LibraryRevealDisposition(tab: .channels, clearsSearch: true)
        }
        return LibraryRevealDisposition(
            tab: currentTab,
            clearsSearch: !visibleIDs.contains(targetID)
        )
    }
}

enum LibraryChannelAvailability: Equatable {
    case available
    case unknown
    case unavailable

    var canTune: Bool { self == .available }

    var detail: String? {
        switch self {
        case .available: nil
        case .unknown: "Saved on this Mac · Availability unknown"
        case .unavailable: "Saved on this Mac · Unavailable in the current lineup"
        }
    }
}

/// One truthful library row. Saved collections keep their durable snapshot
/// even when the latest catalog cannot currently supply the channel.
struct LibraryChannelItem: Identifiable, Equatable {
    let channel: LiveChannel
    let availability: LibraryChannelAvailability

    var id: LiveChannelID { channel.id }

    static func current(_ channels: [LiveChannel]) -> [Self] {
        channels.map { Self(channel: $0, availability: .available) }
    }

    static func saved(
        _ snapshots: [LibraryChannelSnapshot],
        currentChannels: [LiveChannel],
        catalogIsResolved: Bool
    ) -> [Self] {
        let currentByID = Dictionary(uniqueKeysWithValues: currentChannels.map { ($0.id, $0) })
        return snapshots.map { snapshot in
            if let current = currentByID[snapshot.id] {
                return Self(channel: current, availability: .available)
            }
            return Self(
                channel: LiveChannel(
                    id: snapshot.id,
                    name: snapshot.name,
                    displayNumber: snapshot.displayNumber,
                    category: snapshot.category
                ),
                availability: catalogIsResolved ? .unavailable : .unknown
            )
        }
    }
}

/// A direct grouped projection for browsing the lineup by category. Category
/// headings are descriptive only; tuning continues to use channel identity.
struct LibraryCategoryGroup: Identifiable, Equatable {
    static let uncategorizedName = "Other"

    let id: String
    let name: String
    let channels: [LiveChannel]

    static func groups(from channels: [LiveChannel]) -> [LibraryCategoryGroup] {
        let grouped = Dictionary(grouping: channels) { channel in
            normalizedName(channel.category)
        }
        return grouped.map { name, channels in
            LibraryCategoryGroup(
                id: name,
                name: name,
                channels: channels.sorted(by: channelOrder)
            )
        }
        .sorted { left, right in
            if left.name == uncategorizedName { return false }
            if right.name == uncategorizedName { return true }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private static func normalizedName(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? uncategorizedName : trimmed
    }

    private static func channelOrder(_ left: LiveChannel, _ right: LiveChannel) -> Bool {
        switch (left.displayNumber, right.displayNumber) {
        case let (leftNumber?, rightNumber?) where leftNumber != rightNumber:
            return leftNumber < rightNumber
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            let titleOrder = (left.name ?? "").localizedStandardCompare(right.name ?? "")
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return left.id.rawValue < right.id.rawValue
        }
    }
}

private enum LibraryPalette {
    static let dominant = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
    static let secondary = Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
    static let accent = Color(red: 198 / 255, green: 255 / 255, blue: 0 / 255)
}

/// The authenticated library window. It projects only semantic catalog values
/// and local stable-ID state; selection never authorizes playback.
struct LibraryView: View {
    @Bindable var model: ListeningPresentationModel
    let libraryStore: LibraryStore
    let controller: ListeningSessionController?
    let onTune: (@MainActor (LiveChannelID, [LiveChannelID]) -> Bool)?
    let songFavoriteClipboardWriter: any SongFavoriteClipboardWriting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: LibraryTab
    @State private var query = ""
    @State private var showsClearRecentsConfirmation = false
    @FocusState private var focusTarget: LibraryFocusTarget?

    init(controller: ListeningSessionController) {
        model = controller.listeningModel
        libraryStore = controller.libraryStore
        self.controller = controller
        onTune = nil
        songFavoriteClipboardWriter = SystemSongFavoriteClipboardWriter()
        _tab = State(initialValue: LibraryTab(rawValue: controller.libraryStore.selectedLibraryTab) ?? .channels)
    }

    init(
        model: ListeningPresentationModel,
        libraryStore: LibraryStore,
        onTune: (@MainActor (LiveChannelID, [LiveChannelID]) -> Bool)? = nil,
        songFavoriteClipboardWriter: any SongFavoriteClipboardWriting = SystemSongFavoriteClipboardWriter()
    ) {
        self.model = model
        self.libraryStore = libraryStore
        controller = nil
        self.onTune = onTune
        self.songFavoriteClipboardWriter = songFavoriteClipboardWriter
        _tab = State(initialValue: LibraryTab(rawValue: libraryStore.selectedLibraryTab) ?? .channels)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                libraryContent
                persistenceBanner
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LibraryPalette.dominant)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    libraryTabPicker
                }
                ToolbarItem {
                    librarySearchField
                }
                ToolbarItem {
                    if tab == .recents, !libraryStore.recents.isEmpty {
                        Button(role: .destructive) {
                            showsClearRecentsConfirmation = true
                        } label: {
                            Label("Clear Recents", systemImage: "trash")
                        }
                        .help("Clear Recents")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { _ = model.refresh() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .help("Refresh Channels")
                }
            }
            .onChange(of: controller?.libraryRevealRequest) { _, request in
                guard let request else { return }
                let disposition = LibraryRevealPolicy.disposition(
                    currentTab: tab,
                    currentCollectionIDs: tabChannels.map(\.id),
                    visibleIDs: filteredChannels.map(\.id),
                    targetID: request.channelID
                )
                tab = disposition.tab
                if disposition.clearsSearch {
                    query = ""
                }
                if reduceMotion {
                    proxy.scrollTo(request.channelID, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.12)) { proxy.scrollTo(request.channelID, anchor: .center) }
                }
            }
            .onChange(of: controller?.librarySearchFocusGeneration) { _, _ in
                focusTarget = .search
            }
            .onChange(of: filteredChannels.map(\.id)) { previousIDs, currentIDs in
                guard tab != .favoriteSongs else { return }
                restoreSelectionAfterRefresh(previousIDs: previousIDs, currentIDs: currentIDs)
            }
            .confirmationDialog(
                "Clear Recents?",
                isPresented: $showsClearRecentsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Keep Recents", role: .cancel) {}
                Button("Clear Recents", role: .destructive) { libraryStore.clearRecents() }
            } message: {
                Text("This removes your recently played channels from this Mac. Favorites will not be changed.")
            }
        }
        .frame(minWidth: 760, minHeight: 540, alignment: .top)
        .tint(LibraryPalette.accent)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("\(ProductIdentity.displayName) library")
    }

    private var libraryTabPicker: some View {
        Picker("Library", selection: $tab) {
            ForEach(LibraryTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 480)
        .onChange(of: tab) { _, value in
            libraryStore.setSelectedLibraryTab(value.rawValue)
        }
        .accessibilityIdentifier("library.tabs")
        .accessibilitySortPriority(30)
    }

    private var librarySearchField: some View {
        TextField("Search \(tab.title)", text: $query)
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
            .accessibilityLabel("Search visible library collection")
            .accessibilityIdentifier("library.search")
            .focused($focusTarget, equals: .search)
            .accessibilitySortPriority(29)
    }

    @ViewBuilder
    private var persistenceBanner: some View {
        if let persistenceNotice {
            Label(persistenceNotice, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LibraryPalette.secondary)
                .accessibilityIdentifier("library.persistence-notice")
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if tab == .favoriteSongs {
            favoriteSongContent
        } else if tab == .favorites || tab == .recents {
            collectionContent
        } else {
            switch model.state {
            case .idle:
                ContentUnavailableView {
                    Label("Load Your Channels", systemImage: "music.note.list")
                } description: {
                    Text("Refresh to load the current SiriusXM channel guide.")
                } actions: {
                    Button("Refresh Channels") { _ = model.refresh() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading where model.state.snapshot == nil:
                ProgressView("Loading channels")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(failure):
                ContentUnavailableView {
                    Label("Channels Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failureCopy(failure))
                } actions: {
                    Button(recoveryTitle(for: failure)) { recover(from: failure) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                collectionContent
            }
        }
    }

    @ViewBuilder
    private var favoriteSongContent: some View {
        if filteredFavoriteSongs.isEmpty {
            ContentUnavailableView {
                Label(favoriteSongEmptyTitle, systemImage: LibrarySearchQuery(query).filtersVisibleCollection ? "magnifyingglass" : "music.note")
            } description: {
                Text(favoriteSongEmptyDescription)
            } actions: {
                if LibrarySearchQuery(query).filtersVisibleCollection {
                    Button("Clear Search") { query = "" }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("\(favoriteSongEmptyTitle). \(favoriteSongEmptyDescription)")
        } else {
            favoriteSongList
        }
    }

    @ViewBuilder
    private var collectionContent: some View {
        if filteredChannels.isEmpty {
            ContentUnavailableView {
                Label(emptyCollectionTitle, systemImage: emptyCollectionSystemImage)
            } description: {
                Text(emptyCollectionDescription)
            } actions: {
                Button(emptyCollectionActionTitle) { performEmptyCollectionAction() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("\(emptyCollectionTitle). \(emptyCollectionDescription)")
        } else if tab == .categories {
            categoryList
        } else {
            channelList
        }
    }

    private var channelList: some View {
        List(filteredChannels, selection: selection) { item in
            libraryRow(item)
                .id(item.id)
                .tag(item.id)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(LibraryPalette.dominant)
        .focused($focusTarget, equals: .collection)
        .accessibilityIdentifier("library.collection")
        .accessibilitySortPriority(27)
        .background(NativeListDoubleActionBridge { clickedRow in
            tuneClickedRow(at: clickedRow)
        })
        .onKeyPress(.return) { tuneSelectedChannel(); return .handled }
        .onKeyPress(.space) {
            guard focusTarget != .search else { return .ignored }
            _ = controller?.toggleConfirmedPlayback()
            return .handled
        }
    }

    private var favoriteSongList: some View {
        List(filteredFavoriteSongs, id: \.identity) { snapshot in
            FavoriteSongRow(
                snapshot: snapshot,
                onCopy: { songFavoriteClipboardWriter.copy(snapshot.copyText) },
                onRemove: { setSongFavorite(snapshot, isFavorite: false) }
            )
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(LibraryPalette.dominant)
        .focused($focusTarget, equals: .collection)
        .accessibilityLabel("Favorite Songs")
        .accessibilityIdentifier("library.favorite-songs")
        .accessibilitySortPriority(27)
    }

    private var categoryList: some View {
        List(selection: selection) {
            ForEach(filteredCategoryGroups) { group in
                Section {
                    ForEach(group.channels, id: \.id) { channel in
                        let item = LibraryChannelItem(channel: channel, availability: .available)
                        libraryRow(item)
                            .id(channel.id)
                            .tag(channel.id)
                            .contentShape(.rect)
                            .onTapGesture(count: 2) { _ = tune(item) }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(group.name)
                            .font(.system(size: 14, weight: .semibold))
                        Text(group.channels.count, format: .number)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityLabel("\(group.name), \(group.channels.count) channels")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(LibraryPalette.dominant)
        .focused($focusTarget, equals: .collection)
        .accessibilityLabel("Channels grouped by category")
        .accessibilityIdentifier("library.categories")
        .accessibilitySortPriority(27)
        .onKeyPress(.return) { tuneSelectedChannel(); return .handled }
        .onKeyPress(.space) {
            guard focusTarget != .search else { return .ignored }
            _ = controller?.toggleConfirmedPlayback()
            return .handled
        }
    }

    private var selection: Binding<LiveChannelID?> {
        Binding(get: { model.selectedChannelID }, set: { value in
            if let value { model.select(value) } else { model.clearSelection() }
        })
    }

    private var currentChannels: [LiveChannel] { model.state.snapshot?.channels ?? [] }

    private var catalogIsResolved: Bool {
        switch model.state {
        case .available, .stale, .empty: true
        case .idle, .loading, .failed: false
        }
    }

    private var tabChannels: [LibraryChannelItem] {
        switch tab {
        case .channels:
            LibraryChannelItem.current(currentChannels)
        case .categories:
            LibraryChannelItem.current(
                LibraryCategoryGroup.groups(from: currentChannels).flatMap(\.channels)
            )
        case .favorites:
            LibraryChannelItem.saved(
                libraryStore.favorites,
                currentChannels: currentChannels,
                catalogIsResolved: catalogIsResolved
            )
        case .recents:
            LibraryChannelItem.saved(
                libraryStore.recents,
                currentChannels: currentChannels,
                catalogIsResolved: catalogIsResolved
            )
        case .favoriteSongs:
            []
        }
    }

    private var filteredChannels: [LibraryChannelItem] {
        let search = LibrarySearchQuery(query)
        guard search.filtersVisibleCollection else { return tabChannels }
        let needle: (String) -> Bool = { value in value.localizedCaseInsensitiveContains(search.value) }
        return tabChannels.filter { item in
            needle(item.channel.name ?? "")
                || needle(item.channel.category ?? "")
                || needle(item.channel.displayNumber.map(String.init) ?? "")
        }
    }

    private var filteredCategoryGroups: [LibraryCategoryGroup] {
        LibraryCategoryGroup.groups(from: filteredChannels.map(\.channel))
    }

    private var filteredFavoriteSongs: [FavoriteSongSnapshot] {
        let search = FavoriteSongSearch(query)
        return libraryStore.favoriteSongs.filter(search.matches)
    }

    private func libraryRow(_ item: LibraryChannelItem) -> some View {
        let channel = item.channel
        return HStack(spacing: 8) {
            ChannelArtworkImage(reference: channel.artwork, artworkStore: model.artworkStore)
                .frame(width: 28, height: 28)
                .background(.quaternary.opacity(0.35))
                .clipShape(.rect(cornerRadius: 4))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name ?? "Unnamed channel")
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(channel.name ?? "Unnamed channel")
                if !channelDetail(item).isEmpty {
                    Text(channelDetail(item))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(channelDetail(item))
                }
            }
            Spacer()
            if model.confirmedChannelID == channel.id {
                Label("Playing", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(LibraryPalette.accent)
                    .accessibilityLabel("Now Playing")
            }
            let isFavorite = libraryStore.isFavorite(channel.id)
            Button {
                setFavorite(channel)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFavorite ? LibraryPalette.accent : .secondary)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityIdentifier("library.favorite.\(channel.id.rawValue)")
            .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityValue(isFavorite ? "Favorite" : "Not favorite")
            .accessibilitySortPriority(10)
        }
        .frame(minHeight: 44)
        .listRowBackground(LibraryPalette.secondary)
        .accessibilityLabel(channelAccessibilityLabel(channel))
        .accessibilityValue(channelAccessibilityValue(item))
        .accessibilityIdentifier("library.row.\(channel.id.rawValue)")
        .accessibilitySortPriority(20)
        .contextMenu {
            Button("Tune") { tune(item) }
                .disabled(model.isTunePending || !item.availability.canTune)
            Button(libraryStore.isFavorite(channel.id) ? "Remove from Favorites" : "Add to Favorites") { setFavorite(channel) }
        }
    }

    @discardableResult
    private func tune(_ item: LibraryChannelItem) -> Bool {
        let channel = item.channel
        guard !model.isTunePending, item.availability.canTune else { return false }

        let originIDs = tabChannels.filter(\.availability.canTune).map(\.id)
        guard originIDs.contains(channel.id) else { return false }

        if let onTune { return onTune(channel.id, originIDs) }
        if let controller { return controller.tune(channelID: channel.id, originIDs: originIDs) != nil }
        model.select(channel.id)
        return model.tuneSelectedChannel() != nil
    }

    private func tuneClickedRow(at index: Int) {
        guard filteredChannels.indices.contains(index) else { return }
        _ = tune(filteredChannels[index])
    }

    private func tuneSelectedChannel() {
        guard let selected = model.selectedChannelID,
              let item = filteredChannels.first(where: { $0.id == selected })
        else { return }
        tune(item)
    }

    private func setFavorite(_ channel: LiveChannel) {
        let desiredState = !libraryStore.isFavorite(channel.id)
        if let controller {
            controller.setFavorite(LibraryChannelSnapshot(channel), isFavorite: desiredState)
        } else {
            libraryStore.setFavorite(LibraryChannelSnapshot(channel), isFavorite: desiredState)
        }
    }

    private func setSongFavorite(_ snapshot: FavoriteSongSnapshot, isFavorite: Bool) {
        if let controller {
            _ = controller.setSongFavorite(snapshot, isFavorite: isFavorite)
        } else {
            _ = libraryStore.setSongFavorite(snapshot, isFavorite: isFavorite)
        }
    }

    private func restoreSelectionAfterRefresh(previousIDs: [LiveChannelID], currentIDs: [LiveChannelID]) {
        guard let selected = model.selectedChannelID, !currentIDs.contains(selected) else { return }
        guard !currentIDs.isEmpty else {
            model.clearSelection()
            focusTarget = .collection
            return
        }
        let previousIndex = previousIDs.firstIndex(of: selected) ?? 0
        model.select(currentIDs[min(previousIndex, currentIDs.count - 1)])
        focusTarget = .collection
    }

    private func channelAccessibilityLabel(_ channel: LiveChannel) -> String {
        let number = channel.displayNumber.map(String.init) ?? "Channel"
        let name = channel.name ?? "Unnamed channel"
        return "\(number), \(name)"
    }

    private func channelAccessibilityValue(_ item: LibraryChannelItem) -> String {
        let channel = item.channel
        return [
            model.selectedChannelID == channel.id ? "Selected" : nil,
            model.confirmedChannelID == channel.id ? "Now Playing" : nil,
            libraryStore.isFavorite(channel.id) ? "Favorite" : nil,
            item.availability.detail,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private var emptyCollectionTitle: String {
        if LibrarySearchQuery(query).filtersVisibleCollection { return "No Matching Channels" }
        if hasNoAvailableChannels { return "No Channels Available" }
        return switch tab {
        case .favorites: "No Favorites Yet"
        case .favoriteSongs: "No Favorite Songs Yet"
        case .recents: "No Recent Channels"
        case .channels, .categories: "No Matching Channels"
        }
    }

    private var emptyCollectionDescription: String {
        if LibrarySearchQuery(query).filtersVisibleCollection {
            return "No channels in \(tab.title) match your search."
        }
        if hasNoAvailableChannels {
            return "The current channel guide is empty. Refresh the library or sign in again."
        }
        return switch tab {
        case .favorites: "Select the star beside a channel to keep it here."
        case .favoriteSongs: "Use Favorite Current Song in the Player menu to save a confirmed song."
        case .recents: "Channels you play will appear here."
        case .channels: "Change your search or refresh the library."
        case .categories: "Channels are grouped by their SiriusXM category."
        }
    }

    private var emptyCollectionSystemImage: String {
        if LibrarySearchQuery(query).filtersVisibleCollection { return "magnifyingglass" }
        return switch tab {
        case .favorites: "star"
        case .favoriteSongs: "music.note"
        case .recents: "clock"
        case .channels, .categories: "music.note.list"
        }
    }

    private var emptyCollectionActionTitle: String {
        if LibrarySearchQuery(query).filtersVisibleCollection { return "Clear Search" }
        return hasNoAvailableChannels ? "Refresh Channels" : "Browse Channels"
    }

    private func performEmptyCollectionAction() {
        if LibrarySearchQuery(query).filtersVisibleCollection {
            query = ""
        } else if hasNoAvailableChannels {
            _ = model.refresh()
        } else {
            tab = .channels
        }
    }

    private var hasNoAvailableChannels: Bool {
        currentChannels.isEmpty && (tab == .channels || tab == .categories)
    }

    private var favoriteSongEmptyTitle: String {
        LibrarySearchQuery(query).filtersVisibleCollection ? "No Matching Favorite Songs" : "No Favorite Songs Yet"
    }

    private var favoriteSongEmptyDescription: String {
        if LibrarySearchQuery(query).filtersVisibleCollection {
            return "No saved songs in Favorite Songs match your search."
        }
        return "Use Favorite Current Song in the Player menu to save a confirmed song."
    }

    private func channelDetail(_ item: LibraryChannelItem) -> String {
        let channel = item.channel
        return [channel.displayNumber.map { "Channel \($0)" }, channel.category, item.availability.detail]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var persistenceNotice: String? {
        if libraryStore.lastLoadFailed {
            return "\(ProductIdentity.displayName) couldn’t read part of your saved library. It kept the affected collection unchanged instead of showing the read as an empty result."
        }
        if libraryStore.lastSaveFailed {
            return "\(ProductIdentity.displayName) couldn’t save the last library change or preference. Existing durable library data was not modified."
        }
        if libraryStore.persistence == .inMemoryFallback {
            return "Favorites, Recents, and remembered player settings are unavailable until \(ProductIdentity.displayName) can reopen its library storage."
        }
        return nil
    }

    private var isLoading: Bool {
        if case .loading = model.state { return true }
        return false
    }

    private func failureCopy(_ failure: CatalogFailure) -> String {
        switch failure {
        case .authenticationUnavailable: "Sign in again to refresh channels."
        case .notEntitled: "This account is not currently entitled to listen."
        default: "The channel lineup could not be refreshed safely."
        }
    }

    private func recoveryTitle(for failure: CatalogFailure) -> String {
        switch failure {
        case .authenticationUnavailable, .notEntitled: "Sign In Again"
        case .unavailable, .collectionUnavailable, .malformedCandidate,
             .conflictingIdentity, .unsupportedResponse, .cancelled:
            "Refresh Library"
        }
    }

    private func recover(from failure: CatalogFailure) {
        switch failure {
        case .authenticationUnavailable, .notEntitled:
            if let controller {
                _ = controller.authenticationModel.retry()
            } else {
                _ = model.refresh()
            }
        case .unavailable, .collectionUnavailable, .malformedCandidate,
             .conflictingIdentity, .unsupportedResponse, .cancelled:
            _ = model.refresh()
        }
    }
}

struct FavoriteSongRow: View {
    let snapshot: FavoriteSongSnapshot
    let onCopy: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(snapshot.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let albumName = snapshot.albumName {
                    Text(albumName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(Self.sourcePresentation(for: snapshot)) · Saved \(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("Copy", action: onCopy)
                .frame(minWidth: 32, minHeight: 32)
                .help("Copy \(snapshot.copyText)")
                .accessibilityIdentifier("library.favorite-song.copy.\(snapshot.identity.storageKey)")
                .accessibilityLabel("Copy \(snapshot.copyText)")
                .accessibilityHint("Copies the saved artist and title")
            Button("Remove", role: .destructive, action: onRemove)
                .frame(minWidth: 32, minHeight: 32)
                .help("Remove from Favorite Songs")
                .accessibilityIdentifier("library.favorite-song.remove.\(snapshot.identity.storageKey)")
                .accessibilityLabel("Remove \(snapshot.copyText) from Favorite Songs")
                .accessibilityHint("Removes this saved song after local storage confirms the change")
        }
        .frame(minHeight: 48)
        .listRowBackground(LibraryPalette.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.favorite-song.row.\(snapshot.identity.storageKey)")
    }

    static func sourcePresentation(for snapshot: FavoriteSongSnapshot) -> String {
        let source = snapshot.sourceChannel
        let channelNumber = source.displayNumber.map { "Channel \($0)" }
        return [channelNumber, source.name, source.rawIdentity]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private enum LibraryFocusTarget: Hashable {
    case search
    case collection
}
