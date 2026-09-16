import Foundation
import Observation
import SiriusXMClient
import SwiftData

/// The deliberately small durable representation of a channel. It is copied
/// from the semantic catalog and never retains provider, artwork, metadata,
/// transport, session, or credential values.
struct LibraryChannelSnapshot: Equatable, Hashable {
    let id: LiveChannelID
    let name: String?
    let displayNumber: Int?
    let category: String?

    init(id: LiveChannelID, name: String?, displayNumber: Int?, category: String?) {
        self.id = id
        self.name = Self.cleaned(name)
        self.displayNumber = displayNumber
        self.category = Self.cleaned(category)
    }

    init(_ channel: LiveChannel) {
        self.init(id: channel.id, name: channel.name, displayNumber: channel.displayNumber, category: channel.category)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The only queue commands the application exposes for live radio.
enum QueueDirection: Equatable {
    case previous
    case next
}

/// The available directions are a semantic projection, never media authority.
enum QueueDirectionAvailability: Equatable {
    case none
    case previous
    case next
    case both
}

/// Describes whether small, non-secret library state survives a relaunch.
/// A durable-store failure must not prevent listening; the app deliberately
/// degrades to an in-memory library until the next launch can reopen storage.
enum LibraryStorePersistence: Equatable {
    case durable
    case inMemoryFallback
}

enum FavoriteMoveDirection: Equatable {
    case earlier
    case later
}

/// A volatile, stable-ID queue captured from the collection that explicitly
/// began playback. It deliberately knows nothing about media, sessions, or
/// catalog records; callers reconcile it with the current available guide IDs.
struct PlaybackQueue: Equatable {
    let capturedIDs: [LiveChannelID]
    private(set) var currentID: LiveChannelID?

    init(originIDs: [LiveChannelID], currentID: LiveChannelID?) {
        capturedIDs = originIDs
        self.currentID = currentID
    }

    var currentIndex: Int? {
        guard let currentID else { return nil }
        return capturedIDs.firstIndex(of: currentID)
    }

    mutating func candidate(
        _ direction: QueueDirection,
        currentAvailableIDs: [LiveChannelID],
        fullLineup: [LiveChannelID]
    ) -> LiveChannelID? {
        let available = Set(currentAvailableIDs)
        if capturedIDs.contains(where: { available.contains($0) }) {
            guard let currentIndex else { return nil }
            let indices: [Int] = switch direction {
            case .previous: Array(capturedIDs.indices.prefix(upTo: currentIndex).reversed())
            case .next: Array(capturedIDs.indices.dropFirst(currentIndex + 1))
            }
            for index in indices {
                let candidate = capturedIDs[index]
                if available.contains(candidate) {
                    currentID = candidate
                    return candidate
                }
            }
            return nil
        }

        let usableLineup = fullLineup.filter { available.contains($0) }
        guard !usableLineup.isEmpty else { return nil }
        let candidate: LiveChannelID?
        if let currentID, let fullLineupIndex = usableLineup.firstIndex(of: currentID) {
            switch direction {
            case .previous:
                candidate = fullLineupIndex > 0 ? usableLineup[fullLineupIndex - 1] : nil
            case .next:
                candidate = fullLineupIndex + 1 < usableLineup.count ? usableLineup[fullLineupIndex + 1] : nil
            }
        } else {
            candidate = direction == .next ? usableLineup.first : usableLineup.last
        }
        guard let candidate else { return nil }
        currentID = candidate
        return candidate
    }

    func availability(currentAvailableIDs: [LiveChannelID], fullLineup: [LiveChannelID]) -> QueueDirectionAvailability {
        var previous = self
        var next = self
        let hasPrevious = previous.candidate(.previous, currentAvailableIDs: currentAvailableIDs, fullLineup: fullLineup) != nil
        let hasNext = next.candidate(.next, currentAvailableIDs: currentAvailableIDs, fullLineup: fullLineup) != nil
        return switch (hasPrevious, hasNext) {
        case (false, false): .none
        case (true, false): .previous
        case (false, true): .next
        case (true, true): .both
        }
    }
}

/// A generation-tagged, semantic request for the library to reveal a channel.
struct LibraryRevealRequest: Equatable {
    let channelID: LiveChannelID
    let generation: Int
}

@Model
final class FavoriteRecord {
    static let persistedPropertyNames = ["channelID", "name", "displayNumber", "category", "rank"]

    @Attribute(.unique) var channelID: String
    var name: String?
    var displayNumber: Int?
    var category: String?
    var rank: Int = 0

    init(snapshot: LibraryChannelSnapshot, rank: Int = 0) {
        channelID = snapshot.id.rawValue
        name = snapshot.name
        displayNumber = snapshot.displayNumber
        category = snapshot.category
        self.rank = rank
    }

    func apply(_ snapshot: LibraryChannelSnapshot) {
        name = snapshot.name
        displayNumber = snapshot.displayNumber
        category = snapshot.category
    }

    var snapshot: LibraryChannelSnapshot? {
        guard !channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return LibraryChannelSnapshot(id: LiveChannelID(channelID), name: name, displayNumber: displayNumber, category: category)
    }
}

/// One provider-neutral listening-history item. It contains display metadata
/// and observation times only; it can neither identify nor authorize media.
struct ListeningHistoryEntry: Identifiable, Equatable {
    let id: String
    let channel: LibraryChannelSnapshot
    let title: String
    let artist: String?
    let kind: LiveNowContentKind
    let programStartedAt: Date
    let firstHeardAt: Date
    let lastHeardAt: Date
    let heardDuration: TimeInterval

    var copyText: String {
        let program = artist.map { "\($0) — \(title)" } ?? title
        let channelName = channel.name ?? channel.displayNumber.map { "Channel \($0)" } ?? "Saved channel"
        return "\(program) on \(channelName)"
    }
}

@Model
final class ListeningHistoryRecord {
    static let persistedPropertyNames = [
        "storageKey", "channelID", "channelName", "channelDisplayNumber", "channelCategory",
        "title", "artist", "kind", "programStartedAt", "firstHeardAt", "lastHeardAt", "heardDuration",
    ]

    @Attribute(.unique) var storageKey: String
    var channelID: String
    var channelName: String?
    var channelDisplayNumber: Int?
    var channelCategory: String?
    var title: String
    var artist: String?
    var kind: String
    var programStartedAt: Date
    var firstHeardAt: Date
    var lastHeardAt: Date
    var heardDuration: TimeInterval

    init(channel: LibraryChannelSnapshot, program: LiveNowProgram, heardAt: Date, duration: TimeInterval) {
        storageKey = Self.key(channelID: channel.id, program: program)
        channelID = channel.id.rawValue
        channelName = channel.name
        channelDisplayNumber = channel.displayNumber
        channelCategory = channel.category
        title = program.title
        artist = program.artist
        kind = program.kind == .show ? "show" : "item"
        programStartedAt = program.startedAt
        firstHeardAt = heardAt
        lastHeardAt = heardAt
        heardDuration = max(0, duration)
    }

    func record(channel: LibraryChannelSnapshot, heardAt: Date, duration: TimeInterval) {
        channelName = channel.name
        channelDisplayNumber = channel.displayNumber
        channelCategory = channel.category
        lastHeardAt = max(lastHeardAt, heardAt)
        heardDuration += max(0, duration)
    }

    var entry: ListeningHistoryEntry? {
        guard !channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let semanticKind = kind == "show" ? LiveNowContentKind.show : kind == "item" ? .item : nil
        else { return nil }
        return ListeningHistoryEntry(
            id: storageKey,
            channel: LibraryChannelSnapshot(
                id: LiveChannelID(channelID),
                name: channelName,
                displayNumber: channelDisplayNumber,
                category: channelCategory
            ),
            title: title,
            artist: artist,
            kind: semanticKind,
            programStartedAt: programStartedAt,
            firstHeardAt: firstHeardAt,
            lastHeardAt: lastHeardAt,
            heardDuration: heardDuration
        )
    }

    static func key(channelID: LiveChannelID, program: LiveNowProgram) -> String {
        let parts = [
            channelID.rawValue,
            program.kind == .show ? "show" : "item",
            String(program.startedAt.timeIntervalSinceReferenceDate.bitPattern),
            program.title,
            program.artist ?? "",
        ]
        return parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
}

/// A separate persisted domain from channel favorites. Its exact allow-list is
/// intentionally small so provider and playback details cannot enter SwiftData.
@Model
final class FavoriteSongRecord {
    static let persistedPropertyNames = [
        "storageKey", "normalizedTitle", "normalizedArtist", "title", "artist",
        "albumName", "sourceChannelID", "sourceChannelName",
        "sourceChannelDisplayNumber", "savedAt",
    ]

    @Attribute(.unique) var storageKey: String
    var normalizedTitle: String
    var normalizedArtist: String
    var title: String
    var artist: String
    var albumName: String?
    var sourceChannelID: String
    var sourceChannelName: String?
    var sourceChannelDisplayNumber: Int?
    var savedAt: Date

    init(snapshot: FavoriteSongSnapshot) {
        storageKey = snapshot.identity.storageKey
        normalizedTitle = snapshot.identity.normalizedTitle
        normalizedArtist = snapshot.identity.normalizedArtist
        title = snapshot.title
        artist = snapshot.artist
        albumName = snapshot.albumName
        sourceChannelID = snapshot.sourceChannel.rawIdentity
        sourceChannelName = snapshot.sourceChannel.name
        sourceChannelDisplayNumber = snapshot.sourceChannel.displayNumber
        savedAt = snapshot.savedAt
    }

    func applyPresentation(from snapshot: FavoriteSongSnapshot) {
        title = snapshot.title
        artist = snapshot.artist
        albumName = snapshot.albumName
        sourceChannelID = snapshot.sourceChannel.rawIdentity
        sourceChannelName = snapshot.sourceChannel.name
        sourceChannelDisplayNumber = snapshot.sourceChannel.displayNumber
    }

    var snapshot: FavoriteSongSnapshot? {
        guard let sourceChannel = FavoriteSongSourceChannel(
            rawIdentity: sourceChannelID,
            name: sourceChannelName,
            displayNumber: sourceChannelDisplayNumber
        ), let snapshot = FavoriteSongSnapshot(
            title: title,
            artist: artist,
            albumName: albumName,
            sourceChannel: sourceChannel,
            savedAt: savedAt
        ), snapshot.identity.storageKey == storageKey,
           snapshot.identity.normalizedTitle == normalizedTitle,
           snapshot.identity.normalizedArtist == normalizedArtist
        else { return nil }
        return snapshot
    }
}

@Model
final class RecentRecord {
    static let persistedPropertyNames = ["channelID", "name", "displayNumber", "category", "rank", "confirmedAt"]

    @Attribute(.unique) var channelID: String
    var name: String?
    var displayNumber: Int?
    var category: String?
    var rank: Int
    var confirmedAt: Date

    init(snapshot: LibraryChannelSnapshot, rank: Int, confirmedAt: Date) {
        channelID = snapshot.id.rawValue
        name = snapshot.name
        displayNumber = snapshot.displayNumber
        category = snapshot.category
        self.rank = rank
        self.confirmedAt = confirmedAt
    }

    func apply(_ snapshot: LibraryChannelSnapshot, rank: Int, confirmedAt: Date) {
        name = snapshot.name
        displayNumber = snapshot.displayNumber
        category = snapshot.category
        self.rank = rank
        self.confirmedAt = confirmedAt
    }

    var snapshot: LibraryChannelSnapshot? {
        guard !channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return LibraryChannelSnapshot(id: LiveChannelID(channelID), name: name, displayNumber: displayNumber, category: category)
    }
}

/// Fixed fields prevent this store from becoming a generic persistence channel.
@Model
final class PlayerPreferenceRecord {
    static let persistedPropertyNames = ["selectedTab", "compactWindowAlwaysOnTop", "compactFrameAutosaveName", "libraryFrameAutosaveName"]

    var selectedTab: String
    var compactWindowAlwaysOnTop: Bool
    var compactFrameAutosaveName: String
    var libraryFrameAutosaveName: String

    init(
        selectedTab: String = "channels",
        compactWindowAlwaysOnTop: Bool = false,
        compactFrameAutosaveName: String = "SiriusMacCompactWindow",
        libraryFrameAutosaveName: String = "SiriusMacLibraryWindow"
    ) {
        self.selectedTab = selectedTab
        self.compactWindowAlwaysOnTop = compactWindowAlwaysOnTop
        self.compactFrameAutosaveName = compactFrameAutosaveName
        self.libraryFrameAutosaveName = libraryFrameAutosaveName
    }
}

/// The sole app-owned facade for small, non-secret listening-library state.
/// The main actor serializes all mutations through this one ModelContext.
@MainActor
@Observable
final class LibraryStore {
    private let modelContext: ModelContext
    private let now: @Sendable () -> Date

    private(set) var persistence: LibraryStorePersistence

    private(set) var favorites: [LibraryChannelSnapshot] = []
    private(set) var favoriteChannelIDs: [LiveChannelID] = []
    private(set) var favoriteSongs: [FavoriteSongSnapshot] = []
    private(set) var recents: [LibraryChannelSnapshot] = []
    private(set) var listeningHistory: [ListeningHistoryEntry] = []
    private(set) var selectedLibraryTab = "channels"
    private(set) var alwaysOnTop = false
    private(set) var lastLoadFailed = false
    private(set) var lastSaveFailed = false

    init(
        modelContainer: ModelContainer? = nil,
        persistence injectedPersistence: LibraryStorePersistence? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let setup = modelContainer.map { (container: $0, persistence: injectedPersistence ?? LibraryStorePersistence.durable) }
            ?? Self.makeDefaultContainer()
        modelContext = ModelContext(setup.container)
        persistence = setup.persistence
        self.now = now
        publishFavorites()
        publishFavoriteSongs()
        publishRecents()
        publishListeningHistory()
        publishPlayerPreferences()
    }

    func isFavorite(_ channelID: LiveChannelID) -> Bool {
        favoriteChannelIDs.contains(channelID)
    }

    /// Applies a desired state instead of toggling from a stale read.
    func setFavorite(_ snapshot: LibraryChannelSnapshot, isFavorite: Bool) {
        guard persistence == .durable else {
            // Never present an ephemeral favorite as saved. Listening remains
            // available, while the library banner explains the storage issue.
            lastSaveFailed = true
            return
        }
        guard let records = favoriteRecords() else { return }
        let matches = records.filter { $0.channelID == snapshot.id.rawValue }
        var didMutate = false

        if isFavorite {
            if let retained = matches.first {
                let changedSnapshot = retained.snapshot != snapshot
                retained.apply(snapshot)
                for duplicate in matches.dropFirst() { modelContext.delete(duplicate) }
                didMutate = changedSnapshot || matches.count > 1
            } else {
                let nextRank = (records.map(\.rank).max() ?? -1) + 1
                modelContext.insert(FavoriteRecord(snapshot: snapshot, rank: nextRank))
                didMutate = true
            }
        } else {
            for record in matches { modelContext.delete(record) }
            didMutate = !matches.isEmpty
        }

        saveIfNeeded(didMutate)
        publishFavorites()
    }

    func canMoveFavorite(_ channelID: LiveChannelID, direction: FavoriteMoveDirection) -> Bool {
        guard let index = favoriteChannelIDs.firstIndex(of: channelID) else { return false }
        return direction == .earlier ? index > 0 : index + 1 < favoriteChannelIDs.count
    }

    @discardableResult
    func moveFavorite(_ channelID: LiveChannelID, direction: FavoriteMoveDirection) -> Bool {
        guard persistence == .durable,
              var records = normalizedFavoriteRecords(),
              let index = records.firstIndex(where: { $0.channelID == channelID.rawValue })
        else { return false }
        let target = direction == .earlier ? index - 1 : index + 1
        guard records.indices.contains(target) else { return false }
        records.swapAt(index, target)
        for (rank, record) in records.enumerated() { record.rank = rank }
        guard saveIfNeeded(true) else { return false }
        publishFavorites()
        return true
    }

    func isFavoriteSong(_ snapshot: FavoriteSongSnapshot) -> Bool {
        favoriteSongs.contains { $0.identity == snapshot.identity }
    }

    /// Applies a requested durable state. A failed save never changes the
    /// published song list or reports success to the session controller.
    @discardableResult
    func setSongFavorite(_ snapshot: FavoriteSongSnapshot, isFavorite: Bool) -> FavoriteSongMutationResult {
        guard persistence == .durable else {
            lastSaveFailed = true
            return .failed
        }
        guard let records = favoriteSongRecords() else { return .failed }
        let matches = records.filter { $0.storageKey == snapshot.identity.storageKey }

        var didMutate = false
        if isFavorite {
            if let retained = matches.first {
                let before = retained.snapshot
                retained.applyPresentation(from: snapshot)
                for duplicate in matches.dropFirst() { modelContext.delete(duplicate) }
                didMutate = before?.title != snapshot.title ||
                    before?.artist != snapshot.artist ||
                    before?.albumName != snapshot.albumName ||
                    before?.sourceChannel != snapshot.sourceChannel ||
                    matches.count > 1
            } else {
                modelContext.insert(FavoriteSongRecord(snapshot: snapshot))
                didMutate = true
            }
        } else {
            for record in matches { modelContext.delete(record) }
            didMutate = !matches.isEmpty
        }

        guard saveIfNeeded(didMutate) else { return .failed }
        publishFavoriteSongs()
        return isFavorite ? .saved : .removed
    }

    /// Records only a caller-confirmed playback transition. Catalog selection
    /// and tune intent never reach this API.
    func recordConfirmedPlayback(_ snapshot: LibraryChannelSnapshot) {
        guard persistence == .durable else {
            lastSaveFailed = true
            return
        }
        guard var ordered = normalizedRecentRecords() else { return }
        let matchingIndex = ordered.firstIndex { $0.channelID == snapshot.id.rawValue }
        var didMutate = false

        if let matchingIndex {
            let record = ordered.remove(at: matchingIndex)
            let isAlreadyCurrent = matchingIndex == 0 && record.snapshot == snapshot && record.rank == 0
            ordered.insert(record, at: 0)
            if !isAlreadyCurrent {
                record.apply(snapshot, rank: 0, confirmedAt: now())
                didMutate = true
            }
        } else {
            let record = RecentRecord(snapshot: snapshot, rank: 0, confirmedAt: now())
            modelContext.insert(record)
            ordered.insert(record, at: 0)
            didMutate = true
        }

        for (index, record) in ordered.enumerated() {
            guard index < 50 else {
                modelContext.delete(record)
                didMutate = true
                continue
            }
            if record.rank != index {
                record.rank = index
                didMutate = true
            }
        }

        saveIfNeeded(didMutate)
        publishRecents()
    }

    func clearRecents() {
        guard persistence == .durable else {
            lastSaveFailed = true
            return
        }
        guard let records = recentRecords() else { return }
        for record in records { modelContext.delete(record) }
        saveIfNeeded(!records.isEmpty)
        publishRecents()
    }

    /// Records one locally observed semantic program. Repeated observations of
    /// the same channel/program identity accumulate instead of creating noise.
    func recordListeningHistory(
        channel: LibraryChannelSnapshot,
        program: LiveNowProgram,
        heardAt: Date,
        duration: TimeInterval
    ) {
        guard persistence == .durable else {
            lastSaveFailed = true
            return
        }
        guard let records = listeningHistoryRecords() else { return }
        let key = ListeningHistoryRecord.key(channelID: channel.id, program: program)
        if let record = records.first(where: { $0.storageKey == key }) {
            record.record(channel: channel, heardAt: heardAt, duration: duration)
        } else {
            modelContext.insert(ListeningHistoryRecord(
                channel: channel,
                program: program,
                heardAt: heardAt,
                duration: duration
            ))
        }
        guard let allRecords = listeningHistoryRecords() else { return }
        let ordered = allRecords.sorted { $0.lastHeardAt > $1.lastHeardAt }
        for record in ordered.dropFirst(500) { modelContext.delete(record) }
        guard saveIfNeeded(true) else { return }
        publishListeningHistory()
    }

    func clearListeningHistory() {
        guard persistence == .durable else {
            lastSaveFailed = true
            return
        }
        guard let records = listeningHistoryRecords() else { return }
        for record in records { modelContext.delete(record) }
        guard saveIfNeeded(!records.isEmpty) else { return }
        publishListeningHistory()
    }

    func setSelectedLibraryTab(_ tab: String) {
        guard persistence == .durable else {
            selectedLibraryTab = tab
            lastSaveFailed = true
            return
        }
        guard let records = playerPreferenceRecords() else { return }
        let record = records.first ?? PlayerPreferenceRecord()
        if records.isEmpty { modelContext.insert(record) }
        guard record.selectedTab != tab else { return }
        record.selectedTab = tab
        saveIfNeeded(true)
        publishPlayerPreferences()
    }

    /// Persists a desired compact-window level without exposing any playback,
    /// session, or resource state to the preference boundary.
    func setAlwaysOnTop(_ desiredState: Bool) {
        guard persistence == .durable else {
            alwaysOnTop = desiredState
            lastSaveFailed = true
            return
        }
        guard let records = playerPreferenceRecords() else { return }
        let record = records.first ?? PlayerPreferenceRecord()
        if records.isEmpty { modelContext.insert(record) }
        guard record.compactWindowAlwaysOnTop != desiredState else {
            publishPlayerPreferences()
            return
        }
        record.compactWindowAlwaysOnTop = desiredState
        saveIfNeeded(true)
        publishPlayerPreferences()
    }

    /// Test-only inspection of the persisted stable-identity boundary.
    func favoriteRecordCount(for channelID: LiveChannelID) throws -> Int {
        try modelContext.fetch(FetchDescriptor<FavoriteRecord>())
            .filter { $0.channelID == channelID.rawValue }
            .count
    }

    /// Test-only inspection of the persisted stable-identity boundary.
    func recentRecordCount(for channelID: LiveChannelID) throws -> Int {
        try modelContext.fetch(FetchDescriptor<RecentRecord>())
            .filter { $0.channelID == channelID.rawValue }
            .count
    }

    /// Test-only inspection of the song-specific stable identity boundary.
    func favoriteSongRecordCount(for identity: FavoriteSongIdentity) throws -> Int {
        try modelContext.fetch(FetchDescriptor<FavoriteSongRecord>())
            .filter { $0.storageKey == identity.storageKey }
            .count
    }

    private func favoriteRecords() -> [FavoriteRecord]? {
        do {
            return try modelContext.fetch(FetchDescriptor<FavoriteRecord>())
        } catch {
            lastLoadFailed = true
            return nil
        }
    }

    private func recentRecords() -> [RecentRecord]? {
        do {
            return try modelContext.fetch(FetchDescriptor<RecentRecord>())
        } catch {
            lastLoadFailed = true
            return nil
        }
    }

    private func favoriteSongRecords() -> [FavoriteSongRecord]? {
        do {
            return try modelContext.fetch(FetchDescriptor<FavoriteSongRecord>())
        } catch {
            lastLoadFailed = true
            return nil
        }
    }

    private func listeningHistoryRecords() -> [ListeningHistoryRecord]? {
        do {
            return try modelContext.fetch(FetchDescriptor<ListeningHistoryRecord>())
        } catch {
            lastLoadFailed = true
            return nil
        }
    }

    private func playerPreferenceRecords() -> [PlayerPreferenceRecord]? {
        do {
            return try modelContext.fetch(FetchDescriptor<PlayerPreferenceRecord>())
        } catch {
            lastLoadFailed = true
            return nil
        }
    }

    private func publishPlayerPreferences() {
        guard let records = playerPreferenceRecords() else { return }
        let preferences = records.first
        selectedLibraryTab = preferences?.selectedTab ?? "channels"
        alwaysOnTop = preferences?.compactWindowAlwaysOnTop ?? false
    }

    /// Invalid and duplicate legacy rows are removed deterministically before
    /// the next mutation; no malformed record reaches the public projection.
    private func normalizedRecentRecords() -> [RecentRecord]? {
        guard let records = recentRecords() else { return nil }
        let sorted = records.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.confirmedAt != rhs.confirmedAt { return lhs.confirmedAt > rhs.confirmedAt }
            return lhs.channelID < rhs.channelID
        }
        var seen = Set<LiveChannelID>()
        return sorted.compactMap { record in
            guard let snapshot = record.snapshot, seen.insert(snapshot.id).inserted else {
                modelContext.delete(record)
                return nil
            }
            return record
        }
    }

    private func normalizedFavoriteRecords() -> [FavoriteRecord]? {
        guard let records = favoriteRecords() else { return nil }
        var seen = Set<LiveChannelID>()
        return records
            .filter { $0.snapshot != nil }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                let left = lhs.snapshot?.name ?? lhs.channelID
                let right = rhs.snapshot?.name ?? rhs.channelID
                return left == right ? lhs.channelID < rhs.channelID : left.localizedStandardCompare(right) == .orderedAscending
            }
            .filter { record in
                guard let id = record.snapshot?.id else { return false }
                if seen.insert(id).inserted { return true }
                modelContext.delete(record)
                return false
            }
    }

    private func publishFavorites() {
        guard let records = normalizedFavoriteRecords() else { return }
        let projected = records.compactMap(\.snapshot)
        favorites = projected
        favoriteChannelIDs = projected.map(\.id)
    }

    private func publishFavoriteSongs() {
        guard let records = favoriteSongRecords() else { return }
        var seen = Set<FavoriteSongIdentity>()
        favoriteSongs = records
            .compactMap(\.snapshot)
            .sorted { lhs, rhs in
                if lhs.savedAt != rhs.savedAt { return lhs.savedAt > rhs.savedAt }
                if lhs.identity.normalizedArtist != rhs.identity.normalizedArtist {
                    return lhs.identity.normalizedArtist < rhs.identity.normalizedArtist
                }
                return lhs.identity.normalizedTitle < rhs.identity.normalizedTitle
            }
            .filter { seen.insert($0.identity).inserted }
    }

    private func publishRecents() {
        guard let records = recentRecords() else { return }
        var seen = Set<LiveChannelID>()
        recents = records
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.confirmedAt != rhs.confirmedAt { return lhs.confirmedAt > rhs.confirmedAt }
                return lhs.channelID < rhs.channelID
            }
            .compactMap { record in
                guard let snapshot = record.snapshot, seen.insert(snapshot.id).inserted else { return nil }
                return snapshot
            }
            .prefix(50)
            .map { $0 }
    }

