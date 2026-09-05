import AppKit
import Canis97MotionSafety
import Lottie
import QuartzCore
import SwiftUI

enum AnimatedSkinFallbackDisposition: Equatable, Sendable {
    case staticPose
}

enum AnimatedSkinRuntimeFailure: Error, Equatable, Sendable {
    case unsupportedRenderer
    case compatibilityWarning
    case externalResourceAttempt
    case invalidCanonicalDocument
}

/// Closed lifecycle input owned by the compact-player composition. A skin may
/// never opt itself into work when its host is hidden or inaccessible.
struct AnimatedSkinLifecyclePolicy: Equatable, Sendable {
    let isSelected: Bool
    let isVisible: Bool
    let isPaused: Bool
    let reduceMotion: Bool
    let isWithinBudget: Bool

    var shouldAnimate: Bool {
        isSelected && isVisible && !isPaused && !reduceMotion && isWithinBudget
    }
}

enum AnimatedSkinBudgetState: Equatable, Sendable {
    case withinBudget
    case exceeded

    var isWithinBudget: Bool { self == .withinBudget }
}

struct AnimatedSkinEventTrigger: Equatable, Sendable {
    let event: SkinMotionEvent
    let sequence: UInt64
}

/// Lottie is deliberately confined to this app-internal rendering seam.
/// Canonical motion has already passed `CanonicalMotionCodec.decode` before a
/// host is installed; raw imported JSON is never accepted here.
@MainActor
final class AnimatedSkinRuntime {
    static let renderingEngine: RenderingEngine = .coreAnimation

    static func fallbackDisposition(for _: AnimatedSkinRuntimeFailure) -> AnimatedSkinFallbackDisposition {
        .staticPose
    }

    static func makeConfiguration() -> LottieConfiguration {
        LottieConfiguration(renderingEngine: .coreAnimation, reducedMotionOption: .standardMotion)
    }

    static func validateCanonical(_ data: Data) throws -> CanonicalMotionDocument {
        do {
            return try CanonicalMotionCodec.decode(data)
        } catch {
            throw AnimatedSkinRuntimeFailure.invalidCanonicalDocument
        }
    }
}

/// AppKit keeps the renderer below SwiftUI's semantic controls. It never
/// participates in hit testing and tears down the active composition when the
/// lifecycle policy no longer permits work.
@MainActor
final class AnimatedSkinHostView: NSView {
    private let animationView: LottieAnimationView
    private let spriteSceneView = SpriteMotionSceneView()
    private var selectedMotion: ValidatedSkinMotion?
    private var installedMotionURL: URL?
    private var installedSpriteSceneURL: URL?
    private var canonicalMotionIsValid = false
    private var currentState: SkinMotionState = .idle
    private var currentEvent: AnimatedSkinEventTrigger?
    private var lastPlayedEventSequence: UInt64?
    private var isSongFavorite = false
    private var isChannelFavorite = false
    private var isPaused = true
    private var reduceMotion = true
    private var budgetState: AnimatedSkinBudgetState = .exceeded
    private var lifecycleObservers: [NSObjectProtocol] = []

    override var acceptsFirstResponder: Bool { false }

