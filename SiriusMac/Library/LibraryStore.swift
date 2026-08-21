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
                retained.apply(snapshot)
                for duplicate in matches.dropFirst() { modelContext.delete(duplicate) }
                didMutate = matches.count > 1
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

    /// Test-only inspection of the persisted stable-identity boundary.
    func favoriteRecordCount(for channelID: LiveChannelID) throws -> Int {
        try modelContext.fetch(FetchDescriptor<FavoriteRecord>())
            .filter { $0.channelID == channelID.rawValue }
            .count
    }

    private func favoriteRecords() -> [FavoriteRecord] {
        (try? modelContext.fetch(FetchDescriptor<FavoriteRecord>())) ?? []
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

    private func saveIfNeeded(_ didMutate: Bool) {
        guard didMutate else { return }
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
