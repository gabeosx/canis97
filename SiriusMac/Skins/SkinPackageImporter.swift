import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

struct SkinImportResult: Sendable {
    enum StorageOutcome: Sendable {
        case imported
        case unchanged
    }

    let storageOutcome: StorageOutcome
    let appearance: ValidatedSkinAppearance
    let selected: Bool
}

enum SkinPackageCompatibilityFailure: Error, Equatable, Sendable {
    case unsupportedSchema
}

struct ManagedSkinStore: @unchecked Sendable {
    enum PromotionOutcome: Sendable {
        case imported(URL)
        case unchanged(URL)
    }

    struct PromotionTransaction: Sendable {
        let outcome: PromotionOutcome
        fileprivate let destinationURL: URL
        fileprivate let backupURL: URL?
        fileprivate let installedNewContent: Bool
    }

    let skinsRootURL: URL
    let stagingRootURL: URL
    let packagesRootURL: URL
    let legacyPackagesRootURL: URL
    let migrationMarkerURL: URL

    private let fileManager: FileManager
    private let removeManagedPackage: (URL) throws -> Void

    init(
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default,
        removeManagedPackage: ((URL) throws -> Void)? = nil
    ) {
        let support = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        skinsRootURL = support
            .appendingPathComponent(ProductIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.NonSecretStorage.managedSkinsDirectoryName, isDirectory: true)
        stagingRootURL = skinsRootURL.appendingPathComponent(".staging", isDirectory: true)
        packagesRootURL = skinsRootURL.appendingPathComponent("Packages", isDirectory: true)
        legacyPackagesRootURL = support
            .appendingPathComponent(ProductIdentity.Legacy.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.Legacy.managedSkinsDirectoryName, isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
        migrationMarkerURL = support
            .appendingPathComponent(ProductIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.NonSecretStorage.migrationMarkerDirectoryName, isDirectory: true)
            .appendingPathComponent(ProductIdentity.NonSecretStorage.managedSkinsMigrationMarkerName)
        self.fileManager = fileManager
        self.removeManagedPackage = removeManagedPackage ?? { url in
            try fileManager.removeItem(at: url)
        }
    }

    func makeStagingDirectory() throws -> URL {
        do {
            try fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: packagesRootURL, withIntermediateDirectories: true)
            let url = stagingRootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        } catch {
            throw SkinPackageRejection.storageFailed
        }
    }

    func removeStagingDirectory(_ url: URL) {
        guard isDirectChild(url, of: stagingRootURL) else { return }
        try? fileManager.removeItem(at: url)
    }

    func preparePromotion(
        stagingURL: URL,
        identifier: SkinIdentifier,
        digest: String
    ) throws -> PromotionTransaction {
        guard isDirectChild(stagingURL, of: stagingRootURL) else {
            throw SkinPackageRejection.storageFailed
        }
        let destination = packagesRootURL.appendingPathComponent(identifier.rawValue, isDirectory: true)
        let digestURL = stagingURL.appendingPathComponent(".content-digest", isDirectory: false)
        do {
            try Data(digest.utf8).write(to: digestURL, options: .atomic)
            if fileManager.fileExists(atPath: destination.path),
               try readDigest(at: destination) == digest {
                try fileManager.removeItem(at: stagingURL)
                return PromotionTransaction(
                    outcome: .unchanged(destination),
                    destinationURL: destination,
                    backupURL: nil,
                    installedNewContent: false
                )
            }

            try fileManager.createDirectory(at: packagesRootURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                let backupName = ".backup-\(identifier.rawValue)-\(UUID().uuidString)"
                let backupURL = packagesRootURL.appendingPathComponent(backupName, isDirectory: true)
                do {
                    // Preserve an independent rollback source before the atomic
                    // replacement call. That keeps the prior managed package
                    // recoverable even if replacement itself reports failure.
                    try fileManager.copyItem(at: destination, to: backupURL)
                    _ = try fileManager.replaceItemAt(
                        destination,
                        withItemAt: stagingURL,
                        backupItemName: nil,
                        options: [.usingNewMetadataOnly]
                    )
                } catch {
                    try restoreBackupIfPresent(backupURL, destination: destination)
                    throw SkinPackageRejection.storageFailed
                }
                guard fileManager.fileExists(atPath: destination.path),
                      fileManager.fileExists(atPath: backupURL.path)
                else {
                    try restoreBackupIfPresent(backupURL, destination: destination)
                    throw SkinPackageRejection.storageFailed
                }
                return PromotionTransaction(
                    outcome: .imported(destination),
                    destinationURL: destination,
                    backupURL: backupURL,
                    installedNewContent: true
                )
            } else {
                try fileManager.moveItem(at: stagingURL, to: destination)
                return PromotionTransaction(
                    outcome: .imported(destination),
                    destinationURL: destination,
                    backupURL: nil,
                    installedNewContent: true
                )
            }
        } catch let rejection as SkinPackageRejection {
            throw rejection
        } catch {
            throw SkinPackageRejection.storageFailed
        }
    }

