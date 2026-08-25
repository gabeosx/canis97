import Foundation

struct SkinPackageLimits: Equatable, Sendable {
    static let standard = Self(
        archiveBytes: 16 * 1024 * 1024,
        expandedBytes: 64 * 1024 * 1024,
        entryCount: 128,
        fileBytes: 8 * 1024 * 1024,
        manifestBytes: 64 * 1024,
        compressionRatio: 100,
        imageDimension: 4_096,
        imagePixels: 16_777_216,
        pathComponents: 4,
        pathUTF8Bytes: 240,
        deadlineNanoseconds: 10_000_000_000
    )

    let archiveBytes: UInt64
    let expandedBytes: UInt64
    let entryCount: Int
    let fileBytes: UInt64
    let manifestBytes: UInt64
    let compressionRatio: UInt64
    let imageDimension: UInt64
    let imagePixels: UInt64
    let pathComponents: Int
    let pathUTF8Bytes: Int
    let deadlineNanoseconds: UInt64
}

enum SkinArchiveEntryKind: Equatable, Sendable {
    case file
    case directory
    case symbolicLink
    case unsupported
}

struct CanonicalSkinPath: Hashable, Sendable {
    let value: String
    let comparisonKey: String
    let components: [String]

    init(
        _ untrustedPath: String,
        kind: SkinArchiveEntryKind,
        limits: SkinPackageLimits = .standard
    ) throws {
        guard !untrustedPath.isEmpty,
              !untrustedPath.hasPrefix("/"),
              !untrustedPath.contains("\\"),
              !untrustedPath.contains("\0"),
              !Self.hasDrivePrefix(untrustedPath)
        else { throw SkinPackageRejection.invalidPath }

        let pathWithoutDirectorySuffix: Substring
        if kind == .directory, untrustedPath.hasSuffix("/") {
            pathWithoutDirectorySuffix = untrustedPath.dropLast()
        } else {
            pathWithoutDirectorySuffix = Substring(untrustedPath)
        }
        guard !pathWithoutDirectorySuffix.isEmpty,
              !pathWithoutDirectorySuffix.hasSuffix("/")
        else { throw SkinPackageRejection.invalidPath }

        let rawComponents = pathWithoutDirectorySuffix.split(separator: "/", omittingEmptySubsequences: false)
        guard !rawComponents.isEmpty,
              rawComponents.count <= limits.pathComponents,
              rawComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw SkinPackageRejection.invalidPath }

        let normalizedComponents = rawComponents.map {
            String($0).precomposedStringWithCanonicalMapping
        }
        let canonicalValue = normalizedComponents.joined(separator: "/")
        guard canonicalValue.utf8.count <= limits.pathUTF8Bytes else {
            throw SkinPackageRejection.invalidPath
        }

        value = canonicalValue
        components = normalizedComponents
        comparisonKey = canonicalValue.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func hasDrivePrefix(_ path: String) -> Bool {
        let scalars = Array(path.unicodeScalars.prefix(2))
        guard scalars.count == 2, scalars[1] == ":" else { return false }
        return CharacterSet.letters.contains(scalars[0])
    }
}

struct SkinArchiveEntryDescriptor: Equatable, Sendable {
    let path: String
    let kind: SkinArchiveEntryKind
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let isEncrypted: Bool

    init(
        path: String,
        kind: SkinArchiveEntryKind,
        compressedSize: UInt64 = 0,
        uncompressedSize: UInt64 = 0,
        isEncrypted: Bool = false
    ) {
        self.path = path
        self.kind = kind
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.isEncrypted = isEncrypted
    }
}

enum SkinPackageRejection: Error, Equatable, Sendable {
    case sourceUnavailable
    case archiveTooLarge
    case tooManyEntries
    case invalidPath
    case duplicatePath
    case pathCollision
    case pathPrefixConflict
    case encryptedEntry
    case symbolicLink
    case unsupportedEntry
    case fileTooLarge
    case packageTooLarge
    case manifestMissing
    case manifestTooLarge
    case compressionRatioExceeded
    case arithmeticOverflow
    case extractionFailed
    case invalidManifest
    case invalidAssetReference
    case unexpectedFile
    case unsupportedImageType
    case invalidImageFrameCount
    case invalidImageDimensions
    case cancelled
    case deadlineExceeded
    case storageFailed
}

struct SkinPackagePreflight: Sendable {
    let files: [CanonicalSkinPath]
    let directories: [CanonicalSkinPath]
    let declaredExpandedBytes: UInt64
}

enum SkinPackagePolicy {
    static func validateArchiveSize(
        _ byteCount: UInt64,
        limits: SkinPackageLimits = .standard
    ) throws {
        guard byteCount <= limits.archiveBytes else {
            throw SkinPackageRejection.archiveTooLarge
        }
    }

