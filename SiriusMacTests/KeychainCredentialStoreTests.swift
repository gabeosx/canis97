import Foundation
import Security
import XCTest
@testable import SiriusMac
@_spi(AppIntegration) import SiriusXMClient

final class KeychainCredentialStoreTests: XCTestCase {
    func testAppScopedEntryCanAddReadUpdateAndDeleteSyntheticBytes() async throws {
        let store = makeStore()
        defer { try? store.removeStoredCredential() }

        let first = try renewableTestCredential(accessToken: "first-secret")
        let firstMaterial = first.withVolatileMaterial { $0 }
        try await store.save(first)
        XCTAssertEqual(try store.readStoredCredential(), firstMaterial)

        let second = try renewableTestCredential(accessToken: "second-secret")
        let secondMaterial = second.withVolatileMaterial { $0 }
        try await store.save(second)
        XCTAssertEqual(try store.readStoredCredential(), secondMaterial)

        try store.removeStoredCredential()
        XCTAssertNil(try store.readStoredCredential())
    }

    func testDuplicateSaveUpdatesOneIntendedItem() async throws {
        let store = makeStore()
        defer { try? store.removeStoredCredential() }

        let original = try renewableTestCredential(accessToken: "original")
        let replacement = try renewableTestCredential(accessToken: "replacement")
        try await store.save(original)
        try await store.save(replacement)

        XCTAssertEqual(try store.readStoredCredential(), replacement.withVolatileMaterial { $0 })
    }

    func testMissingAndFailureStatusesUseSafeClassifications() {
        XCTAssertEqual(KeychainCredentialStore.classify(status: errSecItemNotFound), .missing)
        XCTAssertEqual(KeychainCredentialStore.classify(status: errSecAuthFailed), .unavailable)
        XCTAssertFalse(KeychainCredentialStore.StorageError.unavailable.localizedDescription.contains("-25293"))
    }

    func testAuthenticationLoaderReturnsOnlyAnOpaqueBoundedCredential() async throws {
        let store = makeStore()
        defer { try? store.removeStoredCredential() }

        try await store.save(renewableTestCredential(accessToken: "approved-material"))

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

func renewableTestCredential(
    accessToken: String = "synthetic-access-token",
    accessExpiresAt: Date = Date(timeIntervalSinceNow: 10_800)
) throws -> AuthenticationCredential {
    let formatter = ISO8601DateFormatter()
    let authentication = try JSONSerialization.data(withJSONObject: [
        "handle": "synthetic-handle",
        "identityGrant": ["grant": "synthetic-identity-grant", "identityId": "synthetic-identity"],
        "session": [
            "accessToken": accessToken,
            "accessTokenExpiresAt": formatter.string(from: accessExpiresAt),
            "refreshToken": "synthetic-refresh-token",
            "refreshTokenExpiresAt": formatter.string(from: Date(timeIntervalSinceNow: 7_776_000)),
            "sessionType": "authenticated",
        ],
    ], options: [.sortedKeys])
    let device = try JSONSerialization.data(withJSONObject: [
        "deviceId": "synthetic-device",
        "grant": "synthetic-device-grant",
        "grantExpiresAt": formatter.string(from: Date(timeIntervalSinceNow: 2_592_000)),
        "grantVersion": "v2",
        "refreshGrant": "synthetic-device-refresh-grant",
        "refreshGrantExpiresAt": formatter.string(from: Date(timeIntervalSinceNow: 15_552_000)),
    ], options: [.sortedKeys])
    let allowed = CharacterSet.alphanumerics
    return try AuthenticationCredential(
        browserAuthenticationCookieValue: String(data: authentication, encoding: .utf8)!.addingPercentEncoding(withAllowedCharacters: allowed)!,
        browserDeviceGrantCookieValue: String(data: device, encoding: .utf8)!.addingPercentEncoding(withAllowedCharacters: allowed)!
    )
}
