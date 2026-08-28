import Foundation

enum PersistedSkinClassification: String, Codable, CaseIterable, Sendable {
    case native
    case bundled
    case imported
}

struct PersistedSkinSelection: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let native = Self(identifier: "native", classification: .native)

    let schemaVersion: Int
    let identifier: String
    let classification: PersistedSkinClassification

    init(
        schemaVersion: Int = currentSchemaVersion,
        identifier: String,
        classification: PersistedSkinClassification
    ) {
        self.schemaVersion = schemaVersion
        self.identifier = identifier
        self.classification = classification
    }
}

enum SkinSelectionStoreError: Error, Equatable {
    case invalidSelection
    case malformedRecord
    case unsupportedSchema
    case readFailed
    case writeFailed
}

struct SkinSelectionFileOperations: @unchecked Sendable {
    let createDirectory: (URL) throws -> Void
    let fileExists: (URL) -> Bool
    let read: (URL) throws -> Data
    let write: (Data, URL) throws -> Void
    let replace: (URL, URL) throws -> Void
    let move: (URL, URL) throws -> Void
    let remove: (URL) throws -> Void

    static let live = Self(
        createDirectory: { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        },
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        read: { try Data(contentsOf: $0) },
        write: { data, url in try data.write(to: url) },
        replace: { temporaryURL, destinationURL in
            _ = try FileManager.default.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        },
        move: { try FileManager.default.moveItem(at: $0, to: $1) },
        remove: { try FileManager.default.removeItem(at: $0) }
    )
}

actor SkinSelectionStore {
    nonisolated let selectionFileURL: URL
    nonisolated let legacySelectionFileURL: URL
    nonisolated let migrationMarkerURL: URL

    private let fileOperations: SkinSelectionFileOperations
    private let validatedImportedPackageExists: @Sendable (String) -> Bool
    private let encoder: JSONEncoder

    init(
        applicationSupportDirectory: URL? = nil,
        fileOperations: SkinSelectionFileOperations = .live,
        validatedImportedPackageExists: (@Sendable (String) -> Bool)? = nil
    ) {
        let supportDirectory = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        selectionFileURL = supportDirectory
            .appendingPathComponent(ProductIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.NonSecretStorage.appearanceSelectionFileName, isDirectory: false)
        legacySelectionFileURL = supportDirectory
            .appendingPathComponent(ProductIdentity.Legacy.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.Legacy.appearanceSelectionFileName, isDirectory: false)
        migrationMarkerURL = supportDirectory
            .appendingPathComponent(ProductIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.NonSecretStorage.migrationMarkerDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.NonSecretStorage.appearanceSelectionMigrationMarkerName)
        self.fileOperations = fileOperations
        self.validatedImportedPackageExists = validatedImportedPackageExists ?? { identifier in
            ManagedSkinStore(applicationSupportDirectory: supportDirectory)
                .validatedManagedPackageExists(identifier: identifier)
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    /// Returns true only when a new durable record replaced the prior value.
    @discardableResult
    func save(_ selection: PersistedSkinSelection) throws -> Bool {
        try Self.validate(selection)
        if let current = try? load(), current == selection {
            return false
        }

        try replaceSelection(with: selection)
        return true
    }

    private func replaceSelection(with selection: PersistedSkinSelection) throws {
        try Self.validate(selection)

        let directoryURL = selectionFileURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".appearance-selection.\(UUID().uuidString).tmp",
            isDirectory: false
        )

        do {
            try fileOperations.createDirectory(directoryURL)
            let data = try encoder.encode(selection)
            try fileOperations.write(data, temporaryURL)
            if fileOperations.fileExists(selectionFileURL) {
                try fileOperations.replace(temporaryURL, selectionFileURL)
            } else {
                try fileOperations.move(temporaryURL, selectionFileURL)
            }
        } catch {
            try? fileOperations.remove(temporaryURL)
            throw SkinSelectionStoreError.writeFailed
        }
    }

    func load() throws -> PersistedSkinSelection? {
        try migrateLegacySelectionIfNeeded()
        guard fileOperations.fileExists(selectionFileURL) else { return nil }
        return try Self.decodeSelection(from: fileOperations.read(selectionFileURL))
    }

    private func migrateLegacySelectionIfNeeded() throws {
        guard !fileOperations.fileExists(selectionFileURL),
              !fileOperations.fileExists(migrationMarkerURL),
              fileOperations.fileExists(legacySelectionFileURL)
        else { return }

        guard let legacyData = try? fileOperations.read(legacySelectionFileURL),
              let legacySelection = try? Self.decodeSelection(from: legacyData),
              legacySelection.classification != .imported
                || validatedImportedPackageExists(legacySelection.identifier)
        else { return }

        try replaceSelection(with: legacySelection)
        guard try loadCurrentSelection() == legacySelection else {
            throw SkinSelectionStoreError.writeFailed
        }
        try writeMigrationMarker()
    }

    private func loadCurrentSelection() throws -> PersistedSkinSelection? {
        guard fileOperations.fileExists(selectionFileURL) else { return nil }
        return try Self.decodeSelection(from: fileOperations.read(selectionFileURL))
    }

    private static func decodeSelection(from data: Data) throws -> PersistedSkinSelection {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys) == ["schemaVersion", "identifier", "classification"]
        else { throw SkinSelectionStoreError.malformedRecord }

        let selection: PersistedSkinSelection
        do {
            selection = try JSONDecoder().decode(PersistedSkinSelection.self, from: data)
        } catch {
            throw SkinSelectionStoreError.malformedRecord
        }
        guard selection.schemaVersion == PersistedSkinSelection.currentSchemaVersion else {
            throw SkinSelectionStoreError.unsupportedSchema
        }
        try Self.validate(selection)
        return selection
    }

    private func writeMigrationMarker() throws {
        let directoryURL = migrationMarkerURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".appearance-selection-migration.\(UUID().uuidString).tmp",
            isDirectory: false
        )
        do {
            try fileOperations.createDirectory(directoryURL)
            try fileOperations.write(Data(), temporaryURL)
            if fileOperations.fileExists(migrationMarkerURL) {
                try fileOperations.replace(temporaryURL, migrationMarkerURL)
            } else {
                try fileOperations.move(temporaryURL, migrationMarkerURL)
            }
        } catch {
            try? fileOperations.remove(temporaryURL)
            throw SkinSelectionStoreError.writeFailed
        }
    }

    /// Startup recovery deliberately collapses every local record problem to
    /// the permanent metadata-only Native reference.
    func restoredSelectionOrNative() -> PersistedSkinSelection {
        (try? load()) ?? .native
    }

    private static func validate(_ selection: PersistedSkinSelection) throws {
        guard selection.schemaVersion == PersistedSkinSelection.currentSchemaVersion else {
            throw SkinSelectionStoreError.unsupportedSchema
        }
        let identifier = selection.identifier
        guard !identifier.isEmpty,
              identifier.utf8.count <= 64,
              identifier.unicodeScalars.allSatisfy(\.isASCII),
              let first = identifier.first,
              first.isLetter || first.isNumber,
              identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" })
        else { throw SkinSelectionStoreError.invalidSelection }
    }
}