    init() {
        animationView = LottieAnimationView(
            animation: nil,
            imageProvider: DeniedAnimationImageProvider(),
            configuration: AnimatedSkinRuntime.makeConfiguration()
        )
        super.init(frame: .zero)
        wantsLayer = true
        animationView.translatesAutoresizingMaskIntoConstraints = false
        spriteSceneView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(animationView)
        addSubview(spriteSceneView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            animationView.topAnchor.constraint(equalTo: topAnchor),
            animationView.bottomAnchor.constraint(equalTo: bottomAnchor),
            spriteSceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            spriteSceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
            spriteSceneView.topAnchor.constraint(equalTo: topAnchor),
            spriteSceneView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        animationView.loopMode = .loop
        animationView.pause()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        replaceLifecycleObservers()
        recomputeLifecyclePolicy()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(
        motion: ValidatedSkinMotion?,
        state: SkinMotionState,
        event: AnimatedSkinEventTrigger?,
        isSongFavorite: Bool,
        isChannelFavorite: Bool,
        reduceMotion: Bool,
        budgetState: AnimatedSkinBudgetState
    ) {
        self.selectedMotion = motion
        currentState = state
        currentEvent = event
        self.isSongFavorite = isSongFavorite
        self.isChannelFavorite = isChannelFavorite
        isPaused = state != .playing
        self.reduceMotion = reduceMotion
        self.budgetState = budgetState

        guard let motion else {
            installedMotionURL = nil
            installedSpriteSceneURL = nil
            canonicalMotionIsValid = false
            spriteSceneView.install(nil, assets: [:])
            recomputeLifecyclePolicy()
            return
        }

        if installedMotionURL != motion.documentURL {
            installedMotionURL = motion.documentURL
            do {
                let canonicalData = try Data(contentsOf: motion.documentURL, options: [.mappedIfSafe])
                try installCanonicalMotion(canonicalData)
                canonicalMotionIsValid = true
            } catch {
                canonicalMotionIsValid = false
            }
        }
        if installedSpriteSceneURL != motion.spriteSceneURL {
            installedSpriteSceneURL = motion.spriteSceneURL
            do {
                guard let sceneURL = motion.spriteSceneURL else {
                    spriteSceneView.install(nil, assets: [:])
                    recomputeLifecyclePolicy()
                    return
                }
                let data = try Data(contentsOf: sceneURL, options: [.mappedIfSafe])
                let scene = try SpriteMotionSceneCodec.decode(
                    data,
                    allowedAssets: Set(motion.spriteAssetURLs.keys)
                )
                try SpriteMotionSceneCodec.validateAtlasDimensions(scene, assets: motion.spriteAssetURLs)
                spriteSceneView.install(scene, assets: motion.spriteAssetURLs)
            } catch {
                spriteSceneView.install(nil, assets: [:])
            }
        }
        recomputeLifecyclePolicy()
    }

    private func recomputeLifecyclePolicy() {
        let window = window
        let isVisible = if let window {
            !isHiddenOrHasHiddenAncestor &&
                window.isVisible &&
                !window.isMiniaturized &&
                window.occlusionState.contains(.visible) &&
                !NSApp.isHidden
        } else {
            false
        }
        let policy = AnimatedSkinLifecyclePolicy(
            isSelected: selectedMotion != nil && canonicalMotionIsValid,
            isVisible: isVisible,
            isPaused: isPaused,
            reduceMotion: reduceMotion,
            isWithinBudget: budgetState.isWithinBudget
        )
        apply(policy)
    }

    private func apply(_ policy: AnimatedSkinLifecyclePolicy) {
        spriteSceneView.apply(
            shouldAnimate: policy.shouldAnimate,
            event: currentEvent,
            isSongFavorite: isSongFavorite,
            isChannelFavorite: isChannelFavorite
        )
        guard policy.shouldAnimate,
              animationView.currentRenderingEngine == AnimatedSkinRuntime.renderingEngine
        else {
            animationView.pause()
            if let staticFrame = selectedMotion?.states[currentState]?.startFrame {
                animationView.currentFrame = AnimationFrameTime(staticFrame)
            } else {
                animationView.currentProgress = 0
            }
            return
        }
        if let event = currentEvent,
           event.sequence != lastPlayedEventSequence,
           let range = selectedMotion?.events?[event.event]
        {
            lastPlayedEventSequence = event.sequence
            animationView.play(
                fromFrame: AnimationFrameTime(range.startFrame),
                toFrame: AnimationFrameTime(range.endFrame),
                loopMode: .playOnce
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.playCurrentState() }
            }
        } else {
            playCurrentState()
        }
    }

    private func playCurrentState() {
        guard let range = selectedMotion?.states[currentState] else { return }
        if range.startFrame == range.endFrame {
            animationView.pause()
            animationView.currentFrame = AnimationFrameTime(range.startFrame)
        } else {
            animationView.play(
                fromFrame: AnimationFrameTime(range.startFrame),
                toFrame: AnimationFrameTime(range.endFrame),
                loopMode: .loop
            )
        }
    }

    private func replaceLifecycleObservers() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
        guard let window else { return }

        let center = NotificationCenter.default
        let notifications: [(Notification.Name, Any?)] = [
            (NSWindow.didMiniaturizeNotification, window),
            (NSWindow.didDeminiaturizeNotification, window),
            (NSWindow.didChangeOcclusionStateNotification, window),
            (NSApplication.didHideNotification, NSApp),
            (NSApplication.didUnhideNotification, NSApp),
        ]
        lifecycleObservers = notifications.map { name, object in
            center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recomputeLifecyclePolicy()
                }
            }
        }
    }

    func installCanonicalMotion(_ data: Data) throws {
        let document = try AnimatedSkinRuntime.validateCanonical(data)
        let animation = try CanonicalLottieAdapter.animation(from: document)
        guard animationView.currentRenderingEngine == AnimatedSkinRuntime.renderingEngine else {
            throw AnimatedSkinRuntimeFailure.unsupportedRenderer
        }
        animationView.animation = animation
        animationView.pause()
    }

    func tearDown() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
        selectedMotion = nil
        installedMotionURL = nil
        installedSpriteSceneURL = nil
        canonicalMotionIsValid = false
        spriteSceneView.tearDown()
        animationView.stop()
        animationView.removeFromSuperview()
    }
}

/// SwiftUI supplies only an already-validated, on-disk canonical document.
/// The bridge performs no URL loading and has no interaction surface, keeping
/// the app-owned controls above it in the responder chain.
struct AnimatedSkinHost: NSViewRepresentable {
    let motion: ValidatedSkinMotion?
    let state: SkinMotionState
    let event: AnimatedSkinEventTrigger?
    let isSongFavorite: Bool
    let isChannelFavorite: Bool
    let reduceMotion: Bool
    let budgetState: AnimatedSkinBudgetState

    func makeNSView(context _: Context) -> AnimatedSkinHostView {
        AnimatedSkinHostView()
    }

    func updateNSView(_ host: AnimatedSkinHostView, context _: Context) {
        host.configure(
            motion: motion,
            state: state,
            event: event,
            isSongFavorite: isSongFavorite,
            isChannelFavorite: isChannelFavorite,
            reduceMotion: reduceMotion,
            budgetState: budgetState
        )
    }

    static func dismantleNSView(_ host: AnimatedSkinHostView, coordinator _: ()) {
        host.tearDown()
    }
}

private final class DeniedAnimationImageProvider: AnimationImageProvider {
    var cacheEligible: Bool { false }
    func imageForAsset(asset _: ImageAsset) -> CGImage? { nil }
}

enum SpriteMotionSceneFailure: Error, Equatable, Sendable {
    case malformedDocument
    case unknownField
    case exceededBudget
    case invalidValue
    case unresolvedAsset
}

struct SpriteMotionSceneDocument: Decodable, Equatable, Sendable {
    struct Canvas: Decodable, Equatable, Sendable {
        let width: Int
        let height: Int
    }

    enum LayerRole: String, Decodable, Equatable, Sendable {
        case backdrop
        case subject
        case effect
        case persistentSongFavorite
        case persistentChannelFavorite
        case encounter
        case performance
        case event
    }