    func commit(_ transaction: PromotionTransaction) throws {
        guard let backupURL = transaction.backupURL else { return }
        do {
            try fileManager.removeItem(at: backupURL)
        } catch {
            throw SkinPackageRejection.storageFailed
        }
    }

    func rollback(_ transaction: PromotionTransaction) throws {
        guard transaction.installedNewContent else { return }
        do {
            if let backupURL = transaction.backupURL {
                try restoreBackupIfPresent(backupURL, destination: transaction.destinationURL)
            } else if fileManager.fileExists(atPath: transaction.destinationURL.path) {
                try fileManager.removeItem(at: transaction.destinationURL)
            }
        } catch {
            throw SkinPackageRejection.storageFailed
        }
    }

    func managedPackageURLs() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: packagesRootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.filter { url in
            guard isDirectChild(url, of: packagesRootURL),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
    }

    /// Copies only legacy packages that validate again as managed Canis97
    /// packages. The old package root is retained regardless of the outcome.
    func migrateLegacyPackagesIfNeeded() {
        guard !fileManager.fileExists(atPath: migrationMarkerURL.path) else { return }
        guard managedPackageURLs().isEmpty else {
            try? writeMigrationMarker()
            return
        }
        guard let legacyURLs = try? fileManager.contentsOfDirectory(
            at: legacyPackagesRootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for legacyURL in legacyURLs {
            guard isDirectChild(legacyURL, of: legacyPackagesRootURL),
                  let values = try? legacyURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else { return }

            let destinationURL = packagesRootURL.appendingPathComponent(
                legacyURL.lastPathComponent,
                isDirectory: true
            )
            guard isDirectChild(destinationURL, of: packagesRootURL),
                  !fileManager.fileExists(atPath: destinationURL.path)
            else { return }

            do {
                try fileManager.createDirectory(at: packagesRootURL, withIntermediateDirectories: true)
                try fileManager.copyItem(at: legacyURL, to: destinationURL)
                guard validatedManagedPackageExists(identifier: legacyURL.lastPathComponent) else {
                    try? fileManager.removeItem(at: destinationURL)
                    return
                }
            } catch {
                try? fileManager.removeItem(at: destinationURL)
                return
            }
        }

        try? writeMigrationMarker()
    }

    func validatedManagedPackageExists(identifier: String) -> Bool {
        let candidate = packagesRootURL.appendingPathComponent(identifier, isDirectory: true)
        guard isDirectChild(candidate, of: packagesRootURL),
              fileManager.fileExists(atPath: candidate.path)
        else { return false }
        return (try? SkinPackageImporter(store: self, fileManager: fileManager)
            .validateManagedPackage(at: candidate)) != nil
    }

    /// Removes only the exact managed directory for an imported reference.
    /// An already-absent package is a successful, idempotent no-op.
    @discardableResult
    func removeImportedSkin(_ reference: SkinSelectionReference) throws -> Bool {
        guard reference.classification == .imported else {
            throw SkinPackageRejection.storageFailed
        }
        let packageURL = packagesRootURL.appendingPathComponent(
            reference.identifier.rawValue,
            isDirectory: true
        )
        guard isDirectChild(packageURL, of: packagesRootURL) else {
            throw SkinPackageRejection.storageFailed
        }
        guard fileManager.fileExists(atPath: packageURL.path) else { return false }
        do {
            let values = try packageURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw SkinPackageRejection.storageFailed
            }
            try removeManagedPackage(packageURL)
            return true
        } catch let rejection as SkinPackageRejection {
            throw rejection
        } catch {
            throw SkinPackageRejection.storageFailed
        }
    }

