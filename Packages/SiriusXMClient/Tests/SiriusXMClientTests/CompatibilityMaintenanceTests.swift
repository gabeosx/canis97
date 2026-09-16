import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Sanitized compatibility maintenance")
struct CompatibilityMaintenanceTests {
    @Test("a strict internal adapter preserves its closed semantic result for a sanitized structure")
    func playbackKeyStructureRemainsAClosedAdapterContract() {
        let repairedShape = NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"keyId":"synthetic-key-id","key":"synthetic-key-material"}"#.utf8)
        )
        let driftedShape = NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"keyId":"synthetic-key-id","key":"synthetic-key-material","revision":"unexpected"}"#.utf8)
        )

        #expect(LiveListeningAdapter.inspectPlaybackKey(repairedShape) == .accepted)
        #expect(LiveListeningAdapter.inspectPlaybackKey(driftedShape) == .unsupported(.playbackKeyUnexpectedShape))
    }

    @Test("fixture promotion rejects provider-sensitive values before a structural fixture is kept")
    func fixturePromotionRejectsProviderSensitiveValues() {
        let rawLikeStructure = Data(#"{"outer":{"authorization":"synthetic-authorization"}}"#.utf8)

        #expect(throws: DiagnosticRedactionError.self) {
            try DiagnosticRedactor.promoteSyntheticFixture(rawLikeStructure)
        }
    }
}
