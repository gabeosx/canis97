import Foundation
import XCTest
@testable import SiriusMac

@MainActor
final class SkinPackageImporterTests: XCTestCase {
    func testManagedRootsRemainUnderOneApplicationSupportSkinRoot() {
        let support = URL(fileURLWithPath: "/tmp/skin-import-contract", isDirectory: true)
        let store = ManagedSkinStore(applicationSupportDirectory: support)

        XCTAssertEqual(
            store.stagingRootURL.deletingLastPathComponent(),
            store.skinsRootURL
        )
        XCTAssertEqual(
            store.packagesRootURL.deletingLastPathComponent(),
            store.skinsRootURL
        )
        XCTAssertNotEqual(store.stagingRootURL, store.packagesRootURL)
    }

    func testImportedCatalogReplacementUsesOneReference() {
        let identifier = SkinIdentifier(rawValue: "creator.contract")!
        let first = importedAppearance(identifier: identifier, displayName: "First")
        let replacement = importedAppearance(identifier: identifier, displayName: "Replacement")

        let catalog = SkinAppearanceCatalog(appearances: [first]).inserting(replacement)

        XCTAssertEqual(catalog.appearances.filter { $0.reference == first.reference }.count, 1)
        XCTAssertEqual(catalog.resolve(first.reference)?.displayName, "Replacement")
    }

    func testSelectionPersistenceFailureKeepsPreviousConfirmedAppearance() async {
        enum InjectedFailure: Error { case write }
        let support = URL(fileURLWithPath: "/tmp/skin-import-selection-contract", isDirectory: true)
        let operations = SkinSelectionFileOperations(
            createDirectory: { _ in },
            fileExists: { _ in false },
            read: { _ in Data() },
            write: { _, _ in throw InjectedFailure.write },
            replace: { _, _ in },
            move: { _, _ in },
            remove: { _ in }
        )
        let selectionStore = SkinSelectionStore(
            applicationSupportDirectory: support,
            fileOperations: operations
        )
        let controller = SkinAppearanceController(
            catalog: .phaseOne,
            selectionStore: selectionStore
        )
        let imported = importedAppearance(
            identifier: SkinIdentifier(rawValue: "creator.rollback")!,
            displayName: "Rollback"
        )

        let selected = await controller.registerImportedAndSelect(imported)

        XCTAssertFalse(selected)
        XCTAssertEqual(controller.selectedReference, .native)
        XCTAssertEqual(controller.selectedAppearance, .native)
        XCTAssertEqual(controller.catalog.resolve(imported.reference), imported)
    }

    func testImportedSelectionAuthorityRejectsAStaleGeneration() async {
        let controller = SkinAppearanceController(catalog: .phaseOne)
        let stale = importedAppearance(
            identifier: SkinIdentifier(rawValue: "creator.stale")!,
            displayName: "Stale"
        )
        let current = importedAppearance(
            identifier: SkinIdentifier(rawValue: "creator.current")!,
            displayName: "Current"
        )

        let staleAuthority = controller.beginImportedSelection(generation: 1)
        let currentAuthority = controller.beginImportedSelection(generation: 2)

        let staleSelected = await controller.commitImportedSelection(
            stale,
            generation: 1,
            authority: staleAuthority
        )
        let currentSelected = await controller.commitImportedSelection(
            current,
            generation: 2,
            authority: currentAuthority
        )

        XCTAssertFalse(staleSelected)
        XCTAssertTrue(currentSelected)
        XCTAssertEqual(controller.selectedReference, current.reference)
        XCTAssertEqual(controller.catalog.resolve(stale.reference), stale)
    }

    func testStagingDirectoriesAreTransactionUnique() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ManagedSkinStore(applicationSupportDirectory: support)
        defer { try? FileManager.default.removeItem(at: support) }

