import XCTest
@testable import Canis97

final class BundledThemeContractTests: XCTestCase {
    func testExpressiveBundledThemesHaveExactSharedCatalogContract() throws {
        XCTAssertEqual(
            SkinAppearanceCatalog.expressiveBundledResourceNames,
            ["PixelDesk", "PocketDisc", "AquaVista", "VintageCassetteDeck", "OrbitDeck", "SignalGarden", "Exit97", "QuartzDeck", "Abyssal97"]
        )

        let appearances = try SkinAppearanceCatalog.expressiveBundledResourceNames.map(bundledAppearance)
        XCTAssertEqual(
            appearances.map(\.displayName),
            ["Pixel Desk", "Pocket Disc", "Aqua Vista", "Vintage Cassette Deck", "Orbit Deck", "Signal Garden", "Exit 97", "Quartz Deck + Quartz Link", "Abyssal 97 — Living Ocean"]
        )
        XCTAssertEqual(
            appearances.map(\.layoutPlan.contentSize),
            [
                .init(width: 432, height: 304),
                .init(width: 384, height: 320),
                .init(width: 448, height: 360),
                .init(width: 432, height: 304),
                .init(width: 384, height: 320),
                .init(width: 448, height: 304),
                .init(width: 448, height: 360),
                .init(width: 448, height: 360),
                .init(width: 448, height: 360),
            ]
        )
        XCTAssertEqual(
            appearances.map(\.layoutPlan.layoutVariant),
            [.desktopUtility, .discConsole, .aquaPod, .desktopUtility, .discConsole, .aquaPod, .cinemaDeck, .cinemaDeck, .cinemaDeck]
        )
        XCTAssertEqual(
            appearances.map(\.layoutPlan.silhouette),
            [.pixelNotched, .discPod, .bubbleCapsule, .pixelNotched, .discPod, .bubbleCapsule, .wideCinema, .wideCinema, .wideCinema]
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
        XCTAssertEqual(appearances[3].layoutPlan.decorations.backdrop, "VintageCassetteFaceplate@2x.png")
        XCTAssertEqual(appearances[3].layoutPlan.slotFrames[.transport], .init(x: 272, y: 164, width: 128, height: 40))
        XCTAssertEqual(appearances[6].layoutPlan.decorations.backdrop, "Exit97Faceplate@2x.png")
        XCTAssertEqual(appearances[6].layoutPlan.slotFrames[.artwork], .init(x: 4, y: 256, width: 48, height: 48))
        XCTAssertEqual(appearances[6].layoutPlan.slotFrames[.channelIdentity], .init(x: 60, y: 256, width: 124, height: 24))
        XCTAssertEqual(appearances[6].layoutPlan.slotFrames[.metadata], .init(x: 60, y: 280, width: 164, height: 48))
        XCTAssertEqual(appearances[6].layoutPlan.slotFrames[.favorite], .init(x: 188, y: 248, width: 32, height: 32))
        XCTAssertEqual(appearances[6].layoutPlan.slotFrames[.status], .init(x: 264, y: 256, width: 136, height: 24))
        XCTAssertEqual(appearances[6].layoutPlan.slotFrames[.transport], .init(x: 264, y: 280, width: 136, height: 48))
        XCTAssertEqual(appearances[7].layoutPlan.decorations.backdrop, "QuartzDeckFaceplate@2x.png")
        XCTAssertEqual(appearances[7].layoutPlan.slotFrames[.metadata], .init(x: 92, y: 316, width: 156, height: 40))
        XCTAssertEqual(appearances[7].layoutPlan.slotFrames[.favorite], .init(x: 216, y: 284, width: 32, height: 32))
        XCTAssertEqual(appearances[7].layoutPlan.slotFrames[.transport], .init(x: 264, y: 316, width: 128, height: 40))
        XCTAssertEqual(Set(appearances.map(\.reference.identifier.rawValue)).count, 9)
        XCTAssertTrue(appearances.allSatisfy { $0.reference.classification == .bundled })
    }

    func testExpressiveThemesRetainSemanticActionsAndNativeRecovery() throws {
        let source = try repositorySource("SiriusMac/Player/CompactPlayerView.swift")
        let catalog = SkinAppearanceCatalog(appearances: try SkinAppearanceCatalog.expressiveBundledResourceNames.map(bundledAppearance))

        XCTAssertEqual(catalog.appearances.filter { $0.layoutPlan.isLegacy == false }.count, 9)
        XCTAssertEqual(ValidatedSkinAppearance.native.layoutPlan.contentSize, .init(width: 400, height: 288))
        XCTAssertTrue(source.contains("expressiveMaterialLayer"))
        XCTAssertTrue(source.contains("expressiveFaceplateLayer"))
        XCTAssertTrue(source.contains("hasExpressiveFaceplate"))
        XCTAssertTrue(source.contains("expressiveSlotAlignment"))
        XCTAssertTrue(source.contains("expressiveTransportControlCenters"))
        XCTAssertTrue(source.contains("usesQuartzReceiverGeometry"))
        XCTAssertTrue(source.contains(".position(x: semanticMetric(140), y: semanticMetric(21))"))
        XCTAssertTrue(source.contains("[CGPoint(x: 17, y: 21), CGPoint(x: 54, y: 21), CGPoint(x: 91, y: 21)]"))
        XCTAssertTrue(source.contains("usesQuartzReceiverGeometry ? \"Loading\" : \"Loading playback\""))
        XCTAssertTrue(source.contains("Text(\"Error\")"))
        XCTAssertTrue(source.contains("Button(\"Retry\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(recovery.title)"))
        XCTAssertTrue(source.contains("FaceplateGlyphView"))
        XCTAssertTrue(source.contains("BoundedMarqueeText"))
        XCTAssertTrue(source.contains(".compositingGroup()"))
        XCTAssertTrue(source.contains("TimelineView(.animation"))
        XCTAssertEqual(source.components(separatedBy: "TimelineView(.animation").count - 1, 1)
        XCTAssertTrue(source.contains("menuIndicator(.hidden)"))
        XCTAssertFalse(source.contains("switch appearance.reference.classification"))
        for identifier in ["compact.favorite", "compact.show-library", "compact.always-on-top", "compact.sign-out"] {
            XCTAssertTrue(source.contains(identifier))
        }
        XCTAssertTrue(source.contains(#".accessibilityIdentifier("compact.transport.\(accessibilityIdentifier(for: action))")"#))
        for (action, identifier) in [("previous", "previous"), ("playPause", "play-pause"), ("next", "next")] {
            XCTAssertTrue(source.contains("case .\(action): \"\(identifier)\""))
        }
    }

    func testLargeCinemaSkinsRenderSemanticsAtFinalPixelScaleWithoutChangingLogicalGeometry() throws {
        for name in ["Exit97", "QuartzDeck", "Abyssal97"] {
            let appearance = try bundledAppearance(named: name)
            XCTAssertEqual(appearance.layoutPlan.contentSize, .init(width: 448, height: 360))
            XCTAssertEqual(appearance.style.contentSize, appearance.layoutPlan.contentSize)
            XCTAssertEqual(appearance.layoutPlan.presentationScale, 1.5)
            XCTAssertEqual(appearance.layoutPlan.presentationSize, .init(width: 672, height: 540))
        }
        XCTAssertFalse(try bundledAppearance(named: "Exit97").layoutPlan.usesQuartzReceiverGeometry)
        XCTAssertTrue(try bundledAppearance(named: "QuartzDeck").layoutPlan.usesQuartzReceiverGeometry)
        for size in CompactSkinSizeVariant.allCases where size != .cinema448x360 {
            XCTAssertEqual(size.presentationScale, 1)
            XCTAssertEqual(size.presentationSize, size.contentSize)
        }
        let view = try repositorySource("SiriusMac/Player/CompactPlayerView.swift")
        XCTAssertTrue(view.contains(".scaleEffect(presentationScale, anchor: .topLeading)"))
        XCTAssertFalse(view.contains(".scaleEffect(renderingAppearance.layoutPlan.presentationScale, anchor: .topLeading)"))
        XCTAssertTrue(view.contains("width: plan.presentationSize.width, height: plan.presentationSize.height"))
        XCTAssertTrue(view.contains("width: semanticMetric(CGFloat(frame.width))"))
        XCTAssertTrue(view.contains("minimumInterval: 1.0 / 60.0"))
        let playerBody = try XCTUnwrap(view.components(separatedBy: "private struct BoundedMarqueeText").first)
        XCTAssertFalse(playerBody.contains("TimelineView(.animation"), "Marquee ticks must not rebuild the full player or reload its assets")
        XCTAssertTrue(view.contains("decorationImages[url]"))
        XCTAssertTrue(view.contains("@Environment(\\.displayScale) private var displayScale"))
        XCTAssertTrue(view.contains("(rawOffset * pixelScale).rounded() / pixelScale"))
        XCTAssertTrue(view.contains("width: renderingAppearance.layoutPlan.presentationSize.width"))
        XCTAssertTrue(view.contains("if !usesQuartzReceiverGeometry {\n                    surfaceBackground(.canvas)"))
        XCTAssertTrue(view.contains("// Quartz supplies its own RGBA silhouette"))
        let window = try repositorySource("SiriusMac/Windows/CompactWindowController.swift")
        XCTAssertTrue(window.contains("let size = appearance.layoutPlan.presentationSize"))
        XCTAssertTrue(window.contains("window.isMovableByWindowBackground = true"))
    }

    func testLargeCinemaRejectsArbitrarySizesZoomAndUnsafeSlots() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(repositorySource("SiriusMac/Skins/Bundled/QuartzDeck.json").utf8)) as? [String: Any])
        func validate(_ object: [String: Any]) throws -> ValidatedSkinAppearance {
            try SkinManifestValidator.validate(JSONSerialization.data(withJSONObject: object), classification: .bundled,
                assetResolver: { URL(fileURLWithPath: "/offline-fixture/\($0)") })
        }
        XCTAssertNoThrow(try validate(original))
        for (key, value) in [("size", "cinema672x540"), ("size", "custom"), ("layoutVariant", "aquaPod"), ("silhouette", "bubbleCapsule")] {
            var invalid = original
            invalid[key] = value
            XCTAssertThrowsError(try validate(invalid))
        }
        for value in [0, 1.5, 100] {
            var invalid = original
            invalid["presentationScale"] = value
            XCTAssertThrowsError(try validate(invalid))
        }
        var invalid = original
        var slots = try XCTUnwrap(original["slots"] as? [[String: Any]])
        slots[2]["frame"] = ["x":92, "y":320, "width":156, "height":40]
        invalid["slots"] = slots
        XCTAssertThrowsError(try validate(invalid)) // bottom focus clearance remains mandatory

        var legacy = original
        legacy["size"] = "cinema448x304"
        legacy["dragRegions"] = [["x":4, "y":4, "width":320, "height":20]]
        legacy["slots"] = try XCTUnwrap(original["slots"] as? [[String: Any]]).map { slot in
            var copy = slot
            var frame = slot["frame"] as! [String: Int]
            frame["y"]! -= 56
            copy["frame"] = frame
            return copy
        }
        let old = try validate(legacy)
        XCTAssertTrue(old.layoutPlan.usesQuartzReceiverGeometry)
        XCTAssertEqual(old.layoutPlan.presentationSize, .init(width: 448, height: 304))
    }