    static func preflight(
        _ descriptors: [SkinArchiveEntryDescriptor],
        limits: SkinPackageLimits = .standard
    ) throws -> SkinPackagePreflight {
        guard descriptors.count <= limits.entryCount else {
            throw SkinPackageRejection.tooManyEntries
        }

        var canonicalEntries: [(path: CanonicalSkinPath, kind: SkinArchiveEntryKind)] = []
        var seenExact = Set<String>()
        var seenComparison = Set<String>()
        var files: [CanonicalSkinPath] = []
        var directories: [CanonicalSkinPath] = []
        var totalCompressed: UInt64 = 0
        var totalExpanded: UInt64 = 0

        for descriptor in descriptors {
            guard !descriptor.isEncrypted else { throw SkinPackageRejection.encryptedEntry }
            switch descriptor.kind {
            case .symbolicLink:
                throw SkinPackageRejection.symbolicLink
            case .unsupported:
                throw SkinPackageRejection.unsupportedEntry
            case .file, .directory:
                break
            }

            let path = try CanonicalSkinPath(descriptor.path, kind: descriptor.kind, limits: limits)
            guard seenExact.insert(path.value).inserted else {
                throw SkinPackageRejection.duplicatePath
            }
            guard seenComparison.insert(path.comparisonKey).inserted else {
                throw SkinPackageRejection.pathCollision
            }
            canonicalEntries.append((path, descriptor.kind))

            if descriptor.kind == .directory {
                directories.append(path)
                continue
            }

            guard descriptor.uncompressedSize <= limits.fileBytes else {
                throw SkinPackageRejection.fileTooLarge
            }
            try validateRatio(
                expanded: descriptor.uncompressedSize,
                compressed: descriptor.compressedSize,
                maximum: limits.compressionRatio
            )
            totalCompressed = try checkedAdd(totalCompressed, descriptor.compressedSize)
            totalExpanded = try checkedAdd(totalExpanded, descriptor.uncompressedSize)
            guard totalExpanded <= limits.expandedBytes else {
                throw SkinPackageRejection.packageTooLarge
            }
            files.append(path)
        }

        try validatePrefixConflicts(canonicalEntries)
        try validateRatio(
            expanded: totalExpanded,
            compressed: totalCompressed,
            maximum: limits.compressionRatio
        )
        guard files.contains(where: { $0.value == "manifest.json" }) else {
            throw SkinPackageRejection.manifestMissing
        }
        return SkinPackagePreflight(
            files: files,
            directories: directories,
            declaredExpandedBytes: totalExpanded
        )
    }

    static func validateManifestByteCount(
        _ byteCount: UInt64,
        limits: SkinPackageLimits = .standard
    ) throws {
        guard byteCount <= limits.manifestBytes else {
            throw SkinPackageRejection.manifestTooLarge
        }
    }

    static func validateImageDimensions(
        width: UInt64,
        height: UInt64,
        limits: SkinPackageLimits = .standard
    ) throws {
        guard width > 0,
              height > 0,
              width <= limits.imageDimension,
              height <= limits.imageDimension
        else { throw SkinPackageRejection.invalidImageDimensions }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow else { throw SkinPackageRejection.arithmeticOverflow }
        guard pixels.partialValue <= limits.imagePixels else {
            throw SkinPackageRejection.invalidImageDimensions
        }
    }

    static func checkProcessing(
        cancelled: Bool,
        startNanoseconds: UInt64,
        nowNanoseconds: UInt64,
        limits: SkinPackageLimits = .standard
    ) throws {
        guard !cancelled else { throw SkinPackageRejection.cancelled }
        guard nowNanoseconds >= startNanoseconds else {
            throw SkinPackageRejection.arithmeticOverflow
        }
        let elapsed = nowNanoseconds - startNanoseconds
        guard elapsed < limits.deadlineNanoseconds else {
            throw SkinPackageRejection.deadlineExceeded
        }
    }

    private static func validatePrefixConflicts(
        _ entries: [(path: CanonicalSkinPath, kind: SkinArchiveEntryKind)]
    ) throws {
        let files = Set(entries.filter { $0.kind == .file }.map(\.path.comparisonKey))
        for entry in entries {
            guard entry.path.components.count > 1 else { continue }
            for prefixLength in 1..<entry.path.components.count {
                let prefix = entry.path.components.prefix(prefixLength).joined(separator: "/")
                    .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                if files.contains(prefix) {
                    throw SkinPackageRejection.pathPrefixConflict
                }
            }
        }
    }

    private static func validateRatio(
        expanded: UInt64,
        compressed: UInt64,
        maximum: UInt64
    ) throws {
        guard expanded > 0 else { return }
        guard compressed > 0 else { throw SkinPackageRejection.compressionRatioExceeded }
        let product = compressed.multipliedReportingOverflow(by: maximum)
        guard !product.overflow else { throw SkinPackageRejection.arithmeticOverflow }
        guard expanded <= product.partialValue else {
            throw SkinPackageRejection.compressionRatioExceeded
        }
    }

    private static func checkedAdd(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw SkinPackageRejection.arithmeticOverflow }
        return result.partialValue
    }
}

struct SkinExtractionBudget: Sendable {
    private(set) var totalBytes: UInt64 = 0
    private var bytesByPath: [CanonicalSkinPath: UInt64] = [:]

    mutating func record(
        _ byteCount: Int,
        for path: CanonicalSkinPath,
        limits: SkinPackageLimits = .standard
    ) throws {
        guard byteCount >= 0 else { throw SkinPackageRejection.arithmeticOverflow }
        let count = UInt64(byteCount)
        let current = bytesByPath[path, default: 0]
        let nextFile = current.addingReportingOverflow(count)
        guard !nextFile.overflow else { throw SkinPackageRejection.arithmeticOverflow }
        guard nextFile.partialValue <= limits.fileBytes else {
            throw SkinPackageRejection.fileTooLarge
        }
        let nextTotal = totalBytes.addingReportingOverflow(count)
        guard !nextTotal.overflow else { throw SkinPackageRejection.arithmeticOverflow }
        guard nextTotal.partialValue <= limits.expandedBytes else {
            throw SkinPackageRejection.packageTooLarge
        }
        bytesByPath[path] = nextFile.partialValue
        totalBytes = nextTotal.partialValue
    }

    func byteCount(for path: CanonicalSkinPath) -> UInt64 {
        bytesByPath[path, default: 0]
    }
}
