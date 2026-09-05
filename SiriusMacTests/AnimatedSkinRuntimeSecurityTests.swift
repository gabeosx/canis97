import Foundation
import XCTest
import Canis97MotionSafety
@testable import Canis97

@MainActor
final class AnimatedSkinRuntimeSecurityTests: XCTestCase {
    func testMalformedCanonicalDataFailsClosedToStaticFallback() {
        XCTAssertThrowsError(try AnimatedSkinRuntime.validateCanonical(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? AnimatedSkinRuntimeFailure, .invalidCanonicalDocument)
        }
        XCTAssertEqual(
            AnimatedSkinRuntime.fallbackDisposition(for: .invalidCanonicalDocument),
            .staticPose
        )
    }

    func testLifecycleKeepsVisibleBackgroundMotionRunning() {
        let active = AnimatedSkinLifecyclePolicy(
            isSelected: true,
            isVisible: true,
            isPaused: false,
            reduceMotion: false,
            isWithinBudget: true
        )
        XCTAssertTrue(active.shouldAnimate)

        let inactiveStates: [AnimatedSkinLifecyclePolicy] = [
            .init(isSelected: false, isVisible: true, isPaused: false, reduceMotion: false, isWithinBudget: true),
            .init(isSelected: true, isVisible: false, isPaused: false, reduceMotion: false, isWithinBudget: true),
            .init(isSelected: true, isVisible: true, isPaused: true, reduceMotion: false, isWithinBudget: true),
            .init(isSelected: true, isVisible: true, isPaused: false, reduceMotion: true, isWithinBudget: true),
            .init(isSelected: true, isVisible: true, isPaused: false, reduceMotion: false, isWithinBudget: false),
        ]
        XCTAssertTrue(inactiveStates.allSatisfy { !$0.shouldAnimate })
    }

    func testBudgetStateHasOnlyBoundedOrStaticOutcomes() {
        XCTAssertTrue(AnimatedSkinBudgetState.withinBudget.isWithinBudget)
        XCTAssertFalse(AnimatedSkinBudgetState.exceeded.isWithinBudget)
    }

    func testRendererAndConverterRetainFailClosedImplementationContracts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let runtime = try String(contentsOf: root.appendingPathComponent("SiriusMac/Motion/AnimatedSkinRuntime.swift"), encoding: .utf8)
        let converter = try String(contentsOf: root.appendingPathComponent("Canis97MotionConverter/Canis97MotionConverterService.swift"), encoding: .utf8)

