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

struct ManagedSkinStore: @unchecked Sendable {
    enum PromotionOutcome: Sendable {
        case imported(URL)
        case unchanged(URL)
    }

    let skinsRootURL: URL
    let stagingRootURL: URL
    let packagesRootURL: URL

    private let fileManager: FileManager

    init(
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let support = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        skinsRootURL = support
            .appendingPathComponent("Sirius Mac", isDirectory: true)
            .appendingPathComponent("Skins", isDirectory: true)
        stagingRootURL = skinsRootURL.appendingPathComponent(".staging", isDirectory: true)
        packagesRootURL = skinsRootURL.appendingPathComponent("Packages", isDirectory: true)
        self.fileManager = fileManager
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

    func promote(
        stagingURL: URL,
        identifier: SkinIdentifier,
        digest: String
    ) throws -> PromotionOutcome {
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
                return .unchanged(destination)
            }

            try fileManager.createDirectory(at: packagesRootURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                let backupName = ".backup-\(identifier.rawValue)-\(UUID().uuidString)"
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: stagingURL,
                    backupItemName: backupName,
                    options: [.usingNewMetadataOnly]
                )
                let backupURL = packagesRootURL.appendingPathComponent(backupName, isDirectory: true)
                try? fileManager.removeItem(at: backupURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destination)
            }
            return .imported(destination)
        } catch let rejection as SkinPackageRejection {
            throw rejection
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

    private func readDigest(at packageURL: URL) throws -> String? {
        let url = packageURL.appendingPathComponent(".content-digest", isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return String(data: try Data(contentsOf: url), encoding: .utf8)
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
        let archiveBytes = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            .map(UInt64.init) ?? 0
        try SkinPackagePolicy.validateArchiveSize(archiveBytes, limits: limits)

        let archive: Archive
        do {
            archive = try Archive(url: sourceURL, accessMode: .read)
        } catch {
            throw SkinPackageRejection.sourceUnavailable
        }

        let entries = Array(archive)
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
        let promotion = try store.promote(
            stagingURL: stagingURL,
            identifier: candidate.reference.identifier,
            digest: digest
        )
        stagingWasPromoted = true
        let managedURL: URL = switch promotion {
        case let .imported(url), let .unchanged(url): url
        }
        let managedAppearance = try validateManagedCandidate(at: managedURL)
        guard managedAppearance.reference.identifier == candidate.reference.identifier else {
            throw SkinPackageRejection.storageFailed
        }
        return (promotion, managedAppearance)
    }

    func loadManagedAppearances() -> [ValidatedSkinAppearance] {
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
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.uint64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.uint64Value,
              width > 0,
              height > 0,
              width <= limits.imageDimension,
              height <= limits.imageDimension
        else { throw SkinPackageRejection.invalidImageDimensions }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow, pixels.partialValue <= limits.imagePixels else {
            throw pixels.overflow ? SkinPackageRejection.arithmeticOverflow : SkinPackageRejection.invalidImageDimensions
        }
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

actor SkinImportCoordinator {
    private let importer: SkinPackageImporter
    private let appearanceController: SkinAppearanceController

    init(
        importer: SkinPackageImporter,
        appearanceController: SkinAppearanceController
    ) {
        self.importer = importer
        self.appearanceController = appearanceController
    }

    func importAndSelect(_ sourceURL: URL) async throws -> SkinImportResult {
        let (promotion, appearance) = try importer.importPackage(at: sourceURL)
        let selected = await appearanceController.registerImportedAndSelect(appearance)
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
}