    enum Easing: String, Decodable, Equatable, Sendable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
    }

    struct Keyframe: Decodable, Equatable, Sendable {
        let time: Double
        let x: Double
        let y: Double
        let scaleX: Double
        let scaleY: Double
        let rotation: Double
        let opacity: Double
        let easing: Easing
    }

    struct Layer: Decodable, Equatable, Sendable {
        let identifier: String
        let asset: String
        let frame: CompactSkinRect
        let zIndex: Int
        let role: LayerRole
        let timeline: [Keyframe]?
        let event: SkinMotionEvent?
        let group: String?
        var atlas: Atlas? = nil
    }

    struct EncounterGroup: Decodable, Equatable, Sendable {
        let identifier: String
        let layerIDs: [String]
        let interval: Double
        let seed: UInt64
    }

    struct Atlas: Decodable, Equatable, Sendable {
        let columns: Int
        let rows: Int
        let frameCount: Int
    }

    struct PoseCycle: Decodable, Equatable, Sendable {
        let frames: [Int]
        let framesPerSecond: Double
        let loops: Bool
    }

    struct PerformanceTrack: Decodable, Equatable, Sendable {
        let layerID: String
        let timeline: [Keyframe]
        let poseCycle: PoseCycle?
    }

    struct Performance: Decodable, Equatable, Sendable {
        let identifier: String
        let actor: String
        let tier: ScenePerformancePlan.Tier?
        let event: SkinMotionEvent?
        let duration: Double
        let cooldown: Double
        let actorCooldown: Double
        let requiresSongFavorite: Bool?
        let requiresChannelFavorite: Bool?
        let tracks: [PerformanceTrack]
    }

    struct DirectorSettings: Decodable, Equatable, Sendable {
        struct Interval: Decodable, Equatable, Sendable {
            let minimum: Double
            let maximum: Double
            var planValue: ScenePerformancePlan.Interval { .init(minimum, maximum) }
        }
        struct Cadence: Decodable, Equatable, Sendable {
            let tier: ScenePerformancePlan.Tier
            let initialDelay: Interval
            let interval: Interval
        }
        let seed: UInt64
        let rest: Interval
        let cadences: [Cadence]
    }

    let formatVersion: Int
    let canvas: Canvas
    let layers: [Layer]
    let encounterGroups: [EncounterGroup]
    var director: DirectorSettings? = nil
    var performances: [Performance]? = nil

    func performancePlan() throws -> ScenePerformancePlan? {
        guard let director, let performances else { return nil }
        return try ScenePerformancePlan(seed: director.seed,
            cadences: director.cadences.map { .init(tier: $0.tier, initialDelay: $0.initialDelay.planValue, interval: $0.interval.planValue) },
            performances: performances.compactMap { p in
                guard let tier = p.tier else { return nil }
                return .init(identifier: p.identifier, actor: p.actor, tier: tier, duration: p.duration,
                    cooldown: p.cooldown, actorCooldown: p.actorCooldown,
                    requiresSongFavorite: p.requiresSongFavorite, requiresChannelFavorite: p.requiresChannelFavorite)
            }, rest: director.rest.planValue)
    }
}

enum SpriteMotionSceneCodec {
    private static let maximumBytes = 128 * 1_024
    private static let maximumLayers = 32
    private static let maximumKeyframes = 256

    static func decode(
        _ data: Data,
        allowedAssets: Set<String>
    ) throws -> SpriteMotionSceneDocument {
        guard data.count <= 384 * 1_024 else { throw SpriteMotionSceneFailure.exceededBudget }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SpriteMotionSceneFailure.malformedDocument
        }
        try validateShape(root)
        if (root as? [String: Any])?["formatVersion"] as? Int == 1, data.count > maximumBytes {
            throw SpriteMotionSceneFailure.exceededBudget
        }

