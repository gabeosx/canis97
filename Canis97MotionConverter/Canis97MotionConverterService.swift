import Canis97MotionSafety
import Foundation
import Lottie

@main
enum Canis97MotionConverterServiceMain {
    static func main() {
        let listener = NSXPCListener.service()
        let delegate = Canis97MotionConverterServiceDelegate()
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
    }
}

private final class Canis97MotionConverterServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: Canis97MotionXPCProtocol.self)
        connection.exportedObject = Canis97MotionConverterService()
        connection.resume()
        return true
    }
}

final class Canis97MotionConverterService: NSObject, Canis97MotionXPCProtocol {
    private static let maximumRequestBytes = 6 * 1_024 * 1_024

    func convert(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        let response: Canis97MotionConversionReply
        if request.count > Self.maximumRequestBytes {
            response = .failure(.oversizedInput, diagnostic: .init(code: .canonicalByteLimitExceeded))
        } else {
            response = Self.convertRestrictedLottie(request)
        }
        reply(Self.encode(response))
    }

    private static func convertRestrictedLottie(_ request: Data) -> Canis97MotionConversionReply {
        do {
            let source = try RestrictedLottieSource(data: request)
            // Keep Lottie's decoder private to this credential-free service. The
            // source tree was structurally allowlisted before this parse, and no
            // Lottie value leaves the service.
            _ = try LottieAnimation.from(data: request)
            let canonical = try CanonicalMotionCodec.encode(source.canonicalDocument)
            return .success(canonicalData: canonical)
        } catch let error as MotionSafetyError {
            return .failure(.validationFailed, diagnostic: error.diagnostic)
        } catch {
            return .failure(.unsupportedSource)
        }
    }

    private static func encode(_ reply: Canis97MotionConversionReply) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(reply)) ?? Data()
    }
}

