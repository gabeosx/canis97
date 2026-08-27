import SwiftData
import XCTest
@testable import SiriusMac
import SiriusXMClient

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testPersistentContainerFailureDoesNotPretendEphemeralFavoritesAreSaved() throws {
        enum PersistentContainerError: Error { case unavailable }
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let fallback = try ModelContainer(
            for: FavoriteRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: configuration
        )

        let setup = LibraryStore.makeDefaultContainer(
            persistentContainer: { throw PersistentContainerError.unavailable },
            fallbackContainer: { fallback }
        )
        let store = LibraryStore(modelContainer: setup.container, persistence: setup.persistence)
        let snapshot = channel("fixture-fallback")

        XCTAssertEqual(setup.persistence, .inMemoryFallback)
        store.setFavorite(snapshot, isFavorite: true)
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertTrue(store.lastSaveFailed)

        store.setSelectedLibraryTab("favorites")
        store.setAlwaysOnTop(true)
        XCTAssertEqual(store.selectedLibraryTab, "favorites")
        XCTAssertTrue(store.alwaysOnTop)
    }

    func testAppSpecificStoreMigratesLegacyRowsExactlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiriusMacLibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("default.store")
        let destinationURL = directory.appendingPathComponent("Sirius Mac/Library.store")

        let legacyContainer = try LibraryStore.makePersistentContainer(at: legacyURL)
        let legacyStore = LibraryStore(modelContainer: legacyContainer)
        let snapshot = channel("fixture-legacy-favorite")
        legacyStore.setFavorite(snapshot, isFavorite: true)

        let migratedContainer = try LibraryStore.makePersistentContainer(
            at: destinationURL,
            migratingLegacyStoreAt: legacyURL
        )
        let migratedStore = LibraryStore(modelContainer: migratedContainer)
        XCTAssertEqual(migratedStore.favorites, [snapshot])

        migratedStore.setFavorite(snapshot, isFavorite: false)
        let reopenedContainer = try LibraryStore.makePersistentContainer(
            at: destinationURL,
            migratingLegacyStoreAt: legacyURL
        )
        let reopenedStore = LibraryStore(modelContainer: reopenedContainer)
        XCTAssertTrue(reopenedStore.favorites.isEmpty)
    }

    func testSettingFavoriteTrueTwiceKeepsOneStableRecord() throws {
        let store = try makeStore()
        let snapshot = channel("fixture-favorite")

        store.setFavorite(snapshot, isFavorite: true)
        store.setFavorite(snapshot, isFavorite: true)

        XCTAssertEqual(store.favoriteChannelIDs, [snapshot.id])
        XCTAssertEqual(store.favorites, [snapshot])
        XCTAssertEqual(try store.favoriteRecordCount(for: snapshot.id), 1)
    }

    func testSettingFavoriteFalseTwiceRemovesTheProjection() throws {
        let store = try makeStore()
        let snapshot = channel("fixture-remove")
        store.setFavorite(snapshot, isFavorite: true)

        store.setFavorite(snapshot, isFavorite: false)
        store.setFavorite(snapshot, isFavorite: false)

        XCTAssertFalse(store.isFavorite(snapshot.id))
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertEqual(try store.favoriteRecordCount(for: snapshot.id), 0)
    }

    func testInterleavedDesiredFavoriteCommandsEndAtLastStateWithoutDuplicates() async throws {
        let store = try makeStore()
        let snapshot = channel("fixture-interleaved")

        await MainActor.run {
            store.setFavorite(snapshot, isFavorite: true)
            store.setFavorite(snapshot, isFavorite: false)
            store.setFavorite(snapshot, isFavorite: true)
        }

        XCTAssertTrue(store.isFavorite(snapshot.id))
        XCTAssertEqual(try store.favoriteRecordCount(for: snapshot.id), 1)
    }

    func testRecentsRemainEmptyUntilAConfirmedPlaybackIsRecorded() throws {
        let store = try makeStore()

        XCTAssertTrue(store.recents.isEmpty)

        store.recordConfirmedPlayback(channel("fixture-confirmed"))

        XCTAssertEqual(store.recents.map(\.id), [LiveChannelID("fixture-confirmed")])
    }

    func testPersistedRecentsAreProjectedImmediatelyWhenStoreReopens() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FavoriteRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: configuration
        )
        let firstStore = LibraryStore(modelContainer: container, now: { Date(timeIntervalSince1970: 1) })
        firstStore.recordConfirmedPlayback(channel("fixture-persisted-recent"))

        let reopenedStore = LibraryStore(modelContainer: container)

        XCTAssertEqual(
            reopenedStore.recents.map(\.id),
            [LiveChannelID("fixture-persisted-recent")]
        )
    }

    func testReplayingAnExistingRecentMovesOnlyThatItemToRankZero() throws {
        let store = try makeStore()
        let first = channel("fixture-first")
        let second = channel("fixture-second")
        let third = channel("fixture-third")
        store.recordConfirmedPlayback(first)
        store.recordConfirmedPlayback(second)
        store.recordConfirmedPlayback(third)

        store.recordConfirmedPlayback(first)

        XCTAssertEqual(store.recents.map(\.id), [first.id, third.id, second.id])
        XCTAssertEqual(try store.recentRecordCount(for: first.id), 1)
    }

    func testRecentsRetainExactlyTheNewestFiftyUniqueConfirmedChannels() throws {
        let store = try makeStore()
        for index in 0 ... 50 {
            store.recordConfirmedPlayback(channel("fixture-\(index)"))
        }

        XCTAssertEqual(store.recents.count, 50)
        XCTAssertEqual(store.recents.first?.id, LiveChannelID("fixture-50"))
        XCTAssertEqual(store.recents.last?.id, LiveChannelID("fixture-1"))
        XCTAssertEqual(try store.recentRecordCount(for: LiveChannelID("fixture-0")), 0)
    }

    func testClearingRecentsIsIdempotentAndPreservesFavorites() throws {
        let store = try makeStore()
        let favorite = channel("fixture-favorite")
        store.setFavorite(favorite, isFavorite: true)
        store.recordConfirmedPlayback(channel("fixture-recent"))

        store.clearRecents()
        store.clearRecents()

        XCTAssertTrue(store.recents.isEmpty)
        XCTAssertTrue(store.isFavorite(favorite.id))
    }

    func testDurableModelsExposeOnlyTheDeclaredSafeAllowList() {
        XCTAssertEqual(FavoriteRecord.persistedPropertyNames, ["channelID", "name", "displayNumber", "category"])
        XCTAssertEqual(RecentRecord.persistedPropertyNames, ["channelID", "name", "displayNumber", "category", "rank", "confirmedAt"])
        XCTAssertEqual(PlayerPreferenceRecord.persistedPropertyNames, ["selectedTab", "compactWindowAlwaysOnTop", "compactFrameAutosaveName", "libraryFrameAutosaveName"])
    }

    private func makeStore() throws -> LibraryStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FavoriteRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: configuration
        )
        return LibraryStore(modelContainer: container, now: { Date(timeIntervalSince1970: 1) })
    }

    private func channel(_ rawValue: String) -> LibraryChannelSnapshot {
        LibraryChannelSnapshot(
            id: LiveChannelID(rawValue),
            name: "Fixture \(rawValue)",
            displayNumber: 42,
            category: "Test"
        )
    }
}

