import Foundation

public struct CanonicalMotionDocument: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public let formatVersion: Int
    public let canvas: CanonicalMotionCanvas
    public let frameRate: Double
    public let duration: Double
    public let layers: [CanonicalMotionLayer]
    public let precompositions: [CanonicalMotionPrecomposition]
    public let stateBindings: [CanonicalMotionStateBinding]

    public init(
        formatVersion: Int = Self.formatVersion,
        canvas: CanonicalMotionCanvas,
        frameRate: Double,
        duration: Double,
        layers: [CanonicalMotionLayer],
        precompositions: [CanonicalMotionPrecomposition] = [],
        stateBindings: [CanonicalMotionStateBinding] = []
    ) {
        self.formatVersion = formatVersion
        self.canvas = canvas
        self.frameRate = frameRate
        self.duration = duration
        self.layers = layers
        self.precompositions = precompositions
        self.stateBindings = stateBindings
    }
}

public struct CanonicalMotionCanvas: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct CanonicalMotionLayer: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case shape
        case solid
        case null
        case precomposition
    }

    public let identifier: String
    public let kind: Kind
    public let transform: CanonicalMotionTransform
    public let opacity: Double
    public let paths: [CanonicalMotionPath]
    public let masks: [CanonicalMotionMask]
    public let keyframes: [CanonicalMotionKeyframe]
    public let precompositionID: String?

    public init(
        identifier: String,
        kind: Kind,
        transform: CanonicalMotionTransform,
        opacity: Double,
        paths: [CanonicalMotionPath] = [],
        masks: [CanonicalMotionMask] = [],
        keyframes: [CanonicalMotionKeyframe] = [],
        precompositionID: String? = nil
    ) {
        self.identifier = identifier
        self.kind = kind
        self.transform = transform
        self.opacity = opacity
        self.paths = paths
        self.masks = masks
        self.keyframes = keyframes
        self.precompositionID = precompositionID
    }
}

public struct CanonicalMotionPrecomposition: Codable, Equatable, Sendable {
    public let identifier: String
    public let layers: [CanonicalMotionLayer]

    public init(identifier: String, layers: [CanonicalMotionLayer]) {
        self.identifier = identifier
        self.layers = layers
    }
}

public struct CanonicalMotionTransform: Codable, Equatable, Sendable {
    public let position: CanonicalMotionPoint
    public let scale: CanonicalMotionPoint
    public let rotation: Double

    public init(position: CanonicalMotionPoint, scale: CanonicalMotionPoint, rotation: Double) {
        self.position = position
        self.scale = scale
        self.rotation = rotation
    }
}

public struct CanonicalMotionPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CanonicalMotionPath: Codable, Equatable, Sendable {
    public let identifier: String
    public let points: [CanonicalMotionPoint]
    public let fill: CanonicalMotionFill?
    public let stroke: CanonicalMotionStroke?

    public init(
        identifier: String,
        points: [CanonicalMotionPoint],
        fill: CanonicalMotionFill? = nil,
        stroke: CanonicalMotionStroke? = nil
    ) {
        self.identifier = identifier
        self.points = points
        self.fill = fill
        self.stroke = stroke
    }
}

public struct CanonicalMotionFill: Codable, Equatable, Sendable {
    public let color: CanonicalMotionColor

    public init(color: CanonicalMotionColor) {
        self.color = color
    }
}

public struct CanonicalMotionStroke: Codable, Equatable, Sendable {
    public let color: CanonicalMotionColor
    public let width: Double

    public init(color: CanonicalMotionColor, width: Double) {
        self.color = color
        self.width = width
    }
}

public struct CanonicalMotionColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct CanonicalMotionMask: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case add
    }

    public let identifier: String
    public let mode: Mode
    public let opacity: Double

    public init(identifier: String, mode: Mode = .add, opacity: Double) {
        self.identifier = identifier
        self.mode = mode
        self.opacity = opacity
    }
}

public struct CanonicalMotionKeyframe: Codable, Equatable, Sendable {
    /// A point on its containing layer's normalized opacity timeline.
    ///
    /// `value` is retained as the stable serialized field name for format v1,
    /// but it is not a generic animation value: it is always an opacity in
    /// the closed interval `0 ... 1`.
    public let frame: Double
    public let value: Double