/// A narrow Lottie intake. It accepts only a flat, local shape/solid/null
/// document with a static opacity or a linear opacity timeline, and emits one
/// deterministic Canis97 document. Effects, masks, expressions, assets, fonts,
/// images, URLs, and unknown source forms fail closed.
private struct RestrictedLottieSource {
    let canonicalDocument: CanonicalMotionDocument

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys).isSubset(of: ["v", "fr", "ip", "op", "w", "h", "layers"]),
              let frameRate = Self.number(root["fr"]),
              let start = Self.number(root["ip"]),
              let end = Self.number(root["op"]),
              let width = Self.number(root["w"]),
              let height = Self.number(root["h"]),
              let sourceLayers = root["layers"] as? [[String: Any]],
              frameRate.isFinite, start.isFinite, end.isFinite,
              width.isFinite, height.isFinite, frameRate > 0, end > start
        else { throw MotionSafetyError.rejected(.init(code: .malformedDocument)) }

        let layers: [CanonicalMotionLayer] = try sourceLayers.enumerated().map { index, layer in
            guard Set(layer.keys).isSubset(of: ["ty", "ind", "ks"]),
                  let type = Self.integer(layer["ty"]),
                  [1, 3, 4].contains(type),
                  let identifier = Self.integer(layer["ind"])
            else { throw MotionSafetyError.rejected(.init(code: .unknownField)) }
            let kind: CanonicalMotionLayer.Kind = switch type {
            case 1: .solid
            case 3: .null
            default: .shape
            }
            let opacity = try Self.opacity(
                from: layer["ks"],
                sourceStartFrame: start,
                maximumSourceFrame: end - start
            )
            return CanonicalMotionLayer(
                identifier: "layer_\(identifier)_\(index)",
                kind: kind,
                transform: .init(position: .init(x: 0, y: 0), scale: .init(x: 1, y: 1), rotation: 0),
                opacity: opacity.initialValue,
                keyframes: opacity.keyframes
            )
        }
        canonicalDocument = .init(
            canvas: .init(width: width, height: height),
            frameRate: frameRate,
            duration: (end - start) / frameRate,
            layers: layers
        )
        _ = try CanonicalMotionValidator().validate(canonicalDocument)
    }

    private struct OpacityTimeline {
        let initialValue: Double
        let keyframes: [CanonicalMotionKeyframe]
    }

    private static func opacity(
        from transformValue: Any?,
        sourceStartFrame: Double,
        maximumSourceFrame: Double
    ) throws -> OpacityTimeline {
        guard let transformValue else { return .init(initialValue: 1, keyframes: []) }
        guard let transform = transformValue as? [String: Any] else {
            throw MotionSafetyError.rejected(.init(code: .malformedDocument))
        }
        guard Set(transform.keys).isSubset(of: ["o"]), let opacityValue = transform["o"] as? [String: Any] else {
            throw MotionSafetyError.rejected(.init(code: .unknownField))
        }
        guard Set(opacityValue.keys).isSubset(of: ["a", "k"]),
              let animated = integer(opacityValue["a"]),
              [0, 1].contains(animated)
        else { throw MotionSafetyError.rejected(.init(code: .malformedDocument)) }

        if animated == 0 {
            guard let value = normalizedOpacity(opacityValue["k"]) else {
                throw MotionSafetyError.rejected(.init(code: .invalidOpacityTimeline))
            }
            return .init(initialValue: value, keyframes: [])
        }

        guard let sourceKeyframes = opacityValue["k"] as? [[String: Any]], sourceKeyframes.count >= 2 else {
            throw MotionSafetyError.rejected(.init(code: .invalidOpacityTimeline))
        }

        var previousFrame: Double?
        let keyframes = try sourceKeyframes.map { sourceKeyframe -> (keyframe: CanonicalMotionKeyframe, endValue: Double?) in
            guard Set(sourceKeyframe.keys).isSubset(of: ["t", "s", "e"]),
                  let timestamp = number(sourceKeyframe["t"]),
                  let sourceValues = sourceKeyframe["s"] as? [Any], sourceValues.count == 1,
                  let value = normalizedOpacity(sourceValues[0])
            else { throw MotionSafetyError.rejected(.init(code: .invalidOpacityTimeline)) }

            let endValue: Double?
            if let endValues = sourceKeyframe["e"] {
                guard let endValues = endValues as? [Any], endValues.count == 1,
                      let normalizedEndValue = normalizedOpacity(endValues[0])
                else { throw MotionSafetyError.rejected(.init(code: .invalidOpacityTimeline)) }
                endValue = normalizedEndValue
            } else {
                endValue = nil
            }

            let frame = timestamp - sourceStartFrame
            guard frame >= 0, frame <= maximumSourceFrame,
                  previousFrame.map({ frame > $0 }) ?? true
            else { throw MotionSafetyError.rejected(.init(code: .invalidOpacityTimeline)) }
            previousFrame = frame
            return (.init(frame: frame, value: value), endValue)
        }
        for index in keyframes.indices.dropLast() {
            guard keyframes[index].endValue == nil || keyframes[index].endValue == keyframes[index + 1].keyframe.value else {
                throw MotionSafetyError.rejected(.init(code: .invalidOpacityTimeline))
            }
        }
        guard keyframes.last?.endValue == nil, let initialValue = keyframes.first?.keyframe.value else {
            throw MotionSafetyError.rejected(.init(code: .invalidOpacityTimeline))
        }
        return .init(initialValue: initialValue, keyframes: keyframes.map(\.keyframe))
    }

    private static func normalizedOpacity(_ value: Any?) -> Double? {
        guard let sourceOpacity = number(value), (0 ... 100).contains(sourceOpacity) else { return nil }
        return sourceOpacity / 100
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let value = number(value), value.rounded() == value,
              value >= Double(Int.min), value <= Double(Int.max)
        else { return nil }
        return Int(value)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value, !(value is Bool), let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }
}