    private func readDigest(at packageURL: URL) throws -> String? {
        let url = packageURL.appendingPathComponent(".content-digest", isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return String(data: try Data(contentsOf: url), encoding: .utf8)
    }

    private func restoreBackupIfPresent(_ backupURL: URL, destination: URL) throws {
        guard fileManager.fileExists(atPath: backupURL.path) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: backupURL, to: destination)
    }

    private func writeMigrationMarker() throws {
        try fileManager.createDirectory(
            at: migrationMarkerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: migrationMarkerURL, options: .atomic)
    }

    private func isDirectChild(_ candidate: URL, of parent: URL) -> Bool {
        let standardizedParent = parent.standardizedFileURL
        return candidate.standardizedFileURL.deletingLastPathComponent() == standardizedParent
    }
}

struct SkinPackageImporter: @unchecked Sendable {
    private let limits: SkinPackageLimits
    private let store: ManagedSkinStore
    private let fileManager: FileManager
    private let nowNanoseconds: @Sendable () -> UInt64

    init(
        limits: SkinPackageLimits = .standard,
        store: ManagedSkinStore = ManagedSkinStore(),
        fileManager: FileManager = .default,
        nowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.limits = limits
        self.store = store
        self.fileManager = fileManager
        self.nowNanoseconds = nowNanoseconds
    }