    public init(frame: Double, value: Double) {
        self.frame = frame
        self.value = value
    }
}

public enum CanonicalMotionState: String, Codable, CaseIterable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case error
    case reducedMotion
}

public enum CanonicalMotionEvent: String, Codable, CaseIterable, Sendable {
    case activated
    case playbackStarted
    case playbackPaused
    case playbackFailed
    case reduceMotionEnabled
}

public struct CanonicalMotionStateBinding: Codable, Equatable, Sendable {
    public let state: CanonicalMotionState
    public let event: CanonicalMotionEvent
    public let startFrame: Double
    public let endFrame: Double

    public init(state: CanonicalMotionState, event: CanonicalMotionEvent, startFrame: Double, endFrame: Double) {
        self.state = state
        self.event = event
        self.startFrame = startFrame
        self.endFrame = endFrame
    }
}

public struct MotionSafetyLimits: Equatable, Sendable {
    public let maximumCanonicalBytes: Int
    public let maximumLayers: Int
    public let maximumPrecompositions: Int
    public let maximumMasks: Int
    public let maximumPaths: Int
    public let maximumPathPoints: Int
    public let maximumKeyframes: Int
    public let maximumFrameRate: Double
    public let maximumDuration: Double

    public init(
        maximumCanonicalBytes: Int,
        maximumLayers: Int,
        maximumPrecompositions: Int,
        maximumMasks: Int,
        maximumPaths: Int,
        maximumPathPoints: Int,
        maximumKeyframes: Int,
        maximumFrameRate: Double,
        maximumDuration: Double
    ) {
        self.maximumCanonicalBytes = maximumCanonicalBytes
        self.maximumLayers = maximumLayers
        self.maximumPrecompositions = maximumPrecompositions
        self.maximumMasks = maximumMasks
        self.maximumPaths = maximumPaths
        self.maximumPathPoints = maximumPathPoints
        self.maximumKeyframes = maximumKeyframes
        self.maximumFrameRate = maximumFrameRate
        self.maximumDuration = maximumDuration
    }

    public static let production = Self(
        maximumCanonicalBytes: 512 * 1_024,
        maximumLayers: 64,
        maximumPrecompositions: 4,
        maximumMasks: 32,
        maximumPaths: 1_500,
        maximumPathPoints: 10_000,
        maximumKeyframes: 1_000,
        maximumFrameRate: 30,
        maximumDuration: 10
    )
}

public struct MotionSafetyDiagnostic: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case malformedDocument
        case unknownField
        case forbiddenValue
        case nonFiniteNumber
        case invalidVersion
        case invalidIdentifier
        case canvasLimitExceeded
        case frameRateLimitExceeded
        case durationLimitExceeded
        case canonicalByteLimitExceeded
        case layerLimitExceeded
        case precompositionLimitExceeded
        case maskLimitExceeded
        case pathLimitExceeded
        case pointLimitExceeded
        case keyframeLimitExceeded
        case invalidOpacityTimeline
        case invalidStateBinding
    }

    public let code: Code

    public init(code: Code) {
        self.code = code
    }
}

public enum MotionSafetyError: Error, Equatable, Sendable {
    case rejected(MotionSafetyDiagnostic)

    public var diagnostic: MotionSafetyDiagnostic {
        switch self {
        case let .rejected(diagnostic): diagnostic
        }
    }
}

public struct CanonicalMotionValidator: Sendable {
    public let limits: MotionSafetyLimits

    public init(limits: MotionSafetyLimits = .production) {
        self.limits = limits
    }