        XCTAssertTrue(runtime.contains("LottieConfiguration(renderingEngine: .coreAnimation"))
        XCTAssertTrue(runtime.contains("imageProvider: DeniedAnimationImageProvider()"))
        XCTAssertTrue(runtime.contains("override func hitTest(_ point: NSPoint) -> NSView? { nil }"))
        XCTAssertTrue(runtime.contains("animationView.pause()"))
        XCTAssertTrue(runtime.contains("animationView.removeFromSuperview()"))
        XCTAssertTrue(runtime.contains("CanonicalMotionCodec.decode"))
        XCTAssertTrue(converter.contains("private static let maximumRequestBytes"))
        XCTAssertTrue(converter.contains("RestrictedLottieSource(data: request)"))
        XCTAssertTrue(converter.contains("CanonicalMotionValidator().validate"))
        XCTAssertFalse(converter.contains("URLSession"))
        XCTAssertFalse(converter.contains("NSOpenPanel"))
    }

    func testLifecycleObserversAndOfflineAcceptanceControlsRemainClosed() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let runtime = try String(contentsOf: root.appendingPathComponent("SiriusMac/Motion/AnimatedSkinRuntime.swift"), encoding: .utf8)
        let compactPlayer = try String(contentsOf: root.appendingPathComponent("SiriusMac/Player/CompactPlayerView.swift"), encoding: .utf8)
        let harness = try String(contentsOf: root.appendingPathComponent("SiriusMac/Testing/UITestHarness.swift"), encoding: .utf8)

        for notification in [
            "NSWindow.didMiniaturizeNotification", "NSWindow.didDeminiaturizeNotification",
            "NSWindow.didChangeOcclusionStateNotification",
            "NSApplication.didHideNotification", "NSApplication.didUnhideNotification",
        ] {
            XCTAssertTrue(runtime.contains(notification))
        }
        for forbiddenForegroundGate in [
            "NSWindow.didBecomeKeyNotification", "NSWindow.didResignKeyNotification",
            "NSApplication.didBecomeActiveNotification", "NSApplication.didResignActiveNotification",
            "window?.isKeyWindow", "NSApp.isActive",
        ] {
            XCTAssertFalse(runtime.contains(forbiddenForegroundGate))
        }
        XCTAssertTrue(runtime.contains("!isHiddenOrHasHiddenAncestor"))
        XCTAssertTrue(runtime.contains("!window.isMiniaturized"))
        XCTAssertTrue(runtime.contains("!NSApp.isHidden"))
        XCTAssertTrue(runtime.contains("override func viewDidMoveToWindow()"))
        XCTAssertTrue(runtime.contains("installedMotionURL != motion.documentURL"))
        XCTAssertTrue(runtime.contains("static func dismantleNSView"))
        XCTAssertTrue(runtime.contains("lifecycleObservers.forEach(NotificationCenter.default.removeObserver)"))
        XCTAssertTrue(compactPlayer.contains("animationBudgetState: AnimatedSkinBudgetState = .withinBudget"))
        XCTAssertTrue(compactPlayer.contains("animationReduceMotionOverride: Bool? = nil"))
        XCTAssertTrue(compactPlayer.contains("budgetState: animationBudgetState"))
        let decorativeSurfaces = try XCTUnwrap(compactPlayer.range(of: "if !hasExpressiveFaceplate {\n                    appOwnedDecorativeSurfaces"))
        let motionHost = try XCTUnwrap(compactPlayer.range(of: "AnimatedSkinHost("))
        let semanticContent = try XCTUnwrap(compactPlayer.range(of: "if renderingAppearance.layoutPlan.isLegacy {"))
        XCTAssertLessThan(decorativeSurfaces.lowerBound, motionHost.lowerBound)
        XCTAssertLessThan(motionHost.lowerBound, semanticContent.lowerBound)
        XCTAssertTrue(compactPlayer.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)\n                .allowsHitTesting(false)"))
        XCTAssertTrue(compactPlayer.contains(".allowsHitTesting(false)\n                .accessibilityHidden(true)"))

        XCTAssertTrue(harness.hasPrefix("#if DEBUG || CANIS97_ANIMATION_ACCEPTANCE"))
        for identifier in [
            "offline-review.animation.reduce-motion", "offline-review.animation.play-pause",
            "offline-review.animation.budget", "offline-review.animation.host-present",
            "offline-review.animation.host-removed",
        ] {
            XCTAssertTrue(harness.contains(identifier))
        }
        XCTAssertTrue(harness.contains("if action == .playPause { animationIsPlaying.toggle() }"))
        XCTAssertTrue(harness.contains("animationReduceMotionOverride: animationReduceMotion"))
        XCTAssertTrue(harness.contains("if animationHostPresent"))
    }

    func testCanonicalOpacityTimelinesMapToLoopingStaticSafeLottie() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let runtime = try String(contentsOf: root.appendingPathComponent("SiriusMac/Motion/AnimatedSkinRuntime.swift"), encoding: .utf8)

        XCTAssertTrue(runtime.contains("animationView.loopMode = .loop"))
        XCTAssertTrue(runtime.contains("private static func opacityProperty(for layer: CanonicalMotionLayer)"))
        XCTAssertTrue(runtime.contains("\"a\": 1, \"k\": keyframes"))
        XCTAssertTrue(runtime.contains("\"s\": [keyframe.value * 100]"))
        XCTAssertTrue(runtime.contains("animationView.currentFrame = AnimationFrameTime(staticFrame)"))
        XCTAssertTrue(runtime.contains("let endFrame = max(1, document.frameRate * document.duration)"))
        XCTAssertTrue(runtime.contains("makeLayer(layer, index: index, canvas: document.canvas, endFrame: endFrame)"))
        for metadata in ["\"ip\": 0", "\"op\": endFrame", "\"st\": 0", "\"sr\": 1"] {
            XCTAssertTrue(runtime.contains(metadata))
        }
        XCTAssertTrue(runtime.contains("layer.paths.flatMap(makeShape)"))
        XCTAssertTrue(runtime.contains("let pathItem: [String: Any]"))
        XCTAssertTrue(runtime.contains("let fillItem: [String: Any]"))
        XCTAssertTrue(runtime.contains("return [pathItem, fillItem]"))
        XCTAssertFalse(runtime.contains("\"fill\": ["))

        for name in ["OrbitDeck", "SignalGarden", "Exit97", "QuartzDeck"] {
            let data = try Data(contentsOf: root.appendingPathComponent("SiriusMac/Skins/Bundled/\(name).motion.json"))
            let document = try CanonicalMotionCodec.decode(data)
            let timeline = try XCTUnwrap(document.layers.first?.keyframes)
            XCTAssertGreaterThanOrEqual(timeline.count, 2)
            XCTAssertEqual(timeline.first?.frame, 0)
            XCTAssertEqual(timeline.first?.value, timeline.last?.value)
            XCTAssertTrue(zip(timeline, timeline.dropFirst()).allSatisfy { $0.frame < $1.frame })
            XCTAssertTrue(timeline.allSatisfy { (0 ... 1).contains($0.value) })
            XCTAssertLessThanOrEqual(timeline.last?.frame ?? .infinity, document.frameRate * document.duration)

            let layer = try XCTUnwrap(document.layers.first)
            let points = layer.paths.flatMap(\.points).map {
                (
                    x: $0.x * layer.transform.scale.x + layer.transform.position.x,
                    y: $0.y * layer.transform.scale.y + layer.transform.position.y
                )
            }
            let minX = try XCTUnwrap(points.map(\.x).min())
            let maxX = try XCTUnwrap(points.map(\.x).max())
            let minY = try XCTUnwrap(points.map(\.y).min())
            let maxY = try XCTUnwrap(points.map(\.y).max())
            XCTAssertLessThan(minX, document.canvas.width)
            XCTAssertGreaterThan(maxX, 0)
            XCTAssertLessThan(minY, document.canvas.height)
            XCTAssertGreaterThan(maxY, 0)
            let occupiedCanvasFraction = ((maxX - minX) * (maxY - minY)) / (document.canvas.width * document.canvas.height)
            if name == "QuartzDeck" {
                // The taller hardware must not enlarge the two physical LCDs
                // merely to satisfy a fraction-of-canvas heuristic. The sprite
                // scene supplies the primary motion; canonical afterglow stays
                // registered to these exact receiver apertures.
                XCTAssertEqual(minX, 92)
                XCTAssertEqual(maxX, 212)
                XCTAssertEqual(minY, 288)
                XCTAssertEqual(maxY, 348)
            } else {
                XCTAssertGreaterThan(occupiedCanvasFraction, 0.05)
            }
        }
    }

    func testSpriteSceneRejectsUnknownFieldsAndUnlistedAssets() throws {
        let valid = Data(
            #"{"formatVersion":1,"canvas":{"width":448,"height":304},"layers":[{"identifier":"roadster","asset":"vehicle.png","frame":{"x":0,"y":0,"width":448,"height":228},"zIndex":0,"role":"subject","timeline":null,"event":null,"group":null}],"encounterGroups":[]}"#.utf8
        )
        XCTAssertNoThrow(try SpriteMotionSceneCodec.decode(valid, allowedAssets: ["vehicle.png"]))
        XCTAssertThrowsError(try SpriteMotionSceneCodec.decode(valid, allowedAssets: [])) { error in
            XCTAssertEqual(error as? SpriteMotionSceneFailure, .unresolvedAsset)
        }

        let unknownField = Data(
            #"{"formatVersion":1,"canvas":{"width":448,"height":304},"layers":[{"identifier":"roadster","asset":"vehicle.png","frame":{"x":0,"y":0,"width":448,"height":228},"zIndex":0,"role":"subject","timeline":null,"event":null,"group":null,"remoteURL":"https://example.invalid"}],"encounterGroups":[]}"#.utf8
        )
        XCTAssertThrowsError(try SpriteMotionSceneCodec.decode(unknownField, allowedAssets: ["vehicle.png"])) { error in
            XCTAssertEqual(error as? SpriteMotionSceneFailure, .unknownField)
        }
    }
}