        let first = try store.makeStagingDirectory()
        let second = try store.makeStagingDirectory()
        defer {
            store.removeStagingDirectory(first)
            store.removeStagingDirectory(second)
        }

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent(), store.stagingRootURL)
        XCTAssertEqual(second.deletingLastPathComponent(), store.stagingRootURL)
    }

    func testCancelledCoordinatorRequestDoesNotInvokeTransport() async {
        let probe = SynchronousImportProbe()
        let controller = SkinAppearanceController(catalog: .phaseOne)
        let appearance = importedAppearance(
            identifier: SkinIdentifier(rawValue: "creator.cancelled")!,
            displayName: "Cancelled"
        )
        let coordinator = SkinImportCoordinator(
            importOperation: { _ in
                probe.recordInvocation()
                return (.unchanged(URL(fileURLWithPath: "/managed")), appearance)
            },
            appearanceController: controller
        )

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await coordinator.importAndSelect(URL(fileURLWithPath: "/source.siriusskin"))
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled queued request must fail closed")
        } catch {
            XCTAssertEqual(error as? SkinPackageRejection, .cancelled)
        }
        XCTAssertEqual(probe.invocationCount, 0)
        XCTAssertEqual(controller.selectedReference, .native)
    }

    func testPromotionRollbackRestoresPriorManagedPackage() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ManagedSkinStore(applicationSupportDirectory: support)
        defer { try? FileManager.default.removeItem(at: support) }
        let identifier = SkinIdentifier(rawValue: "creator.rollback-package")!
        let destination = store.packagesRootURL
            .appendingPathComponent(identifier.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("marker"))
        try Data("old-digest".utf8).write(to: destination.appendingPathComponent(".content-digest"))
        let staging = try store.makeStagingDirectory()
        try Data("new".utf8).write(to: staging.appendingPathComponent("marker"))

        let transaction = try store.preparePromotion(
            stagingURL: staging,
            identifier: identifier,
            digest: "new-digest"
        )
        try store.rollback(transaction)

        let restored = try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8)
        XCTAssertEqual(restored, "old")
    }

    func testClosedPolicyCoversTransportEntryKindsAndCancellation() throws {
        XCTAssertThrowsError(
            try SkinPackagePolicy.preflight([
                SkinArchiveEntryDescriptor(
                    path: "manifest.json",
                    kind: .file,
                    compressedSize: 1,
                    uncompressedSize: 1
                ),
                SkinArchiveEntryDescriptor(path: "link", kind: .symbolicLink)
            ])
        ) { XCTAssertEqual($0 as? SkinPackageRejection, .symbolicLink) }

        XCTAssertThrowsError(
            try SkinPackagePolicy.checkProcessing(
                cancelled: true,
                startNanoseconds: 0,
                nowNanoseconds: 0
            )
        ) { XCTAssertEqual($0 as? SkinPackageRejection, .cancelled) }
    }

    func testSelectedImportedRemovalPersistsNativeBeforeDeleting() async {
        let events = RemovalEventProbe()
        let imported = importedAppearance(
            identifier: SkinIdentifier(rawValue: "creator.selected-removal")!,
            displayName: "Selected Removal"
        )
        let controller = SkinAppearanceController(
            catalog: SkinAppearanceCatalog(appearances: [imported]),
            initialReference: imported.reference,
            selectionStore: selectionStore(
                write: { data, _ in
                    let record = try JSONDecoder().decode(PersistedSkinSelection.self, from: data)
                    XCTAssertEqual(record, .native)
                    events.record("persist-native")
                }
            ),
            removeImportedPackage: { reference in
                XCTAssertEqual(reference, imported.reference)
                events.record("delete-package")
                return true
            }
        )

        let removed = await controller.removeImportedSkin(imported.reference)

        XCTAssertTrue(removed)
        XCTAssertEqual(events.values, ["persist-native", "delete-package"])
        XCTAssertEqual(controller.selectedReference, .native)
        XCTAssertNil(controller.catalog.resolve(imported.reference))
    }

    func testSelectedRemovalAbortsBeforeDeletionWhenNativePersistenceFails() async {
        enum InjectedFailure: Error { case write }
        let events = RemovalEventProbe()
        let imported = importedAppearance(
            identifier: SkinIdentifier(rawValue: "creator.failed-native")!,
            displayName: "Failed Native"
        )
        let controller = SkinAppearanceController(
            catalog: SkinAppearanceCatalog(appearances: [imported]),
            initialReference: imported.reference,
            selectionStore: selectionStore(write: { _, _ in throw InjectedFailure.write }),
            removeImportedPackage: { _ in
                events.record("delete-package")
                return true
            }
        )

        let removed = await controller.removeImportedSkin(imported.reference)

        XCTAssertFalse(removed)
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertEqual(controller.selectedReference, imported.reference)
        XCTAssertEqual(controller.catalog.resolve(imported.reference), imported)
    }

    func testDeletionFailureKeepsCatalogEntryAfterNativeConfirmation() async {
        enum InjectedFailure: Error { case delete }
        let imported = importedAppearance(
            identifier: SkinIdentifier(rawValue: "creator.failed-deletion")!,
            displayName: "Failed Deletion"
        )
        let controller = SkinAppearanceController(
            catalog: SkinAppearanceCatalog(appearances: [imported]),
            initialReference: imported.reference,
            selectionStore: selectionStore(),
            removeImportedPackage: { _ in throw InjectedFailure.delete }
        )

        let removed = await controller.removeImportedSkin(imported.reference)

        XCTAssertFalse(removed)
        XCTAssertEqual(controller.selectedReference, .native)
        XCTAssertEqual(controller.catalog.resolve(imported.reference), imported)
        XCTAssertEqual(controller.removalError, .storageFailed)
    }

    func testNonselectedRemovalAndRepeatAreIdempotent() async {
        let events = RemovalEventProbe()
        let imported = importedAppearance(
            identifier: SkinIdentifier(rawValue: "creator.repeat-removal")!,
            displayName: "Repeat Removal"
        )
        let controller = SkinAppearanceController(
            catalog: SkinAppearanceCatalog(appearances: [imported]),
            removeImportedPackage: { _ in
                events.record("delete-attempt")
                return events.values.count == 1
            }
        )

        XCTAssertTrue(await controller.removeImportedSkin(imported.reference))
        XCTAssertTrue(await controller.removeImportedSkin(imported.reference))
        XCTAssertEqual(events.values, ["delete-attempt", "delete-attempt"])
        XCTAssertEqual(controller.selectedReference, .native)
        XCTAssertNil(controller.catalog.resolve(imported.reference))
    }

    func testNativeAndBundledAppearancesArePermanent() async throws {
        let events = RemovalEventProbe()
        let bundled = try SkinManifestValidator.validate(
            manifestData(identifier: "bundled-permanent", displayName: "Bundled Permanent"),
            classification: .bundled
        )
        let controller = SkinAppearanceController(
            catalog: SkinAppearanceCatalog(appearances: [bundled]),
            removeImportedPackage: { _ in
                events.record("delete-package")
                return true
            }
        )

        XCTAssertFalse(await controller.removeImportedSkin(.native))
        XCTAssertFalse(await controller.removeImportedSkin(bundled.reference))
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertEqual(controller.availableAppearances.map(\.reference), [.native, bundled.reference])
    }

    private func importedAppearance(
        identifier: SkinIdentifier,
        displayName: String
    ) -> ValidatedSkinAppearance {
        ValidatedSkinAppearance(
            reference: SkinSelectionReference(identifier: identifier, classification: .imported),
            displayName: displayName,
            style: .fallback,
            cornerRadius: 4,
            backgroundAssetURL: nil,
            metadataPanelAssetURL: nil
        )
    }

    private func selectionStore(
        write: @escaping (Data, URL) throws -> Void = { _, _ in }
    ) -> SkinSelectionStore {
        SkinSelectionStore(
            applicationSupportDirectory: URL(fileURLWithPath: "/tmp/skin-removal-selection-contract"),
            fileOperations: SkinSelectionFileOperations(
                createDirectory: { _ in },
                fileExists: { _ in false },
                read: { _ in Data() },
                write: write,
                replace: { _, _ in },
                move: { _, _ in },
                remove: { _ in }
            )
        )
    }

    private func manifestData(identifier: String, displayName: String) -> Data {
        Data(
            #"""
            {
              "schemaVersion": 1,
              "identifier": "\#(identifier)",
              "displayName": "\#(displayName)",
              "playerBackground": "#101010",
              "metadataPanel": "#202020",
              "accent": "#C6FF00",
              "destructive": "#FF453A",
              "foregroundScheme": "dark",
              "contentPadding": 16,
              "sectionSpacing": 8,
              "cornerRadius": 4,
              "backgroundAsset": null,
              "metadataPanelAsset": null
            }
            """#.utf8
        )
    }
}

private final class SynchronousImportProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invocationCount: Int {
        lock.withLock { count }
    }

    func recordInvocation() {
        lock.withLock { count += 1 }
    }
}

private final class RemovalEventProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.withLock { storedValues }
    }

    func record(_ value: String) {
        lock.withLock { storedValues.append(value) }
    }
}