    public func validate(_ document: CanonicalMotionDocument) throws -> CanonicalMotionDocument {
        guard document.formatVersion == CanonicalMotionDocument.formatVersion else { throw reject(.invalidVersion) }
        try validateFinite(document.canvas.width, document.canvas.height, document.frameRate, document.duration)
        guard document.canvas.width > 0, document.canvas.height > 0,
              document.canvas.width <= 4_096, document.canvas.height <= 4_096
        else { throw reject(.canvasLimitExceeded) }
        guard document.frameRate > 0, document.frameRate <= limits.maximumFrameRate else { throw reject(.frameRateLimitExceeded) }
        guard document.duration > 0, document.duration <= limits.maximumDuration else { throw reject(.durationLimitExceeded) }
        guard document.precompositions.count <= limits.maximumPrecompositions else { throw reject(.precompositionLimitExceeded) }

        let allLayers = document.layers + document.precompositions.flatMap(\.layers)
        guard allLayers.count <= limits.maximumLayers else { throw reject(.layerLimitExceeded) }

        let layerIDs = allLayers.map(\.identifier)
        let precompositionIDs = document.precompositions.map(\.identifier)
        guard Set(layerIDs).count == layerIDs.count, Set(precompositionIDs).count == precompositionIDs.count else {
            throw reject(.invalidIdentifier)
        }

        for precomposition in document.precompositions {
            try validateIdentifier(precomposition.identifier)
        }

        let maximumFrame = document.duration * document.frameRate
        var maskCount = 0
        var pathCount = 0
        var pointCount = 0
        var keyframeCount = 0
        for layer in allLayers {
            try validateLayer(
                layer,
                knownPrecompositions: Set(precompositionIDs),
                maximumFrame: maximumFrame
            )
            maskCount += layer.masks.count
            pathCount += layer.paths.count
            pointCount += layer.paths.reduce(into: 0) { $0 += $1.points.count }
            keyframeCount += layer.keyframes.count
        }

        guard maskCount <= limits.maximumMasks else { throw reject(.maskLimitExceeded) }
        guard pathCount <= limits.maximumPaths else { throw reject(.pathLimitExceeded) }
        guard pointCount <= limits.maximumPathPoints else { throw reject(.pointLimitExceeded) }
        guard keyframeCount <= limits.maximumKeyframes else { throw reject(.keyframeLimitExceeded) }

        for binding in document.stateBindings {
            try validateFinite(binding.startFrame, binding.endFrame)
            guard binding.startFrame >= 0, binding.endFrame >= binding.startFrame, binding.endFrame <= maximumFrame else {
                throw reject(.invalidStateBinding)
            }
        }

        guard try CanonicalMotionCodec.encodeUnchecked(document).count <= limits.maximumCanonicalBytes else {
            throw reject(.canonicalByteLimitExceeded)
        }
        return document
    }

    private func validateLayer(
        _ layer: CanonicalMotionLayer,
        knownPrecompositions: Set<String>,
        maximumFrame: Double
    ) throws {
        try validateIdentifier(layer.identifier)
        try validateFinite(
            layer.transform.position.x, layer.transform.position.y,
            layer.transform.scale.x, layer.transform.scale.y,
            layer.transform.rotation, layer.opacity
        )
        guard (0 ... 1).contains(layer.opacity) else { throw reject(.forbiddenValue) }
        if layer.kind == .precomposition {
            guard let precompositionID = layer.precompositionID, knownPrecompositions.contains(precompositionID) else {
                throw reject(.forbiddenValue)
            }
        } else if layer.precompositionID != nil {
            throw reject(.forbiddenValue)
        }
        for path in layer.paths {
            try validateIdentifier(path.identifier)
            for point in path.points {
                try validateFinite(point.x, point.y)
            }
            if let fill = path.fill {
                try validateColor(fill.color)
            }
            if let stroke = path.stroke {
                try validateColor(stroke.color)
                try validateFinite(stroke.width)
                guard stroke.width >= 0, stroke.width <= 1_024 else { throw reject(.forbiddenValue) }
            }
            guard path.fill != nil || path.stroke != nil else { throw reject(.forbiddenValue) }
        }
        for mask in layer.masks {
            try validateIdentifier(mask.identifier)
            try validateFinite(mask.opacity)
            guard (0 ... 1).contains(mask.opacity) else { throw reject(.forbiddenValue) }
        }
        guard layer.keyframes.isEmpty || layer.keyframes.count >= 2 else {
            throw reject(.invalidOpacityTimeline)
        }
        var previousFrame: Double?
        for keyframe in layer.keyframes {
            try validateFinite(keyframe.frame, keyframe.value)
            guard keyframe.frame >= 0, keyframe.frame <= maximumFrame,
                  (0 ... 1).contains(keyframe.value),
                  previousFrame.map({ keyframe.frame > $0 }) ?? true
            else { throw reject(.invalidOpacityTimeline) }
            previousFrame = keyframe.frame
        }
    }