extension AnimatedSkinRuntimeSecurityTests {
    private func performanceSceneFixture() -> [String: Any] {
        func frame(_ time: Double, _ opacity: Double) -> [String: Any] {
            ["time": time, "x": time * 5, "y": 0, "scaleX": 1, "scaleY": 1,
             "rotation": 0, "opacity": opacity, "easing": "linear"]
        }
        return [
            "formatVersion": 2, "canvas": ["width": 64, "height": 64], "encounterGroups": [],
            "layers": [["identifier": "visitor", "asset": "poses.png",
                "frame": ["x": 0, "y": 0, "width": 32, "height": 32], "zIndex": 1,
                "role": "performance", "timeline": NSNull(), "event": NSNull(), "group": NSNull(),
                "atlas": ["columns": 2, "rows": 1, "frameCount": 2]]],
            "director": ["seed": 97, "rest": ["minimum": 2, "maximum": 3],
                "cadences": [["tier": "common", "initialDelay": ["minimum": 1, "maximum": 1],
                    "interval": ["minimum": 20, "maximum": 55]]]],
            "performances": [["identifier": "visit", "actor": "fish", "tier": "common",
                "event": NSNull(), "duration": 2, "cooldown": 30, "actorCooldown": 10,
                "requiresSongFavorite": NSNull(), "requiresChannelFavorite": NSNull(),
                "tracks": [["layerID": "visitor", "timeline": [frame(0, 0), frame(1, 1), frame(2, 0)],
                    "poseCycle": ["frames": [0, 1], "framesPerSecond": 4, "loops": true]]]]],
        ]
    }