    func testQuartzTurntableReceivesClicksWithoutCoveringReceiverControls() throws {
        let plan = try bundledAppearance(named: "QuartzDeck").layoutPlan
        XCTAssertEqual(plan.dragRegions, [.init(x: 8, y: 4, width: 432, height: 276)])
        let drag = try XCTUnwrap(plan.dragRegions.first).cgRect
        for point in [CGPoint(x: 20, y: 20), CGPoint(x: 181.5, y: 132.5), CGPoint(x: 350, y: 180), CGPoint(x: 430, y: 270)] {
            XCTAssertTrue(drag.contains(point))
            let displayedDrag = CGRect(x: drag.minX * plan.presentationScale, y: drag.minY * plan.presentationScale,
                                       width: drag.width * plan.presentationScale, height: drag.height * plan.presentationScale)
            XCTAssertTrue(displayedDrag.contains(CGPoint(x: point.x * plan.presentationScale, y: point.y * plan.presentationScale)))
        }
        for slot in plan.slotFrames.values {
            XCTAssertFalse(drag.intersects(slot.cgRect))
        }
        let source = try repositorySource("SiriusMac/Player/CompactPlayerView.swift")
        XCTAssertTrue(source.contains(".frame(width: plan.presentationSize.width, height: plan.presentationSize.height, alignment: .topLeading)\n        .overlay(alignment: .topLeading)"))
        XCTAssertTrue(source.contains("Color.white.opacity(0.001)\n                    .frame(width: semanticMetric(CGFloat(drag.width)), height: semanticMetric(CGFloat(drag.height)))\n                    .contentShape(.rect)\n                    .gesture(WindowDragGesture())"))
        XCTAssertTrue(source.contains(".allowsWindowActivationEvents(true)\n                    .allowsHitTesting(true)"))
    }

    private func bundledAppearance(named name: String) throws -> ValidatedSkinAppearance {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try SkinManifestValidator.validate(
            Data(contentsOf: root.appendingPathComponent("SiriusMac/Skins/Bundled/\(name).json")),
            classification: .bundled,
            assetResolver: { path in
                let directory = root.appendingPathComponent("SiriusMac/Skins/Bundled")
                for relativePath in [path, "Assets/\(path)", "Assets/Exit97/\(path)", "Assets/QuartzDeck/\(path)", "Assets/Abyssal97/\(path)"] {
                    let candidate = directory.appendingPathComponent(relativePath)
                    if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                }
                return nil
            }
        )
    }

    private func repositorySource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
