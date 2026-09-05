import AppKit
import XCTest
@testable import Canis97

final class BundledAnimatedSkinTests: XCTestCase {
    func testOrbitDeckIsAnOrdinaryValidatedSchemaFourPackage() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../SiriusMac/Skins/Bundled").standardized
        let manifest = try Data(contentsOf: directory.appendingPathComponent("OrbitDeck.json"))
        let appearance = try SkinManifestValidator.validate(manifest, classification: .bundled, assetResolver: { path in
            let candidate = directory.appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        })
        XCTAssertEqual(appearance.motion?.format, .canis97)
        XCTAssertEqual(appearance.motion?.documentURL.lastPathComponent, "OrbitDeck.motion.json")
    }

    func testExit97ResolvesItsBoundedLocalSpriteScene() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../SiriusMac/Skins/Bundled")
            .standardized
        let manifest = try Data(contentsOf: directory.appendingPathComponent("Exit97.json"))
        let appearance = try SkinManifestValidator.validate(
            manifest,
            classification: .bundled,
            assetResolver: { path in Self.resolve(path, beneath: directory) }
        )
        let motion = try XCTUnwrap(appearance.motion)
        XCTAssertEqual(motion.format, .canis97)
        XCTAssertEqual(motion.documentURL.lastPathComponent, "Exit97.motion.json")
        XCTAssertEqual(motion.spriteSceneURL?.lastPathComponent, "Exit97.scene.json")
        XCTAssertLessThanOrEqual(motion.spriteAssetURLs.count, 24)

        let sceneURL = try XCTUnwrap(motion.spriteSceneURL)
        let scene = try SpriteMotionSceneCodec.decode(
            Data(contentsOf: sceneURL),
            allowedAssets: Set(motion.spriteAssetURLs.keys)
        )
        XCTAssertEqual(scene.canvas, .init(width: 448, height: 360))
        XCTAssertEqual(scene.formatVersion, 2)
        XCTAssertTrue(scene.encounterGroups.isEmpty)
        XCTAssertEqual(scene.director?.seed, 97)
        XCTAssertEqual(scene.performances?.count, 15)
        XCTAssertNil(scene.layers.first { $0.identifier == "roadster" }?.timeline)
        XCTAssertNil(scene.layers.first { $0.identifier == "night_world" }?.timeline)
        XCTAssertFalse(scene.layers.contains { $0.identifier == "canopy_light" })
        XCTAssertEqual(Set(scene.performances?.compactMap(\.event) ?? []),
            [.songFavoriteAdded, .songFavoriteRemoved, .channelFavoriteAdded, .channelFavoriteRemoved, .channelChanged])

        XCTAssertEqual(appearance.layoutPlan.presentationScale, 1.5)
        XCTAssertEqual(appearance.layoutPlan.presentationSize, .init(width: 672, height: 540))
        let plate = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: motion.staticPoseURL)))
        XCTAssertEqual(plate.pixelsWide, 1_344)
        XCTAssertEqual(plate.pixelsHigh, 1_080)
        let sceneAsset = try XCTUnwrap(motion.spriteAssetURLs["Exit97Environment@2x.png"])
        let sceneBitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: sceneAsset)))
        XCTAssertEqual(sceneBitmap.pixelsWide, 1_344)
        XCTAssertEqual(sceneBitmap.pixelsHigh, 684)
        let rigAsset = try XCTUnwrap(motion.spriteAssetURLs["Exit97CruiseRig.png"])
        let rigBitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: rigAsset)))
        XCTAssertEqual(rigBitmap.pixelsWide, 2880)
        XCTAssertEqual(rigBitmap.pixelsHigh, 960)

    }

    func testQuartzDeckResolvesItsApprovedBoundedSpriteRig() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../SiriusMac/Skins/Bundled")
            .standardized
        let manifest = try Data(contentsOf: directory.appendingPathComponent("QuartzDeck.json"))
        let appearance = try SkinManifestValidator.validate(
            manifest,
            classification: .bundled,
            assetResolver: { path in Self.resolve(path, beneath: directory) }
        )
        let motion = try XCTUnwrap(appearance.motion)
        XCTAssertEqual(motion.documentURL.lastPathComponent, "QuartzDeck.motion.json")
        XCTAssertEqual(motion.spriteSceneURL?.lastPathComponent, "QuartzDeck.scene.json")
        XCTAssertEqual(motion.spriteAssetURLs.count, 3)

        let scene = try SpriteMotionSceneCodec.decode(
            Data(contentsOf: try XCTUnwrap(motion.spriteSceneURL)),
            allowedAssets: Set(motion.spriteAssetURLs.keys)
        )
        XCTAssertEqual(scene.canvas, .init(width: 448, height: 360))
        XCTAssertEqual(scene.encounterGroups, [])
        XCTAssertEqual(scene.layers.first?.frame, .init(x: 133, y: 84, width: 97, height: 97))
        XCTAssertEqual(scene.layers.first?.timeline?.last?.time, 1.8)
        XCTAssertEqual(
            Set(scene.layers.compactMap(\.event)),
            [.songFavoriteAdded, .songFavoriteRemoved, .channelFavoriteAdded, .channelFavoriteRemoved]
        )
        XCTAssertEqual(scene.layers.first { $0.role == .persistentSongFavorite }?.frame, .init(x: 212, y: 317, width: 40, height: 40))
        XCTAssertEqual(scene.layers.first { $0.role == .persistentChannelFavorite }?.frame, .init(x: 212, y: 284, width: 40, height: 40))
        let frame = try XCTUnwrap(scene.layers.first?.frame.cgRect)
        XCTAssertEqual(frame.midX, 181.5)
        XCTAssertEqual(frame.midY, 132.5)
        let labelURL = try XCTUnwrap(motion.spriteAssetURLs["QuartzDeckSceneLabel@2x.png"])
        let label = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: labelURL)))
        XCTAssertEqual(label.pixelsWide, 291)
        XCTAssertEqual(label.pixelsHigh, 291)
        XCTAssertEqual(CGFloat(label.pixelsWide) / frame.width, 3)
        XCTAssertEqual(CGFloat(label.pixelsHigh) / frame.height, 3)
        let plate = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: motion.staticPoseURL)))
        XCTAssertEqual(plate.pixelsWide, 1344)
        XCTAssertEqual(plate.pixelsHigh, 1080)
        XCTAssertTrue(plate.hasAlpha)
        for (x,y) in [(0,0), (2,120), (224,278), (48,320)] {
            XCTAssertLessThan(try XCTUnwrap(plate.colorAt(x: x*3, y: y*3)).alphaComponent, 0.01)
        }
    }

    func testAbyssal97ResolvesTheProductionRepertoireAndAtlasGrids() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../SiriusMac/Skins/Bundled").standardized
        let appearance = try SkinManifestValidator.validate(
            Data(contentsOf: directory.appendingPathComponent("Abyssal97.json")), classification: .bundled,
            assetResolver: { Self.resolve($0, beneath: directory) }
        )
        let motion = try XCTUnwrap(appearance.motion)
        let scene = try SpriteMotionSceneCodec.decode(
            Data(contentsOf: try XCTUnwrap(motion.spriteSceneURL)), allowedAssets: Set(motion.spriteAssetURLs.keys)
        )
        try SpriteMotionSceneCodec.validateAtlasDimensions(scene, assets: motion.spriteAssetURLs)
        XCTAssertEqual(scene.formatVersion, 2)
        XCTAssertEqual(scene.performances?.filter { $0.event == nil }.count, 18)
        XCTAssertEqual(scene.performances?.filter { $0.event != nil }.count, 10)
        XCTAssertEqual(appearance.layoutPlan.presentationSize, .init(width: 672, height: 540))
        XCTAssertEqual(Set(scene.performances?.compactMap(\.event) ?? []),
                       [.songFavoriteAdded, .songFavoriteRemoved, .channelFavoriteAdded, .channelFavoriteRemoved, .channelChanged])
    }

    private static func resolve(_ path: String, beneath directory: URL) -> URL? {
        for relativePath in [path, "Assets/\(path)", "Assets/Exit97/\(path)", "Assets/QuartzDeck/\(path)", "Assets/Abyssal97/\(path)"] {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
