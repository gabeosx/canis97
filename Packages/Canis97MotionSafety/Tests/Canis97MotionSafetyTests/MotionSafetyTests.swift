import Foundation
import Testing
@testable import Canis97MotionSafety

@Suite("canonical motion safety")
struct MotionSafetyTests {
    @Test("documents exactly at every production limit are accepted")
    func acceptsDocumentsAtProductionLimits() throws {
        let limits = MotionSafetyLimits.production
        let document = CanonicalMotionDocument.fixture(
            layers: limits.maximumLayers,
            precompositions: limits.maximumPrecompositions,
            masks: limits.maximumMasks,
            paths: limits.maximumPaths,
            points: limits.maximumPathPoints,
            keyframes: limits.maximumKeyframes,
            frameRate: limits.maximumFrameRate,
            duration: limits.maximumDuration
        )

        #expect(try CanonicalMotionValidator(limits: limits).validate(document) == document)
    }

    @Test("one unit over any production limit returns a stable diagnostic")
    func rejectsDocumentsOverProductionLimits() throws {
        let limits = MotionSafetyLimits.production
        let candidates: [(CanonicalMotionDocument, MotionSafetyDiagnostic.Code)] = [
            (.fixture(layers: limits.maximumLayers + 1), .layerLimitExceeded),
            (.fixture(precompositions: limits.maximumPrecompositions + 1), .precompositionLimitExceeded),
            (.fixture(masks: limits.maximumMasks + 1), .maskLimitExceeded),
            (.fixture(paths: limits.maximumPaths + 1), .pathLimitExceeded),
            (.fixture(paths: 1, points: limits.maximumPathPoints + 1), .pointLimitExceeded),
            (
                .fixture(
                    layers: limits.maximumLayers,
                    keyframes: limits.maximumKeyframes + 1,
                    frameRate: limits.maximumFrameRate,
                    duration: limits.maximumDuration
                ),
                .keyframeLimitExceeded
            ),
            (.fixture(frameRate: limits.maximumFrameRate + 1), .frameRateLimitExceeded),
            (.fixture(duration: limits.maximumDuration + 1), .durationLimitExceeded),
        ]

        for (document, expectedCode) in candidates {
            #expect(throws: MotionSafetyError.self) {
                try CanonicalMotionValidator(limits: limits).validate(document)
            }
            #expect(try failureCode(for: document, limits: limits) == expectedCode)
        }

        #expect(throws: MotionSafetyError.self) {
            try CanonicalMotionCodec.decode(Data(repeating: 0x20, count: limits.maximumCanonicalBytes + 1), limits: limits)
        }
    }

    @Test("codec rejects unknown and executable-looking input")
    func rejectsUnknownAndExecutableInput() throws {
        let unknown = Data("""
        {"formatVersion":1,"canvas":{"width":1,"height":1},"frameRate":30,"duration":1,"layers":[],"precompositions":[],"stateBindings":[],"expression":"valueAtTime()"}
        """.utf8)
        let traversal = Data("""
        {"formatVersion":1,"canvas":{"width":1,"height":1},"frameRate":30,"duration":1,"layers":[{"identifier":"../asset","kind":"shape","transform":{"position":{"x":0,"y":0},"scale":{"x":1,"y":1},"rotation":0},"opacity":1,"paths":[],"masks":[],"keyframes":[]}],"precompositions":[],"stateBindings":[]}
        """.utf8)

        #expect(throws: MotionSafetyError.self) { try CanonicalMotionCodec.decode(unknown) }
        #expect(throws: MotionSafetyError.self) { try CanonicalMotionCodec.decode(traversal) }
    }

    @Test("codec is deterministic and rejects malformed or non-finite input")
    func encodesDeterministicallyAndFailsClosed() throws {
        let document = CanonicalMotionDocument.fixture()
        let first = try CanonicalMotionCodec.encode(document)
        let second = try CanonicalMotionCodec.encode(document)
        let malformed = Data("{not-json}".utf8)
        let nonFinite = Data("""
        {"formatVersion":1,"canvas":{"width":1,"height":1},"frameRate":1e999,"duration":1,"layers":[],"precompositions":[],"stateBindings":[]}
        """.utf8)

        #expect(first == second)
        #expect(throws: MotionSafetyError.self) { try CanonicalMotionCodec.decode(malformed) }
        #expect(throws: MotionSafetyError.self) { try CanonicalMotionCodec.decode(nonFinite) }
    }

    @Test("keyframes are a bounded, normalized opacity timeline")
    func validatesRestrictedOpacityTimelines() throws {
        let validator = CanonicalMotionValidator()
        let valid = opacityDocument([
            .init(frame: 0, value: 0),
            .init(frame: 15, value: 0.5),
            .init(frame: 30, value: 1),
        ])

        #expect(try validator.validate(valid) == valid)

        let invalidTimelines: [[CanonicalMotionKeyframe]] = [
            [.init(frame: 0, value: 1)],
            [.init(frame: 0, value: 0), .init(frame: 0, value: 1)],
            [.init(frame: 10, value: 0), .init(frame: 9, value: 1)],
            [.init(frame: -1, value: 0), .init(frame: 30, value: 1)],
            [.init(frame: 0, value: 0), .init(frame: 31, value: 1)],
            [.init(frame: 0, value: -0.01), .init(frame: 30, value: 1)],
            [.init(frame: 0, value: 0), .init(frame: 30, value: 1.01)],
        ]

        for timeline in invalidTimelines {
            #expect(try failureCode(for: opacityDocument(timeline), limits: .production) == .invalidOpacityTimeline)
        }

        #expect(try failureCode(
            for: opacityDocument([.init(frame: .infinity, value: 0), .init(frame: 30, value: 1)]),
            limits: .production
        ) == .nonFiniteNumber)
    }

    private func failureCode(
        for document: CanonicalMotionDocument,
        limits: MotionSafetyLimits
    ) throws -> MotionSafetyDiagnostic.Code {
        do {
            _ = try CanonicalMotionValidator(limits: limits).validate(document)
            throw TestFailure.expectedValidationFailure
        } catch let error as MotionSafetyError {
            return error.diagnostic.code
        }
    }

    private func opacityDocument(_ keyframes: [CanonicalMotionKeyframe]) -> CanonicalMotionDocument {
        .init(
            canvas: .init(width: 100, height: 100),
            frameRate: 30,
            duration: 1,
            layers: [
                .init(
                    identifier: "opacity",
                    kind: .shape,
                    transform: .init(position: .init(x: 0, y: 0), scale: .init(x: 1, y: 1), rotation: 0),
                    opacity: 1,
                    keyframes: keyframes
                ),
            ]
        )
    }
}

private enum TestFailure: Error {
    case expectedValidationFailure
}
