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

        XCTAssertFalse(await controller.commitImportedSelection(
            stale,
            generation: 1,
            authority: staleAuthority
        ))
        XCTAssertTrue(await controller.commitImportedSelection(
            current,
            generation: 2,
            authority: currentAuthority
        ))
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
}
