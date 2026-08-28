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
        XCTAssertEqual(appearances[1].layoutPlan.slotFrames[.transport], .init(x: 200, y: 112, width: 136, height: 56))
        XCTAssertEqual(appearances[2].layoutPlan.slotFrames[.transport], .init(x: 188, y: 216, width: 176, height: 56))
        XCTAssertEqual(appearances[1].layoutPlan.slotFrames[.channelIdentity], .init(x: 140, y: 32, width: 160, height: 24))
        XCTAssertEqual(appearances[1].layoutPlan.slotFrames[.metadata], .init(x: 136, y: 56, width: 168, height: 48))
        XCTAssertEqual(appearances[1].layoutPlan.slotFrames[.status], .init(x: 32, y: 116, width: 88, height: 32))
        XCTAssertEqual(appearances[1].layoutPlan.slotFrames[.library], .init(x: 28, y: 252, width: 88, height: 40))
        XCTAssertEqual(appearances[1].layoutPlan.slotFrames[.overflowMenu], .init(x: 308, y: 252, width: 40, height: 40))
        XCTAssertEqual(appearances[2].layoutPlan.slotFrames[.status], .init(x: 28, y: 156, width: 152, height: 36))
        XCTAssertEqual(appearances[2].layoutPlan.slotFrames[.library], .init(x: 28, y: 244, width: 112, height: 40))
        XCTAssertEqual(appearances[2].layoutPlan.slotFrames[.overflowMenu], .init(x: 376, y: 228, width: 48, height: 52))
        XCTAssertEqual(appearances[1].layoutPlan.decorations.backdrop, "PocketDiscFaceplate@2x.png")
        XCTAssertEqual(appearances[2].layoutPlan.decorations.backdrop, "AquaVistaFaceplate@2x.png")
        XCTAssertEqual(Set(appearances.map(\.reference.identifier.rawValue)).count, 3)
        XCTAssertTrue(appearances.allSatisfy { $0.reference.classification == .bundled })
    }

    func testExpressiveThemesRetainSemanticActionsAndNativeRecovery() throws {
        let source = try repositorySource("SiriusMac/Player/CompactPlayerView.swift")
        let catalog = SkinAppearanceCatalog(appearances: try SkinAppearanceCatalog.expressiveBundledResourceNames.map(bundledAppearance))

        XCTAssertEqual(catalog.appearances.filter { $0.layoutPlan.isLegacy == false }.count, 3)
        XCTAssertEqual(ValidatedSkinAppearance.native.layoutPlan.contentSize, .init(width: 400, height: 288))
        XCTAssertTrue(source.contains("expressiveMaterialLayer"))
        XCTAssertTrue(source.contains("expressiveFaceplateLayer"))
        XCTAssertTrue(source.contains("hasExpressiveFaceplate"))
        XCTAssertTrue(source.contains("expressiveSlotAlignment"))
        XCTAssertTrue(source.contains("expressiveTransportControlCenters"))
        XCTAssertTrue(source.contains("FaceplateGlyphView"))
        XCTAssertTrue(source.contains("BoundedMarqueeText"))
        XCTAssertTrue(source.contains(".compositingGroup()"))
        XCTAssertTrue(source.contains("TimelineView(.animation"))
        XCTAssertEqual(source.components(separatedBy: "TimelineView(.animation").count - 1, 1)
        XCTAssertTrue(source.contains("menuIndicator(.hidden)"))
        XCTAssertFalse(source.contains("switch appearance.reference.classification"))
        for identifier in ["compact.favorite", "compact.transport.previous", "compact.transport.play-pause", "compact.transport.next", "compact.show-library", "compact.always-on-top", "compact.sign-out"] {
            XCTAssertTrue(source.contains(identifier))
        }
    }

    private func bundledAppearance(named name: String) throws -> ValidatedSkinAppearance {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try SkinManifestValidator.validate(
            Data(contentsOf: root.appendingPathComponent("SiriusMac/Skins/Bundled/\(name).json")),
            classification: .bundled,
            assetResolver: { path in
                let candidate = root.appendingPathComponent("SiriusMac/Skins/Bundled/Assets/\(path)")
                return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
            }
        )
    }

    private func repositorySource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