        let document: SpriteMotionSceneDocument
        do {
            document = try JSONDecoder().decode(SpriteMotionSceneDocument.self, from: data)
        } catch {
            throw SpriteMotionSceneFailure.malformedDocument
        }
        try validate(document, allowedAssets: allowedAssets)
        return document
    }

    private static func validateShape(_ value: Any) throws {
        guard let raw = value as? [String: Any], let version = raw["formatVersion"] as? Int,
              version == 1 || version == 2 else { throw SpriteMotionSceneFailure.invalidValue }
        let root = try object(value, exact: version == 1
            ? ["formatVersion", "canvas", "layers", "encounterGroups"]
            : ["formatVersion", "canvas", "layers", "encounterGroups", "director", "performances"])
        _ = try object(required(root, "canvas"), exact: ["width", "height"])
        for value in try array(required(root, "layers")) {
            let layer = try object(
                value,
                exact: version == 1
                    ? ["identifier", "asset", "frame", "zIndex", "role", "timeline", "event", "group"]
                    : ["identifier", "asset", "frame", "zIndex", "role", "timeline", "event", "group", "atlas"]
            )
            _ = try object(required(layer, "frame"), exact: ["x", "y", "width", "height"])
            if let atlas = layer["atlas"], !(atlas is NSNull) {
                _ = try object(atlas, exact: ["columns", "rows", "frameCount"])
            }
            if let timeline = layer["timeline"], !(timeline is NSNull) {
                for keyframe in try array(timeline) {
                    _ = try object(
                        keyframe,
                        exact: ["time", "x", "y", "scaleX", "scaleY", "rotation", "opacity", "easing"]
                    )
                }
            }
        }
        for value in try array(required(root, "encounterGroups")) {
            _ = try object(value, exact: ["identifier", "layerIDs", "interval", "seed"])
        }
        if version == 2 {
            let director = try object(required(root, "director"), exact: ["seed", "rest", "cadences"])
            _ = try object(required(director, "rest"), exact: ["minimum", "maximum"])
            for value in try array(required(director, "cadences")) {
                let cadence = try object(value, exact: ["tier", "initialDelay", "interval"])
                _ = try object(required(cadence, "initialDelay"), exact: ["minimum", "maximum"])
                _ = try object(required(cadence, "interval"), exact: ["minimum", "maximum"])
            }
            for value in try array(required(root, "performances")) {
                let performance = try object(value, exact: ["identifier", "actor", "tier", "event", "duration", "cooldown", "actorCooldown", "requiresSongFavorite", "requiresChannelFavorite", "tracks"])
                for value in try array(required(performance, "tracks")) {
                    let track = try object(value, exact: ["layerID", "timeline", "poseCycle"])
                    for frame in try array(required(track, "timeline")) {
                        _ = try object(frame, exact: ["time", "x", "y", "scaleX", "scaleY", "rotation", "opacity", "easing"])
                    }
                    if let value = track["poseCycle"], !(value is NSNull) {
                        _ = try object(value, exact: ["frames", "framesPerSecond", "loops"])
                    }
                }
            }
        }
    }

    private static func validate(
        _ document: SpriteMotionSceneDocument,
        allowedAssets: Set<String>
    ) throws {
        guard (1 ... 2).contains(document.formatVersion),
              (1 ... 2_048).contains(document.canvas.width),
              (1 ... 2_048).contains(document.canvas.height),
              (1 ... maximumLayers).contains(document.layers.count),
              document.encounterGroups.count <= 4
        else { throw SpriteMotionSceneFailure.exceededBudget }

        let identifiers = document.layers.map(\.identifier)
        guard Set(identifiers).count == identifiers.count else { throw SpriteMotionSceneFailure.invalidValue }
        var keyframeCount = 0
        for layer in document.layers {
            guard validIdentifier(layer.identifier),
                  allowedAssets.contains(layer.asset),
                  layer.zIndex >= -100,
                  layer.zIndex <= 100,
                  valid(layer.frame, in: document.canvas)
            else { throw SpriteMotionSceneFailure.unresolvedAsset }

            if let atlas = layer.atlas {
                guard document.formatVersion == 2, layer.role == .performance,
                      (1 ... 8).contains(atlas.columns), (1 ... 8).contains(atlas.rows),
                      (2 ... 64).contains(atlas.frameCount), atlas.frameCount <= atlas.columns * atlas.rows
                else { throw SpriteMotionSceneFailure.invalidValue }
            }
            switch layer.role {
            case .performance:
                guard document.formatVersion == 2, layer.timeline == nil, layer.event == nil, layer.group == nil
                else { throw SpriteMotionSceneFailure.invalidValue }
            case .event:
                guard layer.event != nil, layer.group == nil else { throw SpriteMotionSceneFailure.invalidValue }
            case .encounter:
                guard layer.event == nil, layer.group != nil else { throw SpriteMotionSceneFailure.invalidValue }
            case .backdrop, .subject, .effect, .persistentSongFavorite, .persistentChannelFavorite:
                guard layer.event == nil, layer.group == nil else { throw SpriteMotionSceneFailure.invalidValue }
            }

            if let timeline = layer.timeline {
                guard (2 ... 16).contains(timeline.count) else { throw SpriteMotionSceneFailure.exceededBudget }
                keyframeCount += timeline.count
                var previousTime: Double?
                for keyframe in timeline {
                    guard [keyframe.time, keyframe.x, keyframe.y, keyframe.scaleX, keyframe.scaleY, keyframe.rotation, keyframe.opacity]
                        .allSatisfy(\.isFinite),
                          keyframe.time >= 0,
                          keyframe.time <= 10,
                          previousTime.map({ keyframe.time > $0 }) ?? true,
                          (0.25 ... 4).contains(keyframe.scaleX),
                          (0.25 ... 4).contains(keyframe.scaleY),
                          (-180 ... 180).contains(keyframe.rotation),
                          (0 ... 1).contains(keyframe.opacity),
                          abs(keyframe.x) <= Double(document.canvas.width),
                          abs(keyframe.y) <= Double(document.canvas.height)
                    else { throw SpriteMotionSceneFailure.invalidValue }
                    previousTime = keyframe.time
                }
            }
        }
        guard keyframeCount <= maximumKeyframes else { throw SpriteMotionSceneFailure.exceededBudget }

        let layerByID = Dictionary(uniqueKeysWithValues: document.layers.map { ($0.identifier, $0) })
        let groupIDs = document.encounterGroups.map(\.identifier)
        guard Set(groupIDs).count == groupIDs.count else { throw SpriteMotionSceneFailure.invalidValue }
        for group in document.encounterGroups {
            guard validIdentifier(group.identifier),
                  (4 ... 30).contains(group.interval),
                  (1 ... 12).contains(group.layerIDs.count),
                  Set(group.layerIDs).count == group.layerIDs.count,
                  group.layerIDs.allSatisfy({ id in
                      layerByID[id]?.role == .encounter && layerByID[id]?.group == group.identifier
                  })
            else { throw SpriteMotionSceneFailure.invalidValue }
        }
        for layer in document.layers where layer.role == .encounter {
            guard document.encounterGroups.contains(where: { $0.identifier == layer.group && $0.layerIDs.contains(layer.identifier) })
            else { throw SpriteMotionSceneFailure.invalidValue }
        }
        if document.formatVersion == 2 { try validatePerformances(document) }
    }

    private static func validatePerformances(_ document: SpriteMotionSceneDocument) throws {
        guard document.encounterGroups.isEmpty,
              !document.layers.contains(where: { $0.role == .event || $0.role == .encounter }),
              let performances = document.performances, (1 ... 32).contains(performances.count),
              Set(performances.map(\.identifier)).count == performances.count
        else { throw SpriteMotionSceneFailure.exceededBudget }
        do { guard try document.performancePlan() != nil else { throw SpriteMotionSceneFailure.invalidValue } }
        catch { throw SpriteMotionSceneFailure.invalidValue }
        let layers = Dictionary(uniqueKeysWithValues: document.layers.map { ($0.identifier, $0) })
        var totalKeys = 0, totalPoses = 0
        var eventLayers = Set<String>(), visitorLayers = Set<String>()
        for p in performances {
            guard validIdentifier(p.identifier), validIdentifier(p.actor),
                  (p.event == nil) != (p.tier == nil),
                  p.duration.isFinite, (0.1 ... 30).contains(p.duration),
                  p.cooldown.isFinite, (0 ... 3_600).contains(p.cooldown),
                  p.actorCooldown.isFinite, (0 ... 3_600).contains(p.actorCooldown),
                  (1 ... 8).contains(p.tracks.count),
                  Set(p.tracks.map(\.layerID)).count == p.tracks.count
            else { throw SpriteMotionSceneFailure.invalidValue }
            if let event = p.event {
                guard p.duration <= 6, p.requiresSongFavorite == nil, p.requiresChannelFavorite == nil,
                      performances.filter({ $0.event == event }).count <= 3
                else { throw SpriteMotionSceneFailure.invalidValue }
            }
            for track in p.tracks {
                guard let model = layers[track.layerID], model.role == .performance,
                      (2 ... 32).contains(track.timeline.count), track.timeline.first?.time == 0,
                      track.timeline.last?.time == p.duration, track.timeline.first?.opacity == 0,
                      track.timeline.last?.opacity == 0
                else { throw SpriteMotionSceneFailure.invalidValue }
                if p.event == nil { visitorLayers.insert(track.layerID) } else { eventLayers.insert(track.layerID) }
                totalKeys += track.timeline.count
                var previous = -1.0
                for k in track.timeline {
                    guard [k.time, k.x, k.y, k.scaleX, k.scaleY, k.rotation, k.opacity].allSatisfy(\.isFinite),
                          k.time > previous, k.time <= p.duration,
                          abs(k.x) <= Double(document.canvas.width), abs(k.y) <= Double(document.canvas.height),
                          (0.25 ... 4).contains(k.scaleX), (0.25 ... 4).contains(k.scaleY),
                          (-180 ... 180).contains(k.rotation), (0 ... 1).contains(k.opacity)
                    else { throw SpriteMotionSceneFailure.invalidValue }
                    previous = k.time
                }
                if let cycle = track.poseCycle {
                    guard let atlas = model.atlas, (2 ... 256).contains(cycle.frames.count),
                          cycle.framesPerSecond.isFinite, (1 ... 24).contains(cycle.framesPerSecond),
                          cycle.frames.allSatisfy({ (0 ..< atlas.frameCount).contains($0) })
                    else { throw SpriteMotionSceneFailure.invalidValue }
                    totalPoses += cycle.frames.count
                } else if model.atlas != nil { throw SpriteMotionSceneFailure.invalidValue }
            }
        }
        guard totalKeys <= 2_048, totalPoses <= 4_096, eventLayers.isDisjoint(with: visitorLayers),
              Set(document.layers.filter { $0.role == .performance }.map(\.identifier)) == eventLayers.union(visitorLayers)
        else { throw SpriteMotionSceneFailure.exceededBudget }
    }

    /// Cross-check the scene grid with the validated local image before import
    /// or installation. A malformed grid rejects the scene as a whole.
    static func validateAtlasDimensions(_ document: SpriteMotionSceneDocument, assets: [String: URL]) throws {
        var checked = Set<String>()
        for model in document.layers {
            guard let atlas = model.atlas else { continue }
            let key = "\(model.asset):\(atlas.columns):\(atlas.rows)"
            guard checked.insert(key).inserted else { continue }
            guard let url = assets[model.asset],
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width >= atlas.columns, height >= atlas.rows,
                  width % atlas.columns == 0, height % atlas.rows == 0
            else { throw SpriteMotionSceneFailure.invalidValue }
        }
    }

    private static func valid(_ frame: CompactSkinRect, in canvas: SpriteMotionSceneDocument.Canvas) -> Bool {
        frame.x >= 0 && frame.y >= 0 && frame.width > 0 && frame.height > 0 &&
            frame.width <= canvas.width && frame.height <= canvas.height &&
            frame.x <= canvas.width - frame.width && frame.y <= canvas.height - frame.height
    }

    private static func validIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).contains($0)
        }
    }

    private static func object(_ value: Any, exact keys: Set<String>) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw SpriteMotionSceneFailure.malformedDocument }
        guard Set(value.keys) == keys else { throw SpriteMotionSceneFailure.unknownField }
        return value
    }

    private static func array(_ value: Any) throws -> [Any] {
        guard let value = value as? [Any] else { throw SpriteMotionSceneFailure.malformedDocument }
        return value
    }

    private static func required(_ object: [String: Any], _ key: String) throws -> Any {
        guard let value = object[key] else { throw SpriteMotionSceneFailure.malformedDocument }
        return value
    }
}

