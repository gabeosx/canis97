import SwiftData
import XCTest
@testable import Canis97
import SiriusXMClient

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testPersistentContainerFailureDoesNotPretendEphemeralFavoritesAreSaved() throws {
        enum PersistentContainerError: Error { case unavailable }
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let fallback = try ModelContainer(
            for: FavoriteRecord.self,
            FavoriteSongRecord.self,
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
            .appendingPathComponent("Canis97LibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("default.store")
        let destinationURL = directory
            .appendingPathComponent(ProductIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.NonSecretStorage.libraryStoreFileName)

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
            FavoriteSongRecord.self,
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
        XCTAssertEqual(FavoriteSongRecord.persistedPropertyNames, [
            "storageKey", "normalizedTitle", "normalizedArtist", "title", "artist",
            "albumName", "sourceChannelID", "sourceChannelName",
            "sourceChannelDisplayNumber", "savedAt",
        ])
        XCTAssertEqual(RecentRecord.persistedPropertyNames, ["channelID", "name", "displayNumber", "category", "rank", "confirmedAt"])
        XCTAssertEqual(PlayerPreferenceRecord.persistedPropertyNames, ["selectedTab", "compactWindowAlwaysOnTop", "compactFrameAutosaveName", "libraryFrameAutosaveName"])
    }

    func testSongFavoritesDeduplicateAndReload() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FavoriteRecord.self,
            FavoriteSongRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: configuration
        )
        let firstStore = LibraryStore(modelContainer: container)
        let original = song(
            title: "  Song\tTitle  ",
            artist: "  Artist  Name  ",
            sourceID: "source-one",
            sourceName: "One",
            savedAt: Date(timeIntervalSince1970: 10)
        )
        let refreshed = song(
            title: "song title",
            artist: "artist name",
            albumName: "Verified Album",
            sourceID: "source-two",
            sourceName: "Two",
            savedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(firstStore.setSongFavorite(original, isFavorite: true), .saved)
        XCTAssertEqual(firstStore.setSongFavorite(refreshed, isFavorite: true), .saved)
        XCTAssertEqual(try firstStore.favoriteSongRecordCount(for: original.identity), 1)
        XCTAssertEqual(firstStore.favoriteSongs.count, 1)
        XCTAssertEqual(firstStore.favoriteSongs[0].savedAt, original.savedAt)

        let reopenedStore = LibraryStore(modelContainer: container)
        XCTAssertEqual(reopenedStore.favoriteSongs.count, 1)
        XCTAssertEqual(reopenedStore.favoriteSongs[0].identity, original.identity)
        XCTAssertEqual(reopenedStore.favoriteSongs[0].title, "song title")
        XCTAssertEqual(reopenedStore.favoriteSongs[0].artist, "artist name")
        XCTAssertEqual(reopenedStore.favoriteSongs[0].albumName, "Verified Album")
        XCTAssertEqual(reopenedStore.favoriteSongs[0].sourceChannel.rawIdentity, "source-two")
        XCTAssertEqual(reopenedStore.favoriteSongs[0].savedAt, original.savedAt)
    }

    func testSongFavoriteRemovalIsIdempotentAndSeparateFromChannelFavorites() throws {
        let store = try makeStore()
        let channelFavorite = channel("fixture-channel-favorite")
        let savedSong = song()
        store.setFavorite(channelFavorite, isFavorite: true)
        XCTAssertEqual(store.setSongFavorite(savedSong, isFavorite: true), .saved)

        XCTAssertEqual(store.setSongFavorite(savedSong, isFavorite: false), .removed)
        XCTAssertEqual(store.setSongFavorite(savedSong, isFavorite: false), .removed)
        XCTAssertTrue(store.favoriteSongs.isEmpty)
        XCTAssertEqual(try store.favoriteSongRecordCount(for: savedSong.identity), 0)
        XCTAssertTrue(store.isFavorite(channelFavorite.id))
    }

    func testSongFavoriteFallbackDoesNotPublishAnEphemeralSavedState() throws {
        enum PersistentContainerError: Error { case unavailable }
        let fallback = try ModelContainer(
            for: FavoriteRecord.self,
            FavoriteSongRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let setup = LibraryStore.makeDefaultContainer(
            persistentContainer: { throw PersistentContainerError.unavailable },
            fallbackContainer: { fallback }
        )
        let store = LibraryStore(modelContainer: setup.container, persistence: setup.persistence)

        XCTAssertEqual(store.setSongFavorite(song(), isFavorite: true), .failed)
        XCTAssertTrue(store.favoriteSongs.isEmpty)
        XCTAssertTrue(store.lastSaveFailed)
    }

    private func makeStore() throws -> LibraryStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FavoriteRecord.self,
            FavoriteSongRecord.self,
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

    private func song(
        title: String = "Fixture Song",
        artist: String = "Fixture Artist",
        albumName: String? = nil,
        sourceID: String = "fixture-source",
        sourceName: String? = "Fixture Channel",
        savedAt: Date = Date(timeIntervalSince1970: 1)
    ) -> FavoriteSongSnapshot {
        let source = FavoriteSongSourceChannel(
            rawIdentity: sourceID,
            name: sourceName,
            displayNumber: 42
        )!
        return FavoriteSongSnapshot(
            title: title,
            artist: artist,
            albumName: albumName,
            sourceChannel: source,
            savedAt: savedAt
        )!
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
    func testFiveLockedTabsExposeNativeTitlesAndPersistenceValues() {
        XCTAssertEqual(LibraryTab.allCases, [.channels, .categories, .favorites, .favoriteSongs, .recents])
        XCTAssertEqual(LibraryTab.channels.title, "Channels")
        XCTAssertEqual(LibraryTab.categories.title, "Categories")
        XCTAssertEqual(LibraryTab.favorites.title, "Favorites")
        XCTAssertEqual(LibraryTab.favoriteSongs.title, "Favorite Songs")
        XCTAssertEqual(LibraryTab.favoriteSongs.rawValue, "favoriteSongs")
        XCTAssertEqual(LibraryTab.recents.title, "Recents")
    }

    func testFavoriteSongSearchUsesOnlySavedSongPresentation() {
        let snapshot = FavoriteSongSnapshot(
            title: "Title Match",
            artist: "Artist Match",
            albumName: "Album Match",
            sourceChannel: FavoriteSongSourceChannel(rawIdentity: "source", name: "Source Match", displayNumber: 42),
            savedAt: Date(timeIntervalSince1970: 1)
        )!

        XCTAssertTrue(FavoriteSongSearch("title").matches(snapshot))
        XCTAssertTrue(FavoriteSongSearch("artist").matches(snapshot))
        XCTAssertTrue(FavoriteSongSearch("album").matches(snapshot))
        XCTAssertTrue(FavoriteSongSearch("source").matches(snapshot))
        XCTAssertFalse(FavoriteSongSearch("missing").matches(snapshot))
    }

    func testFavoriteSongRowKeepsSavedContextOutOfChannelProjection() {
        let snapshot = FavoriteSongSnapshot(
            title: "Saved Title",
            artist: "Saved Artist",
            albumName: "Verified Album",
            sourceChannel: FavoriteSongSourceChannel(rawIdentity: "source-id", name: "Saved Source", displayNumber: 42),
            savedAt: Date(timeIntervalSince1970: 1)
        )!

        XCTAssertEqual(snapshot.copyText, "Saved Artist — Saved Title")
        XCTAssertEqual(FavoriteSongRow.sourcePresentation(for: snapshot), "Channel 42 · Saved Source · source-id")
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
