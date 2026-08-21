import SwiftData
import XCTest
@testable import SiriusMac
import SiriusXMClient

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testPersistentContainerFailureFallsBackToAnInMemoryLibrary() throws {
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
        let store = LibraryStore(modelContainer: setup.container)
        let snapshot = channel("fixture-fallback")

        XCTAssertEqual(setup.persistence, .inMemoryFallback)
        store.setFavorite(snapshot, isFavorite: true)
        XCTAssertEqual(store.favorites, [snapshot])
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
final class PlaybackQueueContractTests: XCTestCase {
    func testCapturedQueueKeepsExactOrderAndNeverWraps() {
        let ids = values("one", "two", "three", "four")
        var queue = PlaybackQueue(originIDs: ids, currentID: ids[1])
        let entitled = [ids[0], ids[1], ids[3]]

        XCTAssertEqual(queue.capturedIDs, ids)
        XCTAssertEqual(queue.currentIndex, 1)
        XCTAssertEqual(queue.candidate(.next, currentEntitledIDs: entitled, fullLineup: ids), ids[3])
        XCTAssertNil(queue.candidate(.next, currentEntitledIDs: entitled, fullLineup: ids))
        XCTAssertEqual(queue.candidate(.previous, currentEntitledIDs: entitled, fullLineup: ids), ids[1])
    }

    func testEmptyAndOneItemQueuesDisableDirectionsAndUseFullLineupFallback() {
        let only = LiveChannelID("only")
        XCTAssertEqual(PlaybackQueue(originIDs: [], currentID: nil).availability(currentEntitledIDs: [], fullLineup: []), .none)
        XCTAssertEqual(PlaybackQueue(originIDs: [only], currentID: only).availability(currentEntitledIDs: [only], fullLineup: [only]), .none)

        let captured = values("removed-one", "removed-two")
        let lineup = values("alpha", "beta")
        var queue = PlaybackQueue(originIDs: captured, currentID: captured[0])
        XCTAssertEqual(queue.candidate(.next, currentEntitledIDs: lineup, fullLineup: lineup), lineup[0])
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
}
