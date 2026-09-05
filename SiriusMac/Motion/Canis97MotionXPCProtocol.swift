import Canis97MotionSafety
import Foundation

@objc(Canis97MotionXPCProtocol)
protocol Canis97MotionXPCProtocol {
    func convert(_ request: Data, withReply reply: @escaping (Data) -> Void)
}

enum Canis97MotionConversionFailure: String, Codable, Sendable {
    case oversizedInput
    case unsupportedSource
    case transportFailure
    case malformedReply
    case interrupted
    case invalidated
    case timedOut
    case cancelled
    case validationFailed
}

struct Canis97MotionConversionReply: Codable, Sendable {
    let canonicalData: Data?
    let diagnostic: MotionSafetyDiagnostic?
    let failure: Canis97MotionConversionFailure?

    static func success(canonicalData: Data, diagnostic: MotionSafetyDiagnostic? = nil) -> Self {
        Self(canonicalData: canonicalData, diagnostic: diagnostic, failure: nil)
    }

    static func failure(_ failure: Canis97MotionConversionFailure, diagnostic: MotionSafetyDiagnostic? = nil) -> Self {
        Self(canonicalData: nil, diagnostic: diagnostic, failure: failure)
    }
}
