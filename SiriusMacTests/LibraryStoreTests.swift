import SwiftData
import XCTest
@testable import SiriusMac
import SiriusXMClient

@MainActor
final class LibraryStoreTests: XCTestCase {
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
