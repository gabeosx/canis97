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

    func testAuthenticationLoaderReturnsOnlyAnOpaqueBoundedCredential() async throws {
        let store = makeStore()
        defer { try? store.removeStoredCredential() }

        try await store.save(AuthenticationCredential(volatileMaterial: Data("approved-material".utf8)))

        switch store.loadStoredCredentialForAuthentication() {
        case .credential:
            XCTAssertNil(try store.readStoredCredential()?.first(where: { $0 == 0 }))
        default:
            XCTFail("Expected a semantic opaque credential outcome")
        }
    }

    func testAuthenticationLoaderErasesInvalidMaterialAndSurfacesStorageFailuresSemantically() async throws {
        let invalidStore = makeStore()
        defer { try? invalidStore.removeStoredCredential() }
        try await invalidStore.save(AuthenticationCredential(volatileMaterial: Data("contains whitespace".utf8)))

        XCTAssertEqual(invalidStore.loadStoredCredentialForAuthentication().kind, .invalidErased)
        XCTAssertNil(try invalidStore.readStoredCredential())

        let unavailableStore = KeychainCredentialStore(
            storedCredentialReader: { throw KeychainCredentialStore.StorageError.unavailable },
            storedCredentialRemover: {}
        )
        XCTAssertEqual(unavailableStore.loadStoredCredentialForAuthentication().kind, .unavailable)

        let cleanupFailureStore = KeychainCredentialStore(
            storedCredentialReader: { Data() },
            storedCredentialRemover: { throw KeychainCredentialStore.StorageError.unavailable }
        )
        XCTAssertEqual(cleanupFailureStore.loadStoredCredentialForAuthentication().kind, .cleanupFailed)
    }

    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(
            service: "com.siriusmac.player.tests.\(UUID().uuidString)",
            account: UUID().uuidString
        )
    }
}