    func importPackage(at sourceURL: URL) throws -> (ManagedSkinStore.PromotionOutcome, ValidatedSkinAppearance) {
        let startedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let start = nowNanoseconds()
        try checkProcessing(start: start)
        let sourceValues: URLResourceValues
        do {
            sourceValues = try sourceURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
        } catch {
            throw SkinPackageRejection.sourceUnavailable
        }
        guard sourceURL.pathExtension == "siriusskin",
              sourceValues.isRegularFile == true,
              sourceValues.isSymbolicLink != true,
              let fileSize = sourceValues.fileSize,
              fileSize >= 0
        else { throw SkinPackageRejection.sourceUnavailable }
        let archiveBytes = UInt64(fileSize)
        try SkinPackagePolicy.validateArchiveSize(archiveBytes, limits: limits)

        let centralDirectory: ZIPCentralDirectorySummary
        do {
            centralDirectory = try ZIPCentralDirectoryInspector.inspect(
                Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            )
        } catch let rejection as SkinPackageRejection {
            throw rejection
        } catch {
            throw SkinPackageRejection.sourceUnavailable
        }
        guard !centralDirectory.containsEncryptedEntry else {
            throw SkinPackageRejection.encryptedEntry
        }

        let archive: Archive
        do {
            archive = try Archive(url: sourceURL, accessMode: .read)
        } catch {
            throw SkinPackageRejection.sourceUnavailable
        }

        let entries = Array(archive)
        guard entries.count == centralDirectory.entryCount else {
            throw SkinPackageRejection.unsupportedEntry
        }
        let descriptors = entries.map(Self.descriptor)
        let preflight = try SkinPackagePolicy.preflight(descriptors, limits: limits)
        try checkProcessing(start: start)

        let stagingURL = try store.makeStagingDirectory()
        var stagingWasPromoted = false
        defer {
            if !stagingWasPromoted { store.removeStagingDirectory(stagingURL) }
        }

        var extractionBudget = SkinExtractionBudget()
        let pathsByValue = Dictionary(
            uniqueKeysWithValues: preflight.files.map { ($0.value, $0) }
        )
        for entry in entries {
            try checkProcessing(start: start)
            switch entry.type {
            case .directory:
                let path = try CanonicalSkinPath(entry.path, kind: .directory, limits: limits)
                let destination = try containedDestination(for: path, beneath: stagingURL)
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            case .symlink:
                throw SkinPackageRejection.symbolicLink
            case .file:
                guard let path = pathsByValue[
                    try CanonicalSkinPath(entry.path, kind: .file, limits: limits).value
                ] else { throw SkinPackageRejection.invalidPath }
                let destination = try containedDestination(for: path, beneath: stagingURL)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard fileManager.createFile(atPath: destination.path, contents: nil) else {
                    throw SkinPackageRejection.extractionFailed
                }
                let handle: FileHandle
                do {
                    handle = try FileHandle(forWritingTo: destination)
                } catch {
                    throw SkinPackageRejection.extractionFailed
                }
                defer { try? handle.close() }
                do {
                    _ = try archive.extract(
                        entry,
                        bufferSize: 64 * 1024,
                        skipCRC32: false,
                        consumer: { chunk in
                            try checkProcessing(start: start)
                            try extractionBudget.record(chunk.count, for: path, limits: limits)
                            try handle.write(contentsOf: chunk)
                            try checkProcessing(start: start)
                        }
                    )
                } catch let rejection as SkinPackageRejection {
                    throw rejection
                } catch {
                    throw SkinPackageRejection.extractionFailed
                }
            }
            try checkProcessing(start: start)
        }

        let candidate = try validateCandidate(at: stagingURL, extractedFiles: Set(preflight.files))
        try checkProcessing(start: start)
        let digest = try contentDigest(root: stagingURL, files: preflight.files)
        let promotion = try store.preparePromotion(
            stagingURL: stagingURL,
            identifier: candidate.reference.identifier,
            digest: digest
        )
        stagingWasPromoted = true
        let managedURL: URL = switch promotion.outcome {
        case let .imported(url), let .unchanged(url): url
        }
        do {
            let managedAppearance = try validateManagedCandidate(at: managedURL)
            let managedFiles = try regularPackageFiles(at: managedURL)
            let managedDigest = try contentDigest(root: managedURL, files: managedFiles)
            guard managedAppearance.reference.identifier == candidate.reference.identifier,
                  managedDigest == digest
            else { throw SkinPackageRejection.storageFailed }
            try store.commit(promotion)
            return (promotion.outcome, managedAppearance)
        } catch {
            do {
                try store.rollback(promotion)
            } catch {
                throw SkinPackageRejection.storageFailed
            }
            if let rejection = error as? SkinPackageRejection {
                throw rejection
            }
            throw SkinPackageRejection.storageFailed
        }
    }

    func loadManagedAppearances() -> [ValidatedSkinAppearance] {
        store.migrateLegacyPackagesIfNeeded()
        store.managedPackageURLs().compactMap { try? validateManagedCandidate(at: $0) }
    }

    private func validateCandidate(
        at root: URL,
        extractedFiles: Set<CanonicalSkinPath>
    ) throws -> ValidatedSkinAppearance {
        let manifestPath = try CanonicalSkinPath("manifest.json", kind: .file, limits: limits)
        let manifestURL = try containedDestination(for: manifestPath, beneath: root)
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        } catch {
            throw SkinPackageRejection.manifestMissing
        }
        try SkinPackagePolicy.validateManifestByteCount(UInt64(manifestData.count), limits: limits)

        let appearance: ValidatedSkinAppearance
        do {
            appearance = try SkinManifestValidator.validate(
                manifestData,
                classification: .imported,
                assetResolver: { path in
                    guard let canonical = try? CanonicalSkinPath(path, kind: .file, limits: limits),
                          extractedFiles.contains(canonical),
                          let destination = try? containedDestination(for: canonical, beneath: root),
                          fileManager.fileExists(atPath: destination.path)
                    else { return nil }
                    return destination
                }
            )
        } catch SkinManifestValidationError.unsupportedSchema {
            throw SkinPackageCompatibilityFailure.unsupportedSchema
        } catch {
            throw SkinPackageRejection.invalidManifest
        }

