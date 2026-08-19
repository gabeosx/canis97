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
            break
        default:
            XCTFail("Expected a semantic opaque credential outcome")
        }
    }

    func testAuthenticationLoaderRejectsInvalidMaterialWithoutDeletingIt() throws {
        let invalidMaterial = Data("contains whitespace".utf8)
        var storedMaterial: Data? = invalidMaterial
        var removalCount = 0
        let invalidStore = KeychainCredentialStore(
            storedCredentialReader: { storedMaterial },
            storedCredentialRemover: {
                removalCount += 1
                storedMaterial = nil
            }
        )

        XCTAssertEqual(invalidStore.loadStoredCredentialForAuthentication().kind, .invalid)
        XCTAssertEqual(storedMaterial, invalidMaterial)
        XCTAssertEqual(removalCount, 0)

        let unavailableStore = KeychainCredentialStore(
            storedCredentialReader: { throw KeychainCredentialStore.StorageError.unavailable },
            storedCredentialRemover: {}
        )
        XCTAssertEqual(unavailableStore.loadStoredCredentialForAuthentication().kind, .unavailable)

    }

    func testAuthenticationLoaderRejectsEmptyOversizedAndNonUTF8MaterialWithoutDeletingIt() {
        let invalidMaterials = [
            Data(),
            Data(repeating: 65, count: 8_193),
            Data([0xFF, 0xFE]),
        ]

        for material in invalidMaterials {
            var storedMaterial: Data? = material
            var removalCount = 0
            let store = KeychainCredentialStore(
                storedCredentialReader: { storedMaterial },
                storedCredentialRemover: {
                    removalCount += 1
                    storedMaterial = nil
                }
            )

            XCTAssertEqual(store.loadStoredCredentialForAuthentication().kind, .invalid)
            XCTAssertEqual(storedMaterial, material)
            XCTAssertEqual(removalCount, 0)
        }
    }

    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(
            service: "com.siriusmac.player.tests.\(UUID().uuidString)",
            account: UUID().uuidString
        )
    }
}
