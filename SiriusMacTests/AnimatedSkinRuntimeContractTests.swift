import XCTest
@testable import Canis97

@MainActor
final class AnimatedSkinRuntimeContractTests: XCTestCase {
    func testLifecyclePolicyAllowsVisibleSelectedMotionWithoutForegroundGates() {
        XCTAssertTrue(
            AnimatedSkinLifecyclePolicy(
                isSelected: true,
                isVisible: true,
                isPaused: false,
                reduceMotion: false,
                isWithinBudget: true
            ).shouldAnimate
        )
        XCTAssertFalse(
            AnimatedSkinLifecyclePolicy(
                isSelected: false,
                isVisible: true,
                isPaused: false,
                reduceMotion: false,
                isWithinBudget: true
            ).shouldAnimate
        )
    }

    func testRuntimeContractForcesCoreAnimationAndStaticFallback() {
        XCTAssertEqual(AnimatedSkinRuntime.renderingEngine, .coreAnimation)
        XCTAssertEqual(AnimatedSkinRuntime.fallbackDisposition(for: .unsupportedRenderer), .staticPose)
        XCTAssertEqual(AnimatedSkinRuntime.fallbackDisposition(for: .compatibilityWarning), .staticPose)
        XCTAssertEqual(AnimatedSkinRuntime.fallbackDisposition(for: .externalResourceAttempt), .staticPose)
    }

    func testOrbitDeckIsAnOrdinaryValidatedSchemaFourPackage() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../SiriusMac/Skins/Bundled")
            .standardized
        let manifest = try Data(contentsOf: directory.appendingPathComponent("OrbitDeck.json"))
        let appearance = try SkinManifestValidator.validate(
            manifest,
            classification: .bundled,
            assetResolver: { path in
                let candidate = directory.appendingPathComponent(path)
                return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
            }
        )
        XCTAssertEqual(appearance.motion?.format, .canis97)
        XCTAssertEqual(appearance.motion?.documentURL.lastPathComponent, "OrbitDeck.motion.json")
    }

    func testSignalGardenIsAnOrdinaryValidatedSchemaFourPackage() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../SiriusMac/Skins/Bundled").standardized
        let manifest = try Data(contentsOf: directory.appendingPathComponent("SignalGarden.json"))
        let appearance = try SkinManifestValidator.validate(manifest, classification: .bundled, assetResolver: { path in
            let candidate = directory.appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        })
        XCTAssertEqual(appearance.motion?.format, .canis97)
        XCTAssertEqual(appearance.motion?.documentURL.lastPathComponent, "SignalGarden.motion.json")
    }

    func testExit97UsesOnlyValidatedLocalMotionAndSpriteAssets() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../SiriusMac/Skins/Bundled").standardized
        let manifest = try Data(contentsOf: directory.appendingPathComponent("Exit97.json"))
        let appearance = try SkinManifestValidator.validate(
            manifest,
            classification: .bundled,
            assetResolver: { path in
                for relativePath in [path, "Assets/\(path)", "Assets/Exit97/\(path)"] {
                    let candidate = directory.appendingPathComponent(relativePath)
                    if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                }
                return nil
            }
        )
        let motion = try XCTUnwrap(appearance.motion)
        XCTAssertEqual(motion.documentURL.lastPathComponent, "Exit97.motion.json")
        XCTAssertEqual(motion.spriteSceneURL?.lastPathComponent, "Exit97.scene.json")
        XCTAssertEqual(motion.spriteAssetURLs.count, 18)
        XCTAssertEqual(Set(motion.events?.keys.map { $0 } ?? []), Set(SkinMotionEvent.allCases))
    }

    func testQuartzDeckUsesOnlyApprovedLocalMotionAndSpriteAssets() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../SiriusMac/Skins/Bundled").standardized
        let manifest = try Data(contentsOf: directory.appendingPathComponent("QuartzDeck.json"))
        let appearance = try SkinManifestValidator.validate(
            manifest,
            classification: .bundled,
            assetResolver: { path in
                for relativePath in [path, "Assets/QuartzDeck/\(path)"] {
                    let candidate = directory.appendingPathComponent(relativePath)
                    if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                }
                return nil
            }
        )
        let motion = try XCTUnwrap(appearance.motion)
        XCTAssertEqual(motion.documentURL.lastPathComponent, "QuartzDeck.motion.json")
        XCTAssertEqual(motion.spriteSceneURL?.lastPathComponent, "QuartzDeck.scene.json")
        XCTAssertEqual(motion.spriteAssetURLs.count, 3)
        XCTAssertEqual(Set(motion.events?.keys.map { $0 } ?? []), Set(SkinMotionEvent.allCases))
    }

    func testOfflineReviewFixturesSelectAllSchemaFourAppearances() throws {
        XCTAssertEqual(
            OfflineReviewAppearanceFixture(environment: [
                OfflineReviewLaunchMode.reviewAppearanceEnvironmentKey: "orbitDeck",
            ]),
            .orbitDeck
        )
        XCTAssertEqual(
            OfflineReviewAppearanceFixture(environment: [
                OfflineReviewLaunchMode.reviewAppearanceEnvironmentKey: "signalGarden",
            ]),
            .signalGarden
        )
        XCTAssertEqual(
            OfflineReviewAppearanceFixture(environment: [
                OfflineReviewLaunchMode.reviewAppearanceEnvironmentKey: "exit97",
            ]),
            .exit97
        )
        XCTAssertEqual(
            OfflineReviewAppearanceFixture(environment: [
                OfflineReviewLaunchMode.reviewAppearanceEnvironmentKey: "quartzDeck",
            ]),
            .quartzDeck
        )

        let harnessSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../SiriusMac/Testing/UITestHarness.swift")
                .standardized,
            encoding: .utf8
        )
        XCTAssertTrue(harnessSource.contains("case orbitDeck"))
        XCTAssertTrue(harnessSource.contains("case signalGarden"))
        XCTAssertTrue(harnessSource.contains("case exit97"))
        XCTAssertTrue(harnessSource.contains("case quartzDeck"))
        XCTAssertTrue(harnessSource.contains("case .orbitDeck: \"Orbit Deck\""))
        XCTAssertTrue(harnessSource.contains("case .signalGarden: \"Signal Garden\""))
        XCTAssertTrue(harnessSource.contains("case .exit97: \"Exit 97\""))
        XCTAssertTrue(harnessSource.contains("case .quartzDeck: \"Quartz Deck + Quartz Link\""))

        let catalog = SkinAppearanceCatalog.phaseOne
        for name in ["Orbit Deck", "Signal Garden", "Exit 97", "Quartz Deck + Quartz Link"] {
            let appearance = try XCTUnwrap(catalog.appearances.first { $0.displayName == name })
            XCTAssertEqual(appearance.motion?.format, .canis97)
            XCTAssertNotNil(appearance.motion)
        }
    }
}
