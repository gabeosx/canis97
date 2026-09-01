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

    enum StoredAuthenticationCredentialLoadOutcome {
        enum Kind: Equatable {
            case credential
            case missing
            case invalid
            case unavailable
        }

        case credential(AuthenticationCredential)
        case missing
        case invalid
        case unavailable

        var kind: Kind {
            switch self {
            case .credential: .credential
            case .missing: .missing
            case .invalid: .invalid
            case .unavailable: .unavailable
            }
        }
    }

    private let service: String
    private let account: String
    private let storedCredentialReader: (() throws -> Data?)?
    private let storedCredentialRemover: (() throws -> Void)?

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.siriusmac.player",
        account: String = "approved-reusable-credential",
        storedCredentialReader: (() throws -> Data?)? = nil,
        storedCredentialRemover: (() throws -> Void)? = nil
    ) {
        self.service = service
        self.account = account
        self.storedCredentialReader = storedCredentialReader
        self.storedCredentialRemover = storedCredentialRemover
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
        if let storedCredentialReader {
            return try storedCredentialReader()
        }

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
        if let storedCredentialRemover {
            return try storedCredentialRemover()
        }

        switch Self.classify(status: SecItemDelete(itemQuery as CFDictionary)) {
        case .found, .missing:
            return
        case .unavailable:
            throw StorageError.unavailable
        }
    }

    /// Loads a reusable credential for app-owned authentication orchestration.
    ///
    /// Material remains inside this adapter until it becomes an opaque client handoff.
    /// Invalid persisted bytes are classified fail-closed but remain in Keychain until
    /// the owner explicitly chooses Sign Out or Clear Local Session.
    func loadStoredCredentialForAuthentication() -> StoredAuthenticationCredentialLoadOutcome {
        let storedMaterial: Data
        do {
            guard let material = try readStoredCredential() else {
                return .missing
            }
            storedMaterial = material
        } catch {
            return .unavailable
        }

        guard storedMaterial.count <= 40_960,
              AuthenticationCredential.isSupportedPersistentMaterial(storedMaterial) else {
            return .invalid
        }

        let credential = AuthenticationCredential(volatileMaterial: storedMaterial)
        guard let upgraded = credential.addingDiagnosticIdentifierIfMissing() else {
            return .credential(credential)
        }

        // This migration adds only a random diagnostic identifier beside the
        // unchanged opaque cookies. Failure to persist the identifier must not
        // make an otherwise valid SiriusXM session unusable for this launch.
        try? upgraded.withVolatileMaterial { try save(material: $0) }
        return .credential(upgraded)
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
        guard AuthenticationCredential.isSupportedPersistentMaterial(material) else {
            throw StorageError.unavailable
        }
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
