import Foundation

/// Standalone substitute for the managed-package lookup owned by the full app.
/// These persistence probes inject no managed packages and never touch app state.
struct ManagedSkinStore: Sendable {
    init(applicationSupportDirectory: URL) {}

    func validatedManagedPackageExists(identifier: String) -> Bool { false }
}

@main
struct SkinSelectionStoreOfflineTests {
    enum FixtureError: Error {
        case replacementFailed
    }

    static func main() async throws {
        try await run("all classifications round-trip exactly", testClassificationRoundTrips)
        try await run("same selection is a no-op", testSameSelectionIsIdempotent)
        try await run("failed replacement preserves durable selection", testReplacementFailureRollsBack)
        try await run("malformed and unsupported records recover to Native", testMalformedRecordsRecoverToNative)
        try await run("selection JSON contains metadata only", testMetadataOnlyRecord)
    }

    private static func testClassificationRoundTrips() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkinSelectionStore(applicationSupportDirectory: root)

        for classification in PersistedSkinClassification.allCases {
            let selection = PersistedSkinSelection(
                identifier: "fixture-\(classification.rawValue)",
                classification: classification
            )
            try expect(try await store.save(selection), equals: true)
            try expect(try await store.load(), equals: selection)
        }
    }

    private static func testSameSelectionIsIdempotent() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkinSelectionStore(applicationSupportDirectory: root)
        let selection = PersistedSkinSelection(identifier: "signal-glow", classification: .bundled)

        try expect(try await store.save(selection), equals: true)
        let recordURL = store.selectionFileURL
        let before = try recordIdentity(at: recordURL)
        try expect(try await store.save(selection), equals: false)
        let after = try recordIdentity(at: recordURL)

        try expect(after.number, equals: before.number)
        try expect(after.data, equals: before.data)
    }

    private static func testReplacementFailureRollsBack() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let liveStore = SkinSelectionStore(applicationSupportDirectory: root)
        let prior = PersistedSkinSelection(identifier: "signal-glow", classification: .bundled)
        try expect(try await liveStore.save(prior), equals: true)

        let live = SkinSelectionFileOperations.live
        let failing = SkinSelectionFileOperations(
            createDirectory: live.createDirectory,
            fileExists: live.fileExists,
            read: live.read,
            write: live.write,
            replace: { _, _ in throw FixtureError.replacementFailed },
            move: live.move,
            remove: live.remove
        )
        let failingStore = SkinSelectionStore(
            applicationSupportDirectory: root,
            fileOperations: failing
        )
        let candidate = PersistedSkinSelection(identifier: "fixture-imported", classification: .imported)

        do {
            _ = try await failingStore.save(candidate)
            throw TestFailure("expected replacement failure")
        } catch let error as SkinSelectionStoreError {
            try expect(error, equals: .writeFailed)
        }
        try expect(try await liveStore.load(), equals: prior)
    }

    private static func testMalformedRecordsRecoverToNative() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkinSelectionStore(applicationSupportDirectory: root)
        let recordURL = store.selectionFileURL
        try FileManager.default.createDirectory(
            at: recordURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let malformedRecords = [
            Data("not-json".utf8),
            Data(#"{"schemaVersion":1,"identifier":"fixture","classification":"unknown"}"#.utf8),
            Data(#"{"schemaVersion":2,"identifier":"fixture","classification":"bundled"}"#.utf8),
            Data(#"{"schemaVersion":1,"identifier":"fixture","classification":"bundled","extra":true}"#.utf8)
        ]

        for malformed in malformedRecords {
            try malformed.write(to: recordURL)
            try expect(await store.restoredSelectionOrNative(), equals: .native)
        }
        try FileManager.default.removeItem(at: recordURL)
        try expect(await store.restoredSelectionOrNative(), equals: .native)
    }

    private static func testMetadataOnlyRecord() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkinSelectionStore(applicationSupportDirectory: root)
        let selection = PersistedSkinSelection(identifier: "fixture-imported", classification: .imported)
        _ = try await store.save(selection)

        let data = try Data(contentsOf: store.selectionFileURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        try expect(Set(object?.keys.map { $0 } ?? []), equals: ["schemaVersion", "identifier", "classification"])
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sirius-selection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func recordIdentity(at url: URL) throws -> (number: NSNumber, data: Data) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let number = attributes[.systemFileNumber] as? NSNumber else {
            throw TestFailure("selection record has no stable file identity")
        }
        return (number, try Data(contentsOf: url))
    }

    private static func run(_ name: String, _ test: () async throws -> Void) async throws {
        try await test()
        print("PASS: \(name)")
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T) throws {
        guard actual == expected else {
            throw TestFailure("expected \(expected), got \(actual)")
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
