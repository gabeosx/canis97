import Foundation

private enum PolicyTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): message
        }
    }
}

private var assertionCount = 0

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    assertionCount += 1
    guard condition() else { throw PolicyTestFailure.assertion(message) }
}

private func expectRejection(
    _ expected: SkinPackageRejection,
    _ message: String,
    operation: () throws -> Void
) throws {
    assertionCount += 1
    do {
        try operation()
        throw PolicyTestFailure.assertion("Expected \(expected): \(message)")
    } catch let actual as SkinPackageRejection {
        guard actual == expected else {
            throw PolicyTestFailure.assertion("Expected \(expected), got \(actual): \(message)")
        }
    }
}

private func file(
    _ path: String,
    compressed: UInt64 = 1,
    expanded: UInt64 = 1,
    encrypted: Bool = false
) -> SkinArchiveEntryDescriptor {
    SkinArchiveEntryDescriptor(
        path: path,
        kind: .file,
        compressedSize: compressed,
        uncompressedSize: expanded,
        isEncrypted: encrypted
    )
}

private func directory(_ path: String) -> SkinArchiveEntryDescriptor {
    SkinArchiveEntryDescriptor(path: path, kind: .directory)
}

private func preflight(_ additions: [SkinArchiveEntryDescriptor]) throws -> SkinPackagePreflight {
    try SkinPackagePolicy.preflight([file("manifest.json")] + additions)
}

private func limits(
    archive: UInt64 = .max,
    expanded: UInt64 = .max,
    entries: Int = .max,
    file: UInt64 = .max,
    manifest: UInt64 = .max,
    ratio: UInt64 = .max,
    dimension: UInt64 = .max,
    pixels: UInt64 = .max,
    components: Int = .max,
    pathBytes: Int = .max,
    deadline: UInt64 = .max
) -> SkinPackageLimits {
    SkinPackageLimits(
        archiveBytes: archive,
        expandedBytes: expanded,
        entryCount: entries,
        fileBytes: file,
        manifestBytes: manifest,
        compressionRatio: ratio,
        imageDimension: dimension,
        imagePixels: pixels,
        pathComponents: components,
        pathUTF8Bytes: pathBytes,
        deadlineNanoseconds: deadline
    )
}