@MainActor
final class ProductIdentityLibraryMigrationTests: XCTestCase {
    func testApprovedDestinationImportsLegacyRecordsWithoutMovingTheLegacyStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Canis97LibraryMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyURL = root
            .appendingPathComponent(ProductIdentity.Legacy.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.Legacy.libraryStoreFileName)
        let destinationURL = root
            .appendingPathComponent(ProductIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.NonSecretStorage.libraryStoreFileName)

        let legacyContainer = try LibraryStore.makePersistentContainer(at: legacyURL)
        let snapshot = LibraryChannelSnapshot(
            id: LiveChannelID("canis97-legacy"),
            name: "Legacy",
            displayNumber: 97,
            category: "Fixture"
        )
        LibraryStore(modelContainer: legacyContainer).setFavorite(snapshot, isFavorite: true)

        let migrated = try LibraryStore.makePersistentContainer(
            at: destinationURL,
            migratingLegacyStoreAt: legacyURL
        )

        XCTAssertEqual(LibraryStore(modelContainer: migrated).favorites, [snapshot])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }
}

@MainActor
final class PlaybackQueueContractTests: XCTestCase {
    func testCapturedQueueKeepsExactOrderAndNeverWraps() {
        let ids = values("one", "two", "three", "four")
        var queue = PlaybackQueue(originIDs: ids, currentID: ids[1])
        let entitled = [ids[0], ids[1], ids[3]]

        XCTAssertEqual(queue.capturedIDs, ids)
        XCTAssertEqual(queue.currentIndex, 1)
        XCTAssertEqual(queue.candidate(.next, currentAvailableIDs: entitled, fullLineup: ids), ids[3])
        XCTAssertNil(queue.candidate(.next, currentAvailableIDs: entitled, fullLineup: ids))
        XCTAssertEqual(queue.candidate(.previous, currentAvailableIDs: entitled, fullLineup: ids), ids[1])
    }