@MainActor
private final class SpriteMotionSceneView: NSView {
    private let sceneLayer = CALayer()
    private var document: SpriteMotionSceneDocument?
    private var layersByID: [String: CALayer] = [:]
    private var modelByID: [String: SpriteMotionSceneDocument.Layer] = [:]
    private var encounterTimers: [Timer] = []
    private var encounterOrders: [String: [String]] = [:]
    private var encounterIndices: [String: Int] = [:]
    private var lastEventSequence: UInt64?
    private var isRunning = false
    private var performanceDirector: ScenePerformanceDirector?
    private var performanceTimer: Timer?
    private var performanceClock = 0.0
    private var clockStartedAt: CFTimeInterval?
    private var hasStarted = false
    private var hasAppliedSnapshot = false
    private var eventVariantIndices: [SkinMotionEvent: Int] = [:]
    private var eventBusyUntil = 0.0
    private var activeVisitor: (identifier: String, endsAt: Double)?
    private var isSongFavorite = false
    private var isChannelFavorite = false

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        sceneLayer.masksToBounds = true
        sceneLayer.isGeometryFlipped = true
        layer?.addSublayer(sceneLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        sceneLayer.frame = bounds
    }

    func install(_ document: SpriteMotionSceneDocument?, assets: [String: URL]) {
        stopAnimations()
        performanceTimer?.invalidate()
        performanceTimer = nil
        performanceClock = 0
        clockStartedAt = nil
        hasStarted = false
        hasAppliedSnapshot = false
        eventBusyUntil = 0
        activeVisitor = nil
        lastEventSequence = nil
        eventVariantIndices.removeAll()
        sceneLayer.speed = 1
        sceneLayer.timeOffset = 0
        sceneLayer.beginTime = 0
        performanceDirector = (try? document?.performancePlan()).map { ScenePerformanceDirector(plan: $0) }
        sceneLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        layersByID.removeAll()
        modelByID.removeAll()
        self.document = document
        guard let document else { return }

        var decodedImages: [String: CGImage] = [:]
        for model in document.layers.sorted(by: { $0.zIndex < $1.zIndex }) {
            if decodedImages[model.asset] == nil, let url = assets[model.asset],
               let image = NSImage(contentsOf: url),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                decodedImages[model.asset] = cgImage
            }
            guard let cgImage = decodedImages[model.asset] else { continue }
            if let atlas = model.atlas {
                guard cgImage.width % atlas.columns == 0, cgImage.height % atlas.rows == 0 else { continue }
            }
            let sprite = CALayer()
            sprite.name = model.identifier
            sprite.frame = model.frame.cgRect
            sprite.contents = cgImage
            sprite.contentsGravity = model.atlas == nil ? .resizeAspectFill : .resize
            if let atlas = model.atlas { sprite.contentsRect = atlasRect(0, atlas: atlas) }
            sprite.contentsScale = max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
            sprite.zPosition = CGFloat(model.zIndex)
            sprite.opacity = baseOpacity(for: model)
            sceneLayer.addSublayer(sprite)
            layersByID[model.identifier] = sprite
            modelByID[model.identifier] = model
        }
        applyPersistentVisibility(animated: false)
    }

    func apply(
        shouldAnimate: Bool,
        event: AnimatedSkinEventTrigger?,
        isSongFavorite: Bool,
        isChannelFavorite: Bool
    ) {
        if document?.formatVersion == 2, !hasAppliedSnapshot {
            lastEventSequence = event?.sequence
            hasAppliedSnapshot = true
        }
        let contextChanged = self.isSongFavorite != isSongFavorite || self.isChannelFavorite != isChannelFavorite
        self.isSongFavorite = isSongFavorite
        self.isChannelFavorite = isChannelFavorite
        if contextChanged { cancelStalePerformanceEvents() }
        applyPersistentVisibility(animated: isRunning && shouldAnimate)

        if shouldAnimate, !isRunning {
            startAnimations()
        } else if !shouldAnimate, isRunning {
            stopAnimations()
        }

        if let event, event.sequence != lastEventSequence {
            lastEventSequence = event.sequence
            if shouldAnimate { play(event.event) }
        }
        if contextChanged, isRunning, document?.formatVersion == 2 { schedulePerformanceWake() }
    }

    func tearDown() {
        stopAnimations()
        performanceTimer?.invalidate()
        performanceTimer = nil
        performanceDirector = nil
        document = nil
        layersByID.removeAll()
        modelByID.removeAll()
        sceneLayer.removeFromSuperlayer()
    }

    private func startAnimations() {
        guard let document else { return }
        isRunning = true
        if document.formatVersion == 2 {
            if hasStarted {
                let paused = sceneLayer.timeOffset
                sceneLayer.speed = 1
                sceneLayer.timeOffset = 0
                sceneLayer.beginTime = 0
                sceneLayer.beginTime = sceneLayer.convertTime(CACurrentMediaTime(), from: nil) - paused
            }
            clockStartedAt = CACurrentMediaTime()
            if hasStarted { schedulePerformanceWake(); return }
            hasStarted = true
        }
        for model in document.layers where [.backdrop, .subject, .effect].contains(model.role) {
            guard let layer = layersByID[model.identifier], let timeline = model.timeline else { continue }
            layer.add(animation(for: model, timeline: timeline, repeats: true), forKey: "sprite-loop")
        }
        if document.formatVersion == 2 { schedulePerformanceWake(); return }
        for group in document.encounterGroups {
            encounterOrders[group.identifier] = seededOrder(group.layerIDs, seed: group.seed)
            encounterIndices[group.identifier] = 0
            showNextEncounter(in: group)
            encounterTimers.append(Timer.scheduledTimer(withTimeInterval: group.interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.showNextEncounter(in: group) }
            })
        }
    }

    private func stopAnimations() {
        if document?.formatVersion == 2, isRunning {
            performanceClock = activeTime
            clockStartedAt = nil
            sceneLayer.timeOffset = sceneLayer.convertTime(CACurrentMediaTime(), from: nil)
            sceneLayer.speed = 0
            performanceTimer?.invalidate()
            performanceTimer = nil
            isRunning = false
            applyPersistentVisibility(animated: false)
            return
        }
        isRunning = false
        encounterTimers.forEach { $0.invalidate() }
        encounterTimers.removeAll()
        for (identifier, layer) in layersByID {
            layer.removeAllAnimations()
            guard let model = modelByID[identifier] else { continue }
            layer.frame = model.frame.cgRect
            layer.transform = CATransform3DIdentity
            layer.opacity = baseOpacity(for: model)
        }
        applyPersistentVisibility(animated: false)
    }

    private func applyPersistentVisibility(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for model in modelByID.values {
            let target: Float
            switch model.role {
            case .persistentSongFavorite: target = isSongFavorite ? 1 : 0
            case .persistentChannelFavorite: target = isChannelFavorite ? 1 : 0
            default: continue
            }
            guard let layer = layersByID[model.identifier] else { continue }
            if !animated { layer.removeAnimation(forKey: "persistent-fade") }
            guard layer.opacity != target else { continue }
            if animated {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
                fade.toValue = target
                fade.duration = 0.22
                fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(fade, forKey: "persistent-fade")
            }
            layer.opacity = target
        }
    }

    private func play(_ event: SkinMotionEvent) {
        if document?.formatVersion == 2 { playPerformanceEvent(event); return }
        for model in modelByID.values where model.role == .event && model.event == event {
            guard let layer = layersByID[model.identifier], let timeline = model.timeline else { continue }
            layer.removeAnimation(forKey: "sprite-event")
            layer.add(animation(for: model, timeline: timeline, repeats: false), forKey: "sprite-event")
        }
    }

    private func showNextEncounter(in group: SpriteMotionSceneDocument.EncounterGroup) {
        guard isRunning,
              let order = encounterOrders[group.identifier],
              !order.isEmpty
        else { return }
        let index = encounterIndices[group.identifier, default: 0] % order.count
        encounterIndices[group.identifier] = index + 1
        let identifier = order[index]
        guard let model = modelByID[identifier],
              let layer = layersByID[identifier],
              let timeline = model.timeline
        else { return }
        layer.removeAnimation(forKey: "sprite-encounter")
        layer.add(animation(for: model, timeline: timeline, repeats: false), forKey: "sprite-encounter")
    }

    private func animation(
        for model: SpriteMotionSceneDocument.Layer,
        timeline: [SpriteMotionSceneDocument.Keyframe],
        repeats: Bool
    ) -> CAAnimationGroup {
        let duration = max(0.01, timeline.last?.time ?? 0.01)
        let keyTimes = timeline.map { NSNumber(value: $0.time / duration) }
        let timingFunctions = timeline.dropLast().map(timingFunction)
        let center = CGPoint(x: model.frame.cgRect.midX, y: model.frame.cgRect.midY)

        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = timeline.map {
            CGPoint(x: center.x + CGFloat($0.x), y: center.y + CGFloat($0.y))
        }
        position.keyTimes = keyTimes
        position.timingFunctions = timingFunctions

        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = timeline.map { keyframe -> NSValue in
            var value = CATransform3DMakeScale(CGFloat(keyframe.scaleX), CGFloat(keyframe.scaleY), 1)
            value = CATransform3DRotate(value, CGFloat(keyframe.rotation * .pi / 180), 0, 0, 1)
            return NSValue(caTransform3D: value)
        }
        transform.keyTimes = keyTimes
        transform.timingFunctions = timingFunctions

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = timeline.map { NSNumber(value: $0.opacity) }
        opacity.keyTimes = keyTimes
        opacity.timingFunctions = timingFunctions

        let group = CAAnimationGroup()
        group.animations = [position, transform, opacity]
        group.duration = duration
        group.repeatCount = repeats ? .infinity : 0
        group.isRemovedOnCompletion = true
        return group
    }

    private func timingFunction(_ keyframe: SpriteMotionSceneDocument.Keyframe) -> CAMediaTimingFunction {
        switch keyframe.easing {
        case .linear: CAMediaTimingFunction(name: .linear)
        case .easeIn: CAMediaTimingFunction(name: .easeIn)
        case .easeOut: CAMediaTimingFunction(name: .easeOut)
        case .easeInOut: CAMediaTimingFunction(name: .easeInEaseOut)
        }
    }

    private func baseOpacity(for model: SpriteMotionSceneDocument.Layer) -> Float {
        switch model.role {
        case .encounter, .performance, .event, .persistentSongFavorite, .persistentChannelFavorite: 0
        case .backdrop, .subject, .effect: Float(model.timeline?.first?.opacity ?? 1)
        }
    }

    private var activeTime: Double {
        performanceClock + (clockStartedAt.map { max(0, CACurrentMediaTime() - $0) } ?? 0)
    }

    private var performanceContext: ScenePerformanceDirector.Context {
        .init(songFavorite: isSongFavorite, channelFavorite: isChannelFavorite)
    }

    private func schedulePerformanceWake() {
        performanceTimer?.invalidate()
        performanceTimer = nil
        guard isRunning, let director = performanceDirector,
              let delay = director.nextWakeDelay(activeTime: activeTime, context: performanceContext) else { return }
        let timer = Timer(timeInterval: max(delay, eventBusyUntil - activeTime, 0.01), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.wakePerformance() }
        }
        timer.tolerance = min(0.25, delay * 0.05)
        RunLoop.main.add(timer, forMode: .common)
        performanceTimer = timer
    }

    private func wakePerformance() {
        guard isRunning else { return }
        let now = activeTime
        if now >= eventBusyUntil,
           let selection = performanceDirector?.next(activeTime: now, context: performanceContext),
           let performance = document?.performances?.first(where: { $0.identifier == selection.identifier }) {
            runPerformance(performance)
            activeVisitor = (performance.identifier, selection.endsAt)
#if CANIS97_ANIMATION_ACCEPTANCE
            FileHandle.standardOutput.write(Data("OFFLINE-PERFORMANCE: active=\(now) id=\(performance.identifier) ends=\(selection.endsAt)\n".utf8))
#endif
        }
        schedulePerformanceWake()
    }

    private func runPerformance(_ performance: SpriteMotionSceneDocument.Performance) {
        let start = sceneLayer.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for track in performance.tracks {
            guard let layer = layersByID[track.layerID], let model = modelByID[track.layerID] else { continue }
            let group = animation(for: model, timeline: track.timeline, repeats: false)
            group.beginTime = start
            if let cycle = track.poseCycle, let atlas = model.atlas {
                let pose = CAKeyframeAnimation(keyPath: "contentsRect")
                // Discrete rectangles avoid blending neighboring atlas cells.
                // Discrete animation uses N values and N+1 interval boundaries.
                // A finite sequence holds its last cell when its duration ends.
                pose.values = cycle.frames.map { NSValue(rect: atlasRect($0, atlas: atlas)) }
                pose.keyTimes = (0 ... cycle.frames.count).map { NSNumber(value: Double($0) / Double(cycle.frames.count)) }
                pose.calculationMode = .discrete
                pose.duration = Double(cycle.frames.count) / cycle.framesPerSecond
                pose.repeatCount = cycle.loops ? .infinity : 0
                pose.fillMode = .forwards
                pose.isRemovedOnCompletion = false
                group.animations = (group.animations ?? []) + [pose]
            }
            layer.add(group, forKey: "sprite-performance")
        }
        CATransaction.commit()
    }

    private func atlasRect(_ frame: Int, atlas: SpriteMotionSceneDocument.Atlas) -> CGRect {
        CGRect(x: Double(frame % atlas.columns) / Double(atlas.columns),
               y: Double(frame / atlas.columns) / Double(atlas.rows),
               width: 1 / Double(atlas.columns), height: 1 / Double(atlas.rows))
    }

    private func playPerformanceEvent(_ event: SkinMotionEvent) {
        cancelStalePerformanceEvents()
        guard let candidates = document?.performances?.filter({ $0.event == event }), !candidates.isEmpty else { return }
        // One transient event at a time. Repeated input replaces it immediately;
        // no deferred celebrations survive newer host truth.
        for p in document?.performances ?? [] where p.event != nil {
            for track in p.tracks { layersByID[track.layerID]?.removeAnimation(forKey: "sprite-performance") }
        }
        let index = eventVariantIndices[event, default: 0] % candidates.count
        eventVariantIndices[event] = index + 1
        runPerformance(candidates[index])
        eventBusyUntil = activeTime + candidates[index].duration + 2
        schedulePerformanceWake()
    }

    private func cancelStalePerformanceEvents() {
        for p in document?.performances ?? [] {
            let obsolete: Bool
            switch p.event {
            case .songFavoriteAdded: obsolete = !isSongFavorite
            case .songFavoriteRemoved: obsolete = isSongFavorite
            case .channelFavoriteAdded: obsolete = !isChannelFavorite
            case .channelFavoriteRemoved: obsolete = isChannelFavorite
            default: obsolete = false
            }
            if obsolete { for track in p.tracks { layersByID[track.layerID]?.removeAnimation(forKey: "sprite-performance") } }
            if let activeVisitor, activeVisitor.identifier == p.identifier, activeVisitor.endsAt > activeTime,
               (p.requiresSongFavorite.map { $0 != isSongFavorite } ?? false) ||
                (p.requiresChannelFavorite.map { $0 != isChannelFavorite } ?? false) {
                for track in p.tracks { layersByID[track.layerID]?.removeAnimation(forKey: "sprite-performance") }
                self.activeVisitor = nil
            }
        }
    }

    private func seededOrder(_ values: [String], seed: UInt64) -> [String] {
        guard values.count > 1 else { return values }
        var result = values
        var state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            result.swapAt(index, Int(state % UInt64(index + 1)))
        }
        return result
    }
}

