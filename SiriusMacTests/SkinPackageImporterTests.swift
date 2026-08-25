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