    func testEmptyAndOneItemQueuesDisableDirectionsAndUseFullLineupFallback() {
        let only = LiveChannelID("only")
        XCTAssertEqual(PlaybackQueue(originIDs: [], currentID: nil).availability(currentAvailableIDs: [], fullLineup: []), .none)
        XCTAssertEqual(PlaybackQueue(originIDs: [only], currentID: only).availability(currentAvailableIDs: [only], fullLineup: [only]), .none)

        let captured = values("removed-one", "removed-two")
        let lineup = values("alpha", "beta")
        var queue = PlaybackQueue(originIDs: captured, currentID: captured[0])
        XCTAssertEqual(queue.candidate(.next, currentAvailableIDs: lineup, fullLineup: lineup), lineup[0])
    }

    private func values(_ rawValues: String...) -> [LiveChannelID] {
        rawValues.map(LiveChannelID.init)
    }
}

final class LibraryViewStateContractTests: XCTestCase {
    func testFourLockedTabsExposeNativeTitlesAndPersistenceValues() {
        XCTAssertEqual(LibraryTab.allCases, [.channels, .categories, .favorites, .recents])
        XCTAssertEqual(LibraryTab.channels.title, "Channels")
        XCTAssertEqual(LibraryTab.categories.title, "Categories")
        XCTAssertEqual(LibraryTab.favorites.title, "Favorites")
        XCTAssertEqual(LibraryTab.recents.title, "Recents")
    }

    func testEmptySearchKeepsTheCurrentTabCollection() {
        XCTAssertFalse(LibrarySearchQuery("").filtersVisibleCollection)
        XCTAssertTrue(LibrarySearchQuery("rock").filtersVisibleCollection)
    }

    func testRevealKeepsFavoritesWhenSkippedChannelBelongsToFavorites() {
        let first = LiveChannelID("favorite-one")
        let second = LiveChannelID("favorite-two")

        let disposition = LibraryRevealPolicy.disposition(
            currentTab: .favorites,
            currentCollectionIDs: [first, second],
            visibleIDs: [first, second],
            targetID: second
        )

        XCTAssertEqual(disposition, LibraryRevealDisposition(tab: .favorites, clearsSearch: false))
    }