/// This deliberately tiny adapter is the only Lottie-shaped data producer in
/// the app. It builds a closed composition from the revalidated canonical
/// model, so Lottie never sees imported source JSON or a network URL.
private enum CanonicalLottieAdapter {
    static func animation(from document: CanonicalMotionDocument) throws -> LottieAnimation {
        let endFrame = max(1, document.frameRate * document.duration)
        let root: [String: Any] = [
            "v": "5.7.4",
            "fr": document.frameRate,
            "ip": 0,
            "op": endFrame,
            "w": Int(document.canvas.width),
            "h": Int(document.canvas.height),
            "nm": "Canis97 Canonical Motion",
            "layers": document.layers.enumerated().map { index, layer in
                makeLayer(layer, index: index, canvas: document.canvas, endFrame: endFrame)
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        return try LottieAnimation.from(data: data)
    }

    private static func makeLayer(
        _ layer: CanonicalMotionLayer,
        index: Int,
        canvas: CanonicalMotionCanvas,
        endFrame: Double
    ) -> [String: Any] {
        let transform: [String: Any] = [
            "o": opacityProperty(for: layer),
            "r": value(layer.transform.rotation),
            "p": vector(layer.transform.position.x, layer.transform.position.y, 0),
            "a": vector(0, 0, 0),
            "s": vector(layer.transform.scale.x * 100, layer.transform.scale.y * 100, 100),
        ]
        let base: [String: Any] = [
            "ddd": 0,
            "ind": index + 1,
            "nm": layer.identifier,
            "ip": 0,
            "op": endFrame,
            "st": 0,
            "sr": 1,
            "ks": transform,
        ]
        switch layer.kind {
        case .solid:
            return base.merging([
                "ty": 1,
                "sw": Int(canvas.width),
                "sh": Int(canvas.height),
                "sc": "#000000",
            ]) { _, new in new }
        case .null, .precomposition:
            return base.merging(["ty": 3]) { _, new in new }
        case .shape:
            let shapes = layer.paths.flatMap(makeShape) + [transformShape()]
            return base.merging(["ty": 4, "shapes": shapes]) { _, new in new }
        }
    }

    private static func makeShape(_ path: CanonicalMotionPath) -> [[String: Any]] {
        let vertices = path.points.map { [$0.x, $0.y] }
        let fill = path.fill?.color ?? .init(red: 0.35, green: 0.7, blue: 0.95, alpha: 0.8)
        let pathItem: [String: Any] = [
            "ty": "sh",
            "nm": path.identifier,
            "ks": ["a": 0, "k": [
                "i": Array(repeating: [0, 0], count: vertices.count),
                "o": Array(repeating: [0, 0], count: vertices.count),
                "v": vertices,
                "c": true,
            ]],
        ]
        let fillItem: [String: Any] = [
            "ty": "fl",
            "nm": "\(path.identifier)-fill",
            "c": vector(fill.red, fill.green, fill.blue),
            "o": value(fill.alpha * 100),
        ]
        return [pathItem, fillItem]
    }

    private static func transformShape() -> [String: Any] {
        ["ty": "tr", "p": vector(0, 0, 0), "a": vector(0, 0, 0), "s": vector(100, 100, 100), "r": value(0), "o": value(100)]
    }

    /// Canonical keyframes are strictly validated opacity stops. Translate
    /// only those stops into Lottie's animated transform-opacity property;
    /// the idle/static pose remains the first bounded keyframe at frame zero.
    private static func opacityProperty(for layer: CanonicalMotionLayer) -> [String: Any] {
        guard layer.keyframes.count >= 2 else { return value(layer.opacity * 100) }
        let keyframes = layer.keyframes.enumerated().map { index, keyframe -> [String: Any] in
            var lottieKeyframe: [String: Any] = [
                "t": keyframe.frame,
                "s": [keyframe.value * 100],
            ]
            if index + 1 < layer.keyframes.count {
                let next = layer.keyframes[index + 1]
                lottieKeyframe["e"] = [next.value * 100]
            }
            return lottieKeyframe
        }
        return ["a": 1, "k": keyframes]
    }

    private static func value(_ number: Double) -> [String: Any] { ["a": 0, "k": number] }
    private static func vector(_ x: Double, _ y: Double, _ z: Double) -> [String: Any] { ["a": 0, "k": [x, y, z]] }
}