    func testPerformanceSceneDecodesBoundedAtlasAndSchedulingPlan() throws {
        let document = try SpriteMotionSceneCodec.decode(
            JSONSerialization.data(withJSONObject: performanceSceneFixture()), allowedAssets: ["poses.png"]
        )
        XCTAssertEqual(document.formatVersion, 2)
        XCTAssertEqual(document.layers.first?.atlas?.frameCount, 2)
        XCTAssertEqual(document.performances?.first?.tracks.first?.poseCycle?.frames, [0, 1])
        let plan = try XCTUnwrap(document.performancePlan())
        var director = ScenePerformanceDirector(plan: plan)
        XCTAssertNil(director.next(activeTime: 0))
        XCTAssertEqual(director.next(activeTime: 1)?.identifier, "visit")
        XCTAssertNil(director.next(activeTime: 1))
    }

    func testPerformanceSceneRejectsUnknownFieldsUnsafeCellsAndOverflowGeometry() throws {
        for defect in 0..<7 {
            var root = performanceSceneFixture()
            var layers = root["layers"] as! [[String: Any]]
            var performances = root["performances"] as! [[String: Any]]
            switch defect {
            case 0: root["script"] = "forbidden"
            case 1: layers[0]["atlas"] = ["columns": Int.max, "rows": 2, "frameCount": 2]
            case 2: layers[0]["frame"] = ["x": Int.max, "y": 0, "width": 2, "height": 2]
            case 3: performances[0]["duration"] = 31
            case 4:
                var tracks = performances[0]["tracks"] as! [[String: Any]]
                tracks[0]["poseCycle"] = ["frames": [0, 2], "framesPerSecond": 4, "loops": true]
                performances[0]["tracks"] = tracks
            case 5: root["formatVersion"] = 1
            default: performances += performances
            }
            root["layers"] = layers
            root["performances"] = performances
            XCTAssertThrowsError(try SpriteMotionSceneCodec.decode(
                JSONSerialization.data(withJSONObject: root), allowedAssets: ["poses.png"]
            ), "defect \(defect)")
        }
    }
}