    private func validateColor(_ color: CanonicalMotionColor) throws {
        try validateFinite(color.red, color.green, color.blue, color.alpha)
        guard (0 ... 1).contains(color.red), (0 ... 1).contains(color.green),
              (0 ... 1).contains(color.blue), (0 ... 1).contains(color.alpha)
        else { throw reject(.forbiddenValue) }
    }

    private func validateIdentifier(_ identifier: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard !identifier.isEmpty, identifier.utf8.count <= 64,
              identifier.unicodeScalars.allSatisfy(allowed.contains)
        else { throw reject(.invalidIdentifier) }
    }

    private func validateFinite(_ values: Double...) throws {
        guard values.allSatisfy(\.isFinite) else { throw reject(.nonFiniteNumber) }
    }

    private func reject(_ code: MotionSafetyDiagnostic.Code) -> MotionSafetyError {
        .rejected(.init(code: code))
    }
}

public enum CanonicalMotionCodec {
    public static func decode(_ data: Data, limits: MotionSafetyLimits = .production) throws -> CanonicalMotionDocument {
        guard data.count <= limits.maximumCanonicalBytes else {
            throw MotionSafetyError.rejected(.init(code: .canonicalByteLimitExceeded))
        }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw MotionSafetyError.rejected(.init(code: .malformedDocument))
        }
        try CanonicalMotionJSONSchema.validate(raw)
        do {
            return try CanonicalMotionValidator(limits: limits).validate(JSONDecoder().decode(CanonicalMotionDocument.self, from: data))
        } catch let error as MotionSafetyError {
            throw error
        } catch {
            throw MotionSafetyError.rejected(.init(code: .malformedDocument))
        }
    }

    public static func encode(_ document: CanonicalMotionDocument, limits: MotionSafetyLimits = .production) throws -> Data {
        _ = try CanonicalMotionValidator(limits: limits).validate(document)
        return try encodeUnchecked(document)
    }

    fileprivate static func encodeUnchecked(_ document: CanonicalMotionDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
}

private enum CanonicalMotionJSONSchema {
    static func validate(_ value: Any) throws {
        try validateDocument(value)
    }

    private static func validateDocument(_ value: Any) throws {
        let object = try dictionary(value, allowed: ["formatVersion", "canvas", "frameRate", "duration", "layers", "precompositions", "stateBindings"])
        try validateCanvas(required(object, "canvas"))
        try array(required(object, "layers")).forEach(validateLayer)
        try array(required(object, "precompositions")).forEach(validatePrecomposition)
        try array(required(object, "stateBindings")).forEach(validateStateBinding)
    }

    private static func validateCanvas(_ value: Any) throws {
        _ = try dictionary(value, allowed: ["width", "height"])
    }

    private static func validatePrecomposition(_ value: Any) throws {
        let object = try dictionary(value, allowed: ["identifier", "layers"])
        try array(required(object, "layers")).forEach(validateLayer)
    }

    private static func validateLayer(_ value: Any) throws {
        let object = try dictionary(value, allowed: ["identifier", "kind", "transform", "opacity", "paths", "masks", "keyframes", "precompositionID"])
        try validateTransform(required(object, "transform"))
        try array(required(object, "paths")).forEach(validatePath)
        try array(required(object, "masks")).forEach(validateMask)
        try array(required(object, "keyframes")).forEach(validateKeyframe)
    }

    private static func validateTransform(_ value: Any) throws {
        let object = try dictionary(value, allowed: ["position", "scale", "rotation"])
        try validatePoint(required(object, "position"))
        try validatePoint(required(object, "scale"))
    }

    private static func validatePath(_ value: Any) throws {
        let object = try dictionary(value, allowed: ["identifier", "points", "fill", "stroke"])
        try array(required(object, "points")).forEach(validatePoint)
        if let fill = object["fill"] as? [String: Any] { try validateFill(fill) }
        if let stroke = object["stroke"] as? [String: Any] { try validateStroke(stroke) }
    }

