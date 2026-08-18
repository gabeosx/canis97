import Foundation
import Security
@_spi(AppIntegration) import SiriusXMClient

/// App-owned storage for the one reusable credential that the client has approved.
///
/// This adapter uses a single generic-password item identity and deliberately exposes
/// only safe error classifications. It never falls back to preferences, files, or an
/// alternate secret store.
final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    enum StatusClassification: Equatable {
        case found
        case missing
        case unavailable
    }

    enum StorageError: Error, LocalizedError, Equatable {
        case unavailable

        var errorDescription: String? {
            "Credential storage is unavailable."
        }
    }

    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.siriusmac.player",
        account: String = "approved-reusable-credential"
    ) {
        self.service = service
        self.account = account
    }

    func save(_ credential: AuthenticationCredential) async throws {
        try credential.withVolatileMaterial { material in
            try save(material: material)
        }
    }

    func erase() async throws {
        try removeStoredCredential()
    }

    func readStoredCredential() throws -> Data? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch Self.classify(status: status) {
        case .found:
            guard let data = result as? Data else {
                throw StorageError.unavailable
            }
            return data
        case .missing:
            return nil
        case .unavailable:
            throw StorageError.unavailable
        }
    }

    func removeStoredCredential() throws {
        switch Self.classify(status: SecItemDelete(itemQuery as CFDictionary)) {
        case .found, .missing:
            return
        case .unavailable:
            throw StorageError.unavailable
        }
    }

    static func classify(status: OSStatus) -> StatusClassification {
        switch status {
        case errSecSuccess:
            .found
        case errSecItemNotFound:
            .missing
        default:
            .unavailable
        }
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func save(material: Data) throws {
        var newItem = itemQuery
        newItem[kSecValueData as String] = material
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        switch Self.classify(status: addStatus) {
        case .found:
            return
        case .missing:
            throw StorageError.unavailable
        case .unavailable:
            guard addStatus == errSecDuplicateItem else {
                throw StorageError.unavailable
            }

            let changes = [kSecValueData as String: material]
            guard Self.classify(status: SecItemUpdate(itemQuery as CFDictionary, changes as CFDictionary)) == .found else {
                throw StorageError.unavailable
            }
        }
    }
}