    private func publishListeningHistory() {
        guard let records = listeningHistoryRecords() else { return }
        listeningHistory = records
            .compactMap(\.entry)
            .sorted { lhs, rhs in
                if lhs.lastHeardAt != rhs.lastHeardAt { return lhs.lastHeardAt > rhs.lastHeardAt }
                return lhs.id < rhs.id
            }
            .prefix(500)
            .map { $0 }
    }

    @discardableResult
    private func saveIfNeeded(_ didMutate: Bool) -> Bool {
        guard didMutate || modelContext.hasChanges else { return true }
        do {
            try modelContext.save()
            lastSaveFailed = false
            return true
        } catch {
            // Fail closed: do not expose an unsaved mutation or log storage internals.
            modelContext.rollback()
            lastSaveFailed = true
            return false
        }
    }

    static func makeDefaultContainer(
        persistentContainer: () throws -> ModelContainer = {
            try makeAppSpecificPersistentContainer()
        },
        fallbackContainer: () throws -> ModelContainer = {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: FavoriteRecord.self,
                FavoriteSongRecord.self,
                RecentRecord.self,
                ListeningHistoryRecord.self,
                PlayerPreferenceRecord.self,
                configurations: configuration
            )
        }
    ) -> (container: ModelContainer, persistence: LibraryStorePersistence) {
        do {
            return (try persistentContainer(), .durable)
        } catch {
            // The fallback is intentionally isolated from the on-disk store:
            // a corrupt or migration-incompatible local database remains
            // recoverable and cannot block authentication or playback.
            return (try! fallbackContainer(), .inMemoryFallback)
        }
    }

    /// Canis97 owns an explicit store instead of SwiftData's process-wide
    /// `Application Support/default.store`, which can collide with another
    /// model or an earlier development build and force an in-memory fallback.
    private static func makeAppSpecificPersistentContainer() throws -> ModelContainer {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent(
            ProductIdentity.applicationSupportDirectoryName,
            isDirectory: true
        )
        let legacyDirectory = applicationSupport.appendingPathComponent(
            ProductIdentity.Legacy.applicationSupportDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try makePersistentContainer(
            at: directory.appendingPathComponent(ProductIdentity.NonSecretStorage.libraryStoreFileName),
            migratingLegacyStoreAt: legacyDirectory.appendingPathComponent(
                ProductIdentity.Legacy.libraryStoreFileName
            ),
            fileManager: fileManager
        )
    }

    /// Internal for focused persistence tests. Migration is semantic and
    /// idempotent: opaque SQLite files are never moved, deleted, or adopted.
    static func makePersistentContainer(
        at storeURL: URL,
        migratingLegacyStoreAt legacyStoreURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let destinationAlreadyExists = fileManager.fileExists(atPath: storeURL.path)
        let container = try modelContainer(at: storeURL, name: "Canis97Library")
        let markerURL = storeURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ProductIdentity.NonSecretStorage.migrationMarkerDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent(ProductIdentity.NonSecretStorage.libraryMigrationMarkerName)

        guard !fileManager.fileExists(atPath: markerURL.path) else { return container }
        guard !destinationAlreadyExists else {
            try writeMigrationMarker(at: markerURL, fileManager: fileManager)
            return container
        }
        if let legacyStoreURL,
           legacyStoreURL.standardizedFileURL != storeURL.standardizedFileURL,
           fileManager.fileExists(atPath: legacyStoreURL.path) {
            try migrateLegacyRecords(from: legacyStoreURL, into: container)
            try verifyLegacyRecords(from: legacyStoreURL, in: container)
            try writeMigrationMarker(at: markerURL, fileManager: fileManager)
        }
        return container
    }

    private static func modelContainer(at url: URL, name: String) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            name,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: FavoriteRecord.self,
            FavoriteSongRecord.self,
            RecentRecord.self,
            ListeningHistoryRecord.self,
            PlayerPreferenceRecord.self,
            configurations: configuration
        )
    }

    private static func migrateLegacyRecords(
        from legacyStoreURL: URL,
        into destinationContainer: ModelContainer
    ) throws {
        let sourceContainer = try modelContainer(at: legacyStoreURL, name: "SiriusMacLegacyLibrary")
        let source = ModelContext(sourceContainer)
        let destination = ModelContext(destinationContainer)

        let existingFavoriteIDs = Set(
            try destination.fetch(FetchDescriptor<FavoriteRecord>()).map(\.channelID)
        )
        for record in try source.fetch(FetchDescriptor<FavoriteRecord>()) {
            guard let snapshot = record.snapshot,
                  !existingFavoriteIDs.contains(snapshot.id.rawValue)
            else { continue }
            destination.insert(FavoriteRecord(snapshot: snapshot))
        }

        let existingRecentIDs = Set(
            try destination.fetch(FetchDescriptor<RecentRecord>()).map(\.channelID)
        )
        for record in try source.fetch(FetchDescriptor<RecentRecord>()) {
            guard let snapshot = record.snapshot,
                  !existingRecentIDs.contains(snapshot.id.rawValue)
            else { continue }
            destination.insert(RecentRecord(
                snapshot: snapshot,
                rank: record.rank,
                confirmedAt: record.confirmedAt
            ))
        }

        if try destination.fetch(FetchDescriptor<PlayerPreferenceRecord>()).isEmpty,
           let preferences = try source.fetch(FetchDescriptor<PlayerPreferenceRecord>()).first {
            destination.insert(PlayerPreferenceRecord(
                selectedTab: preferences.selectedTab,
                compactWindowAlwaysOnTop: preferences.compactWindowAlwaysOnTop,
                compactFrameAutosaveName: preferences.compactFrameAutosaveName,
                libraryFrameAutosaveName: preferences.libraryFrameAutosaveName
            ))
        }

        if destination.hasChanges {
            try destination.save()
        }
    }

    private static func verifyLegacyRecords(
        from legacyStoreURL: URL,
        in destinationContainer: ModelContainer
    ) throws {
        let sourceContainer = try modelContainer(at: legacyStoreURL, name: "SiriusMacLegacyLibrary")
        let source = ModelContext(sourceContainer)
        let destination = ModelContext(destinationContainer)

        let destinationFavoriteIDs = Set(
            try destination.fetch(FetchDescriptor<FavoriteRecord>()).compactMap(\.snapshot).map(\.id.rawValue)
        )
        let legacyFavoriteIDs = Set(
            try source.fetch(FetchDescriptor<FavoriteRecord>()).compactMap(\.snapshot).map(\.id.rawValue)
        )
        guard legacyFavoriteIDs.isSubset(of: destinationFavoriteIDs) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let destinationRecentIDs = Set(
            try destination.fetch(FetchDescriptor<RecentRecord>()).compactMap(\.snapshot).map(\.id.rawValue)
        )
        let legacyRecentIDs = Set(
            try source.fetch(FetchDescriptor<RecentRecord>()).compactMap(\.snapshot).map(\.id.rawValue)
        )
        guard legacyRecentIDs.isSubset(of: destinationRecentIDs) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let legacyPreferences = try source.fetch(FetchDescriptor<PlayerPreferenceRecord>()).first
        let destinationPreferences = try destination.fetch(FetchDescriptor<PlayerPreferenceRecord>()).first
        guard legacyPreferences == nil || destinationPreferences != nil else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func writeMigrationMarker(at url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url, options: .atomic)
    }

}
