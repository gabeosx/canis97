import Foundation
import Security
import XCTest
@testable import SiriusMac
import SiriusXMClient

final class KeychainCredentialStoreTests: XCTestCase {
    func testAppScopedEntryCanAddReadUpdateAndDeleteSyntheticBytes() async throws {
        let store = makeStore()
        defer { try? store.removeStoredCredential() }

        try await store.save(AuthenticationCredential(volatileMaterial: Data("first-secret".utf8)))
        XCTAssertEqual(try store.readStoredCredential(), Data("first-secret".utf8))

        try await store.save(AuthenticationCredential(volatileMaterial: Data("second-secret".utf8)))
        XCTAssertEqual(try store.readStoredCredential(), Data("second-secret".utf8))

        try store.removeStoredCredential()
        XCTAssertNil(try store.readStoredCredential())
    }

    func testDuplicateSaveUpdatesOneIntendedItem() async throws {
        let store = makeStore()
        defer { try? store.removeStoredCredential() }

        try await store.save(AuthenticationCredential(volatileMaterial: Data("original".utf8)))
        try await store.save(AuthenticationCredential(volatileMaterial: Data("replacement".utf8)))

        XCTAssertEqual(try store.readStoredCredential(), Data("replacement".utf8))
    }

    func testMissingAndFailureStatusesUseSafeClassifications() {
        XCTAssertEqual(KeychainCredentialStore.classify(status: errSecItemNotFound), .missing)
        XCTAssertEqual(KeychainCredentialStore.classify(status: errSecAuthFailed), .unavailable)
        XCTAssertFalse(KeychainCredentialStore.StorageError.unavailable.localizedDescription.contains("-25293"))
    }

    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(
            service: "com.siriusmac.player.tests.\(UUID().uuidString)",
            account: UUID().uuidString
        )
    }
}