private func runBoundaryMatrix() throws {
    let standard = SkinPackageLimits.standard

    try SkinPackagePolicy.validateArchiveSize(standard.archiveBytes)
    try expectRejection(.archiveTooLarge, "archive one byte over") {
        try SkinPackagePolicy.validateArchiveSize(standard.archiveBytes + 1)
    }

    let maximumEntries = [file("manifest.json")] + (1..<standard.entryCount).map {
        directory("d\($0)")
    }
    _ = try SkinPackagePolicy.preflight(maximumEntries)
    try expectRejection(.tooManyEntries, "entry count one over") {
        try SkinPackagePolicy.preflight(maximumEntries + [directory("overflow")])
    }

    _ = try CanonicalSkinPath(
        ["a", "b", "c", "d"].joined(separator: "/"),
        kind: .file
    )
    try expectRejection(.invalidPath, "path component count one over") {
        _ = try CanonicalSkinPath("a/b/c/d/e", kind: .file)
    }
    _ = try CanonicalSkinPath(String(repeating: "a", count: standard.pathUTF8Bytes), kind: .file)
    try expectRejection(.invalidPath, "UTF-8 path bytes one over") {
        _ = try CanonicalSkinPath(String(repeating: "a", count: standard.pathUTF8Bytes + 1), kind: .file)
    }

    for invalid in ["/absolute", "C:drive", "../escape", "a/../escape", "a/./b", "a//b", "a\\b", "a\0b"] {
        try expectRejection(.invalidPath, "invalid path \(invalid.debugDescription)") {
            _ = try CanonicalSkinPath(invalid, kind: .file)
        }
    }
    try expectRejection(.duplicatePath, "exact duplicate") {
        _ = try preflight([file("asset.png"), file("asset.png")])
    }
    try expectRejection(.pathCollision, "POSIX case-fold collision") {
        _ = try preflight([file("asset.png"), file("ASSET.PNG")])
    }
    try expectRejection(.pathCollision, "NFC-equivalent collision") {
        _ = try preflight([file("caf\u{00E9}.png"), file("cafe\u{0301}.png")])
    }
    try expectRejection(.pathPrefixConflict, "file used as directory prefix") {
        _ = try preflight([file("assets"), file("assets/image.png")])
    }

    try expectRejection(.encryptedEntry, "encrypted entry") {
        _ = try preflight([file("asset.png", encrypted: true)])
    }
    try expectRejection(.symbolicLink, "symbolic link") {
        _ = try preflight([SkinArchiveEntryDescriptor(path: "link", kind: .symbolicLink)])
    }
    try expectRejection(.unsupportedEntry, "unsupported kind") {
        _ = try preflight([SkinArchiveEntryDescriptor(path: "special", kind: .unsupported)])
    }

    _ = try preflight([file("maximum.bin", compressed: 83_887, expanded: standard.fileBytes)])
    try expectRejection(.fileTooLarge, "per-file bytes one over") {
        _ = try preflight([file("over.bin", compressed: 83_887, expanded: standard.fileBytes + 1)])
    }

    var exactExpanded = [SkinArchiveEntryDescriptor]()
    for index in 0..<7 {
        exactExpanded.append(file("f\(index).bin", compressed: 83_887, expanded: standard.fileBytes))
    }
    exactExpanded.append(
        file(
            "f7.bin",
            compressed: 83_886,
            expanded: standard.fileBytes - 1
        )
    )
    _ = try preflight(exactExpanded)
    try expectRejection(.packageTooLarge, "declared expanded total one over") {
        _ = try preflight(exactExpanded + [file("over.bin")])
    }

    _ = try preflight([file("ratio.bin", compressed: 1, expanded: standard.compressionRatio)])
    try expectRejection(.compressionRatioExceeded, "ratio one over") {
        _ = try preflight([file("ratio.bin", compressed: 1, expanded: standard.compressionRatio + 1)])
    }
    try expectRejection(.compressionRatioExceeded, "nonempty over zero compressed bytes") {
        _ = try preflight([file("ratio.bin", compressed: 0, expanded: 1)])
    }
    try expectRejection(.arithmeticOverflow, "ratio cross-product overflow") {
        _ = try SkinPackagePolicy.preflight(
            [file("manifest.json", compressed: UInt64.max, expanded: 1)],
            limits: limits(ratio: 2)
        )
    }

    try SkinPackagePolicy.validateManifestByteCount(standard.manifestBytes)
    try expectRejection(.manifestTooLarge, "manifest one byte over") {
        try SkinPackagePolicy.validateManifestByteCount(standard.manifestBytes + 1)
    }

    try SkinPackagePolicy.validateImageDimensions(
        width: standard.imageDimension,
        height: standard.imageDimension,
        limits: standard
    )
    try expectRejection(.invalidImageDimensions, "image width one over") {
        try SkinPackagePolicy.validateImageDimensions(
            width: standard.imageDimension + 1,
            height: 1,
            limits: standard
        )
    }
    try expectRejection(.invalidImageDimensions, "image pixel count one over") {
        try SkinPackagePolicy.validateImageDimensions(
            width: standard.imagePixels,
            height: 2,
            limits: limits(dimension: .max, pixels: standard.imagePixels)
        )
    }
    try expectRejection(.arithmeticOverflow, "image pixel multiplication overflow") {
        try SkinPackagePolicy.validateImageDimensions(
            width: UInt64.max,
            height: 2,
            limits: limits()
        )
    }

    let manifestPath = try CanonicalSkinPath("manifest.json", kind: .file)
    var budget = SkinExtractionBudget()
    try budget.record(Int(standard.fileBytes), for: manifestPath)
    try require(budget.byteCount(for: manifestPath) == standard.fileBytes, "exact streamed file maximum")
    try expectRejection(.fileTooLarge, "streamed file bytes one over") {
        try budget.record(1, for: manifestPath)
    }

    let small = limits(expanded: 2, file: 2, ratio: 100)
    let first = try CanonicalSkinPath("first", kind: .file, limits: small)
    let second = try CanonicalSkinPath("second", kind: .file, limits: small)
    var totalBudget = SkinExtractionBudget()
    try totalBudget.record(1, for: first, limits: small)
    try totalBudget.record(1, for: second, limits: small)
    try require(totalBudget.totalBytes == 2, "exact streamed total maximum")
    try expectRejection(.packageTooLarge, "streamed total one over") {
        try totalBudget.record(1, for: second, limits: small)
    }

    var overflowBudget = SkinExtractionBudget()
    let unbounded = limits()
    try overflowBudget.record(Int.max, for: manifestPath, limits: unbounded)
    try overflowBudget.record(Int.max, for: manifestPath, limits: unbounded)
    try expectRejection(.arithmeticOverflow, "streamed byte addition overflow") {
        try overflowBudget.record(2, for: manifestPath, limits: unbounded)
    }

    try SkinPackagePolicy.checkProcessing(
        cancelled: false,
        startNanoseconds: 1,
        nowNanoseconds: standard.deadlineNanoseconds
    )
    try expectRejection(.deadlineExceeded, "exact ten-second boundary rejects") {
        try SkinPackagePolicy.checkProcessing(
            cancelled: false,
            startNanoseconds: 1,
            nowNanoseconds: standard.deadlineNanoseconds + 1
        )
    }
    try expectRejection(.cancelled, "cancellation wins before deadline") {
        try SkinPackagePolicy.checkProcessing(
            cancelled: true,
            startNanoseconds: 0,
            nowNanoseconds: 0
        )
    }
    try expectRejection(.arithmeticOverflow, "non-monotonic injected clock") {
        try SkinPackagePolicy.checkProcessing(
            cancelled: false,
            startNanoseconds: 2,
            nowNanoseconds: 1
        )
    }
}

@main
private enum SkinPackagePolicyOfflineTests {
    static func main() {
        do {
            try runBoundaryMatrix()
            print("SkinPackagePolicyOfflineTests: PASS (\(assertionCount) assertions)")
        } catch {
            fputs("SkinPackagePolicyOfflineTests: FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
