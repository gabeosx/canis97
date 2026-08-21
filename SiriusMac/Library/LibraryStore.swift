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

/// A volatile, stable-ID queue captured from the collection that explicitly
/// began playback. It deliberately knows nothing about media, sessions, or
/// catalog records; callers reconcile it with the current entitled IDs.
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
        currentEntitledIDs: [LiveChannelID],
        fullLineup: [LiveChannelID]
    ) -> LiveChannelID? {
        let entitled = Set(currentEntitledIDs)
        if capturedIDs.contains(where: { entitled.contains($0) }) {
            guard let currentIndex else { return nil }
            let indices: [Int] = switch direction {
            case .previous: Array(capturedIDs.indices.prefix(upTo: currentIndex).reversed())
            case .next: Array(capturedIDs.indices.dropFirst(currentIndex + 1))
            }
            for index in indices {
                let candidate = capturedIDs[index]
                if entitled.contains(candidate) {
                    currentID = candidate
                    return candidate
                }
            }
            return nil
        }

        let usableLineup = fullLineup.filter { entitled.contains($0) }
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

    func availability(currentEntitledIDs: [LiveChannelID], fullLineup: [LiveChannelID]) -> QueueDirectionAvailability {
        var previous = self
        var next = self
        let hasPrevious = previous.candidate(.previous, currentEntitledIDs: currentEntitledIDs, fullLineup: fullLineup) != nil
        let hasNext = next.candidate(.next, currentEntitledIDs: currentEntitledIDs, fullLineup: fullLineup) != nil
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
    static let persistedPropertyNames = ["channelID", "name", "displayNumber", "category"]

    @Attribute(.unique) var channelID: String
    var name: String?
    var displayNumber: Int?
    var category: String?

    init(snapshot: LibraryChannelSnapshot) {
        channelID = snapshot.id.rawValue
        name = snapshot.name
        displayNumber = snapshot.displayNumber
        category = snapshot.category
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

    private(set) var favorites: [LibraryChannelSnapshot] = []
    private(set) var favoriteChannelIDs: [LiveChannelID] = []
    private(set) var recents: [LibraryChannelSnapshot] = []

    init(
        modelContainer: ModelContainer = LibraryStore.makeDefaultContainer(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        modelContext = ModelContext(modelContainer)
        self.now = now
        publishFavorites()
    }

    func isFavorite(_ channelID: LiveChannelID) -> Bool {
        favoriteChannelIDs.contains(channelID)
    }

    /// Applies a desired state instead of toggling from a stale read.
    func setFavorite(_ snapshot: LibraryChannelSnapshot, isFavorite: Bool) {
        let matches = favoriteRecords().filter { $0.channelID == snapshot.id.rawValue }
        var didMutate = false

        if isFavorite {
            if let retained = matches.first {
                let changedSnapshot = retained.snapshot != snapshot
                retained.apply(snapshot)
                for duplicate in matches.dropFirst() { modelContext.delete(duplicate) }
                didMutate = changedSnapshot || matches.count > 1
            } else {
                modelContext.insert(FavoriteRecord(snapshot: snapshot))
                didMutate = true
            }
        } else {
            for record in matches { modelContext.delete(record) }
            didMutate = !matches.isEmpty
        }

        saveIfNeeded(didMutate)
        publishFavorites()
    }

    /// Records only a caller-confirmed playback transition. Catalog selection
    /// and tune intent never reach this API.
    func recordConfirmedPlayback(_ snapshot: LibraryChannelSnapshot) {
        var ordered = normalizedRecentRecords()
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
        let records = recentRecords()
        for record in records { modelContext.delete(record) }
        saveIfNeeded(!records.isEmpty)
        publishRecents()
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

    private func favoriteRecords() -> [FavoriteRecord] {
        (try? modelContext.fetch(FetchDescriptor<FavoriteRecord>())) ?? []
    }

    private func recentRecords() -> [RecentRecord] {
        (try? modelContext.fetch(FetchDescriptor<RecentRecord>())) ?? []
    }

    /// Invalid and duplicate legacy rows are removed deterministically before
    /// the next mutation; no malformed record reaches the public projection.
    private func normalizedRecentRecords() -> [RecentRecord] {
        let sorted = recentRecords().sorted { lhs, rhs in
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

    private func publishFavorites() {
        let unique = Dictionary(
            favoriteRecords().compactMap { record in record.snapshot.map { ($0.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let projected = unique.values.sorted { lhs, rhs in
            let lhsName = lhs.name ?? lhs.id.rawValue
            let rhsName = rhs.name ?? rhs.id.rawValue
            return lhsName == rhsName ? lhs.id.rawValue < rhs.id.rawValue : lhsName < rhsName
        }
        favorites = projected
        favoriteChannelIDs = projected.map(\.id)
    }

    private func publishRecents() {
        var seen = Set<LiveChannelID>()
        recents = recentRecords()
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

    private func saveIfNeeded(_ didMutate: Bool) {
        guard didMutate || modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            // Fail closed: do not expose an unsaved mutation or log storage internals.
            modelContext.rollback()
        }
    }

    private static func makeDefaultContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: FavoriteRecord.self, RecentRecord.self, PlayerPreferenceRecord.self)
        } catch {
            preconditionFailure("Unable to initialize local library storage")
        }
    }
}