    private static func validatePoint(_ value: Any) throws {
        _ = try dictionary(value, allowed: ["x", "y"])
    }

    private static func validateFill(_ value: [String: Any]) throws {
        try rejectUnknown(value, allowed: ["color"])
        try validateColor(required(value, "color"))
    }

    private static func validateStroke(_ value: [String: Any]) throws {
        try rejectUnknown(value, allowed: ["color", "width"])
        try validateColor(required(value, "color"))
    }

    private static func validateColor(_ value: Any) throws {
        _ = try dictionary(value, allowed: ["red", "green", "blue", "alpha"])
    }

    private static func validateMask(_ value: Any) throws {
        _ = try dictionary(value, allowed: ["identifier", "mode", "opacity"])
    }

    private static func validateKeyframe(_ value: Any) throws {
        _ = try dictionary(value, allowed: ["frame", "value"])
    }

    private static func validateStateBinding(_ value: Any) throws {
        _ = try dictionary(value, allowed: ["state", "event", "startFrame", "endFrame"])
    }

    private static func dictionary(_ value: Any, allowed: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw malformed() }
        try rejectUnknown(object, allowed: allowed)
        return object
    }

    private static func array(_ value: Any) throws -> [Any] {
        guard let array = value as? [Any] else { throw malformed() }
        return array
    }

    private static func required(_ object: [String: Any], _ key: String) throws -> Any {
        guard let value = object[key] else { throw malformed() }
        return value
    }

    private static func rejectUnknown(_ object: [String: Any], allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else {
            throw MotionSafetyError.rejected(.init(code: .unknownField))
        }
    }

    private static func malformed() -> MotionSafetyError {
        .rejected(.init(code: .malformedDocument))
    }
}

extension CanonicalMotionDocument {
    static func fixture(
        layers: Int = 1,
        precompositions: Int = 0,
        masks: Int = 0,
        paths: Int = 1,
        points: Int = 3,
        keyframes: Int = 0,
        frameRate: Double = 30,
        duration: Double = 1
    ) -> Self {
        let fill = CanonicalMotionFill(color: .init(red: 1, green: 0, blue: 0, alpha: 1))
        let pathValues = (0 ..< paths).map { pathIndex in
            let start = (points * pathIndex) / paths
            let end = (points * (pathIndex + 1)) / paths
            let pointValues = (start ..< end).map { CanonicalMotionPoint(x: Double($0), y: Double($0)) }
            return CanonicalMotionPath(identifier: "path_\(pathIndex)", points: pointValues, fill: fill)
        }
        let maskValues = (0 ..< masks).map { CanonicalMotionMask(identifier: "mask_\($0)", opacity: 1) }
        let maximumFrame = duration * frameRate
        var remainingKeyframes = keyframes
        let rootLayers = (0 ..< layers).map { index in
            let remainingLayers = layers - index
            let keyframeCount = remainingLayers == 0 ? 0 : (remainingKeyframes + remainingLayers - 1) / remainingLayers
            remainingKeyframes -= keyframeCount
            let keyframeValues: [CanonicalMotionKeyframe]
            if keyframeCount <= 1 {
                keyframeValues = keyframeCount == 0 ? [] : [.init(frame: 0, value: 1)]
            } else {
                keyframeValues = (0 ..< keyframeCount).map { keyframeIndex in
                    let progress = Double(keyframeIndex) / Double(keyframeCount - 1)
                    return .init(frame: maximumFrame * progress, value: progress)
                }
            }
            return CanonicalMotionLayer(
                identifier: "layer_\(index)",
                kind: .shape,
                transform: .init(position: .init(x: 0, y: 0), scale: .init(x: 1, y: 1), rotation: 0),
                opacity: 1,
                paths: index == 0 ? pathValues : [],
                masks: index == 0 ? maskValues : [],
                keyframes: keyframeValues
            )
        }
        return Self(
            canvas: .init(width: 100, height: 100),
            frameRate: frameRate,
            duration: duration,
            layers: rootLayers,
            precompositions: (0 ..< precompositions).map { .init(identifier: "precomp_\($0)", layers: []) }
        )
    }
}