        let referenced = try referencedAssetPaths(in: manifestData)
        let allowed = referenced.union([manifestPath])
        guard extractedFiles == allowed else { throw SkinPackageRejection.unexpectedFile }
        for asset in referenced {
            try validateImage(at: containedDestination(for: asset, beneath: root), path: asset)
        }
        return appearance
    }

    private func validateManagedCandidate(at root: URL) throws -> ValidatedSkinAppearance {
        guard store.managedPackageURLs().contains(root.standardizedFileURL) else {
            throw SkinPackageRejection.storageFailed
        }
        let files = try regularPackageFiles(at: root)
        return try validateCandidate(at: root, extractedFiles: Set(files))
    }

    func validateManagedPackage(at root: URL) throws -> ValidatedSkinAppearance {
        try validateManagedCandidate(at: root)
    }

    private func regularPackageFiles(at root: URL) throws -> [CanonicalSkinPath] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { throw SkinPackageRejection.storageFailed }
        var files: [CanonicalSkinPath] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw SkinPackageRejection.symbolicLink }
            guard values.isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            files.append(try CanonicalSkinPath(relative, kind: .file, limits: limits))
        }
        return files
    }

    private func referencedAssetPaths(in manifestData: Data) throws -> Set<CanonicalSkinPath> {
        guard let manifest = try? JSONDecoder().decode(SkinManifest.self, from: manifestData) else {
            throw SkinPackageRejection.invalidManifest
        }
        let rawPaths = [manifest.backgroundAsset, manifest.metadataPanelAsset].compactMap { $0 }
        do {
            return Set(try rawPaths.map { try CanonicalSkinPath($0, kind: .file, limits: limits) })
        } catch {
            throw SkinPackageRejection.invalidAssetReference
        }
    }

    private func validateImage(at url: URL, path: CanonicalSkinPath) throws {
        let extensionName = URL(fileURLWithPath: path.value).pathExtension
        guard ["png", "jpg", "jpeg"].contains(extensionName) else {
            throw SkinPackageRejection.unsupportedImageType
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let typeIdentifier = CGImageSourceGetType(source)
        else { throw SkinPackageRejection.unsupportedImageType }
        let detectedType = UTType(typeIdentifier as String)
        let expectedType: UTType = extensionName == "png" ? .png : .jpeg
        guard detectedType == expectedType else {
            throw SkinPackageRejection.unsupportedImageType
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw SkinPackageRejection.invalidImageFrameCount
        }
        guard CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        ) != nil else {
            throw SkinPackageRejection.unsupportedImageType
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.uint64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.uint64Value
        else { throw SkinPackageRejection.invalidImageDimensions }
        try SkinPackagePolicy.validateImageDimensions(width: width, height: height, limits: limits)
    }

    private func contentDigest(root: URL, files: [CanonicalSkinPath]) throws -> String {
        var hasher = SHA256()
        for path in files.sorted(by: { $0.value < $1.value }) {
            hasher.update(data: Data(path.value.utf8))
            hasher.update(data: Data([0]))
            let url = try containedDestination(for: path, beneath: root)
            do {
                hasher.update(data: try Data(contentsOf: url, options: [.mappedIfSafe]))
            } catch {
                throw SkinPackageRejection.extractionFailed
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func containedDestination(for path: CanonicalSkinPath, beneath root: URL) throws -> URL {
        let standardizedRoot = root.standardizedFileURL
        let candidate = path.components.reduce(standardizedRoot) {
            $0.appendingPathComponent($1, isDirectory: false)
        }.standardizedFileURL
        let rootPrefix = standardizedRoot.path.hasSuffix("/")
            ? standardizedRoot.path
            : standardizedRoot.path + "/"
        guard candidate.path.hasPrefix(rootPrefix), candidate.path != standardizedRoot.path else {
            throw SkinPackageRejection.invalidPath
        }
        return candidate
    }

    private func checkProcessing(start: UInt64) throws {
        try SkinPackagePolicy.checkProcessing(
            cancelled: Task.isCancelled,
            startNanoseconds: start,
            nowNanoseconds: nowNanoseconds(),
            limits: limits
        )
    }

    private static func descriptor(_ entry: Entry) -> SkinArchiveEntryDescriptor {
        let kind: SkinArchiveEntryKind = switch entry.type {
        case .file: .file
        case .directory: .directory
        case .symlink: .symbolicLink
        }
        return SkinArchiveEntryDescriptor(
            path: entry.path,
            kind: kind,
            compressedSize: entry.compressedSize,
            uncompressedSize: entry.uncompressedSize,
            isEncrypted: false
        )
    }
}

private struct ZIPCentralDirectorySummary: Sendable {
    let entryCount: Int
    let containsEncryptedEntry: Bool
}

/// ZIPFoundation intentionally hides encryption flags and does not construct
/// public entries for encrypted records. This bounded preflight reads only the
/// central-directory envelope needed to keep those records from disappearing
/// before Sirius Mac's closed policy sees them; ZIPFoundation still owns entry
/// decoding and all extraction mechanics.
private enum ZIPCentralDirectoryInspector {
    private static let endSignature: UInt32 = 0x0605_4b50
    private static let entrySignature: UInt32 = 0x0201_4b50
    private static let maximumCommentBytes = 65_535

    static func inspect(_ data: Data) throws -> ZIPCentralDirectorySummary {
        guard data.count >= 22,
              let endOffset = findEndRecord(in: data)
        else { throw SkinPackageRejection.sourceUnavailable }

        let diskNumber = try uint16(data, at: endOffset + 4)
        let directoryDisk = try uint16(data, at: endOffset + 6)
        let diskEntries = try uint16(data, at: endOffset + 8)
        let totalEntries = try uint16(data, at: endOffset + 10)
        let directorySize = try uint32(data, at: endOffset + 12)
        let directoryOffset = try uint32(data, at: endOffset + 16)
        let commentLength = try uint16(data, at: endOffset + 20)

        guard diskNumber == 0,
              directoryDisk == 0,
              diskEntries == totalEntries,
              totalEntries != UInt16.max,
              directorySize != UInt32.max,
              directoryOffset != UInt32.max,
              endOffset + 22 + Int(commentLength) == data.count
        else { throw SkinPackageRejection.unsupportedEntry }

        let start = Int(directoryOffset)
        let size = Int(directorySize)
        let end = start.addingReportingOverflow(size)
        guard !end.overflow,
              start >= 0,
              end.partialValue <= endOffset,
              end.partialValue <= data.count
        else { throw SkinPackageRejection.sourceUnavailable }

        var cursor = start
        var containsEncryptedEntry = false
        for _ in 0..<Int(totalEntries) {
            guard try uint32(data, at: cursor) == entrySignature else {
                throw SkinPackageRejection.sourceUnavailable
            }
            let flags = try uint16(data, at: cursor + 8)
            containsEncryptedEntry = containsEncryptedEntry || (flags & 0x0001) != 0
            let nameLength = Int(try uint16(data, at: cursor + 28))
            let extraLength = Int(try uint16(data, at: cursor + 30))
            let entryCommentLength = Int(try uint16(data, at: cursor + 32))
            let variableLength = nameLength
                .addingReportingOverflow(extraLength)
            guard !variableLength.overflow else { throw SkinPackageRejection.arithmeticOverflow }
            let allVariable = variableLength.partialValue
                .addingReportingOverflow(entryCommentLength)
            guard !allVariable.overflow else { throw SkinPackageRejection.arithmeticOverflow }
            let recordLength = 46.addingReportingOverflow(allVariable.partialValue)
            guard !recordLength.overflow else { throw SkinPackageRejection.arithmeticOverflow }
            let next = cursor.addingReportingOverflow(recordLength.partialValue)
            guard !next.overflow, next.partialValue <= end.partialValue else {
                throw SkinPackageRejection.sourceUnavailable
            }
            cursor = next.partialValue
        }
        guard cursor == end.partialValue else { throw SkinPackageRejection.sourceUnavailable }
        return ZIPCentralDirectorySummary(
            entryCount: Int(totalEntries),
            containsEncryptedEntry: containsEncryptedEntry
        )
    }

    private static func findEndRecord(in data: Data) -> Int? {
        let lowerBound = max(0, data.count - (22 + maximumCommentBytes))
        guard data.count >= 4 else { return nil }
        for offset in stride(from: data.count - 4, through: lowerBound, by: -1) {
            if (try? uint32(data, at: offset)) == endSignature {
                return offset
            }
        }
        return nil
    }

    private static func uint16(_ data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            throw SkinPackageRejection.sourceUnavailable
        }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw SkinPackageRejection.sourceUnavailable
        }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

actor SkinImportCoordinator {
    typealias ImportOperation = @Sendable (URL) throws -> (
        ManagedSkinStore.PromotionOutcome,
        ValidatedSkinAppearance
    )

    private let importOperation: ImportOperation
    private let appearanceController: SkinAppearanceController
    private var requestGeneration = 0
    private var transactionActive = false
    private var waitingOrder: [UUID] = []
    private var waiting: [UUID: CheckedContinuation<Void, any Error>] = [:]

    init(
        importer: SkinPackageImporter,
        appearanceController: SkinAppearanceController
    ) {
        importOperation = { sourceURL in
            try importer.importPackage(at: sourceURL)
        }
        self.appearanceController = appearanceController
    }

    init(
        importOperation: @escaping ImportOperation,
        appearanceController: SkinAppearanceController
    ) {
        self.importOperation = importOperation
        self.appearanceController = appearanceController
    }

    func importAndSelect(_ sourceURL: URL) async throws -> SkinImportResult {
        requestGeneration += 1
        let generation = requestGeneration

        try await acquireTransaction()
        defer { releaseTransaction() }
        guard !Task.isCancelled else { throw SkinPackageRejection.cancelled }

        let (promotion, appearance) = try importOperation(sourceURL)
        let selected: Bool
        if generation == requestGeneration, !Task.isCancelled {
            let authority = await appearanceController.beginImportedSelection(generation: generation)
            if generation == requestGeneration, !Task.isCancelled {
                selected = await appearanceController.commitImportedSelection(
                    appearance,
                    generation: generation,
                    authority: authority
                )
            } else {
                await appearanceController.registerImported(appearance)
                selected = false
            }
        } else {
            await appearanceController.registerImported(appearance)
            selected = false
        }
        let outcome: SkinImportResult.StorageOutcome = switch promotion {
        case .imported: .imported
        case .unchanged: .unchanged
        }
        return SkinImportResult(
            storageOutcome: outcome,
            appearance: appearance,
            selected: selected
        )
    }

    func removeImportedSkin(_ reference: SkinSelectionReference) async throws -> Bool {
        try await acquireTransaction()
        defer { releaseTransaction() }
        guard !Task.isCancelled else { throw SkinPackageRejection.cancelled }
        return await appearanceController.removeImportedSkin(reference)
    }

    private func acquireTransaction() async throws {
        guard transactionActive else {
            transactionActive = true
            return
        }

        let identifier = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: SkinPackageRejection.cancelled)
                    return
                }
                waitingOrder.append(identifier)
                waiting[identifier] = continuation
            }
        } onCancel: {
            Task { await self.cancelWaitingTransaction(identifier) }
        }
    }

    private func cancelWaitingTransaction(_ identifier: UUID) {
        waitingOrder.removeAll { $0 == identifier }
        waiting.removeValue(forKey: identifier)?.resume(
            throwing: SkinPackageRejection.cancelled
        )
    }

    private func releaseTransaction() {
        while let identifier = waitingOrder.first {
            waitingOrder.removeFirst()
            if let continuation = waiting.removeValue(forKey: identifier) {
                continuation.resume()
                return
            }
        }
        transactionActive = false
    }
}