    func testRevealClearsSearchWithoutLeavingFavoritesWhenSearchHidesSkippedChannel() {
        let first = LiveChannelID("favorite-one")
        let second = LiveChannelID("favorite-two")

        let disposition = LibraryRevealPolicy.disposition(
            currentTab: .favorites,
            currentCollectionIDs: [first, second],
            visibleIDs: [first],
            targetID: second
        )

        XCTAssertEqual(disposition, LibraryRevealDisposition(tab: .favorites, clearsSearch: true))
    }

    func testRevealFallsBackToChannelsWhenCurrentCollectionCannotShowSkippedChannel() {
        let target = LiveChannelID("not-in-current-collection")

        let disposition = LibraryRevealPolicy.disposition(
            currentTab: .recents,
            currentCollectionIDs: [LiveChannelID("recent")],
            visibleIDs: [LiveChannelID("recent")],
            targetID: target
        )

        XCTAssertEqual(disposition, LibraryRevealDisposition(tab: .channels, clearsSearch: true))
    }

    func testSavedFavoriteRemainsVisibleWhenTheCurrentCatalogIsUnavailable() {
        let snapshot = LibraryChannelSnapshot(
            id: LiveChannelID("saved-favorite"),
            name: "Saved Favorite",
            displayNumber: 42,
            category: "Music"
        )

        let unknown = LibraryChannelItem.saved(
            [snapshot],
            currentChannels: [],
            catalogIsResolved: false
        )
        let unavailable = LibraryChannelItem.saved(
            [snapshot],
            currentChannels: [],
            catalogIsResolved: true
        )

        XCTAssertEqual(unknown.map(\.id), [snapshot.id])
        XCTAssertEqual(unknown.first?.channel.name, "Saved Favorite")
        XCTAssertEqual(unknown.first?.availability, .unknown)
        XCTAssertEqual(unavailable.first?.availability, .unavailable)
        XCTAssertFalse(unavailable.first?.availability.canTune ?? true)
    }

    func testSavedFavoriteUsesCurrentCatalogDetailsWhenAvailable() {
        let snapshot = LibraryChannelSnapshot(
            id: LiveChannelID("saved-favorite"),
            name: "Old Name",
            displayNumber: 42,
            category: "Music"
        )
        let current = liveChannel("saved-favorite", name: "Current Name", number: 43, category: "Pop")

        let projected = LibraryChannelItem.saved(
            [snapshot],
            currentChannels: [current],
            catalogIsResolved: true
        )

        XCTAssertEqual(projected.first?.channel, current)
        XCTAssertEqual(projected.first?.availability, .available)
        XCTAssertTrue(projected.first?.availability.canTune ?? false)
    }

    func testCategoriesCreateDistinctBrowseGroupsWithCountsAndChannelOrder() {
        let channels = [
            liveChannel("talk-late", name: "Later", number: 110, category: " Talk "),
            liveChannel("music", name: "Music", number: 2, category: "Music"),
            liveChannel("talk-early", name: "Earlier", number: 100, category: "Talk"),
            liveChannel("other", name: "Other", number: 900, category: "   "),
        ]

        let groups = LibraryCategoryGroup.groups(from: channels)

        XCTAssertEqual(groups.map(\.name), ["Music", "Talk", "Other"])
        XCTAssertEqual(groups.map(\.channels.count), [1, 2, 1])
        XCTAssertEqual(
            groups.first(where: { $0.name == "Talk" })?.channels.map(\.id),
            [LiveChannelID("talk-early"), LiveChannelID("talk-late")]
        )
    }

    func testCategoriesUseOneGroupedCollectionInsteadOfASecondSelectionPane() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "SiriusMac/Catalog/ListeningView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Section {"))
        XCTAssertTrue(source.contains("Channels grouped by category"))
        XCTAssertFalse(source.contains("HSplitView"))
        XCTAssertFalse(source.contains("Choose a Category"))
    }

    private func liveChannel(
        _ id: String,
        name: String,
        number: Int,
        category: String?
    ) -> LiveChannel {
        LiveChannel(
            id: LiveChannelID(id),
            name: name,
            displayNumber: number,
            category: category
        )
    }
}
