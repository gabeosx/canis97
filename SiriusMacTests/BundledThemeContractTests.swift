import XCTest
@testable import Canis97

final class BundledThemeContractTests: XCTestCase {
    func testExpressiveBundledThemesHaveExactSharedCatalogContract() throws {
        XCTAssertEqual(
            SkinAppearanceCatalog.expressiveBundledResourceNames,
            ["PixelDesk", "PocketDisc", "AquaVista"]
        )

        let appearances = try SkinAppearanceCatalog.expressiveBundledResourceNames.map(bundledAppearance)
        XCTAssertEqual(
            appearances.map(\.displayName),
            ["Pixel Desk", "Pocket Disc", "Aqua Vista"]
        )
        XCTAssertEqual(
            appearances.map(\.layoutPlan.contentSize),
            [.init(width: 432, height: 304), .init(width: 384, height: 320), .init(width: 448, height: 304)]
        )
        XCTAssertEqual(
            appearances.map(\.layoutPlan.layoutVariant),
            [.desktopUtility, .discConsole, .aquaPod]
        )
        XCTAssertEqual(
            appearances.map(\.layoutPlan.silhouette),
            [.pixelNotched, .discPod, .bubbleCapsule]
        )
        XCTAssertEqual(
            appearances.map { $0.layoutPlan.slotFrames[.transport] },
            [.init(x: 224, y: 144, width: 144, height: 40), .init(x: 232, y: 148, width: 120, height: 48), .init(x: 244, y: 220, width: 136, height: 40)]
        )
        XCTAssertEqual(Set(appearances.map(\.reference.identifier.rawValue)).count, 3)
        XCTAssertTrue(appearances.allSatisfy { $0.reference.classification == .bundled })
    }

    func testExpressiveThemesRetainSemanticActionsAndNativeRecovery() throws {
        let source = try repositorySource("SiriusMac/Player/CompactPlayerView.swift")
        let catalog = SkinAppearanceCatalog.bundledCatalog()

        XCTAssertEqual(catalog.appearances.filter { $0.layoutPlan.isLegacy == false }.count, 3)
        XCTAssertEqual(ValidatedSkinAppearance.native.layoutPlan.contentSize, .init(width: 400, height: 288))
        XCTAssertTrue(source.contains("expressiveMaterialLayer"))
        XCTAssertFalse(source.contains("switch appearance.reference.classification"))
        for identifier in ["compact.favorite", "compact.transport.previous", "compact.transport.play-pause", "compact.transport.next", "compact.show-library", "compact.always-on-top", "compact.sign-out"] {
            XCTAssertTrue(source.contains(identifier))
        }
    }

    private func bundledAppearance(named name: String) throws -> ValidatedSkinAppearance {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try SkinManifestValidator.validate(
            Data(contentsOf: root.appendingPathComponent("SiriusMac/Skins/Bundled/\(name).json")),
            classification: .bundled
        )
    }

    private func repositorySource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
