import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Safe diagnostics and fixtures")
struct RedactionTests {
    private let canary = "canary-token-cookie-authorization-url-account-request-response-error"

    @Test("diagnostic events expose only closed semantic values")
    func eventIsSafeByConstruction() {
        let event = SafeDiagnosticEvent(
            operation: .nativeAuthentication,
            outcome: .unsupported,
            handle: SafeDiagnosticHandle()
        )

        #expect(event.rendered == "native-authentication:unsupported")
        #expect(!event.rendered.contains(canary))
    }

    @Test("every diagnostic outcome renders as fixed labels only")
    func allDiagnosticOutcomesAreBounded() {
        for outcome in SafeDiagnosticOutcome.allCases {
            let event = SafeDiagnosticEvent(
                operation: .nativeAuthentication,
                outcome: outcome,
                handle: SafeDiagnosticHandle()
            )

            #expect(event.rendered.range(of: #"^[a-z-]+:[a-z-]+$"#, options: .regularExpression) != nil)
            #expect(!event.rendered.contains(canary))
        }
    }

    @Test("safe event and fixture representations exclude secret canaries")
    func representationsExcludeCanaries() throws {
        let event = SafeDiagnosticEvent(
            operation: .entitlement,
            outcome: .rejected,
            handle: SafeDiagnosticHandle()
        )
        let fixture = try DiagnosticRedactor.promoteSyntheticFixture(
            Data(#"{"operation":"entitlement","outcome":"rejected","label":"synthetic"}"#.utf8)
        )

        let representations = [event.rendered, String(decoding: fixture, as: UTF8.self)]
        for representation in representations {
            #expect(!representation.contains(canary))
        }
    }

    @Test("sensitive keys are rejected recursively before fixture promotion")
    func sensitiveKeysCannotBecomeFixtures() {
        let unsafeFixture = Data(#"{"outer":{"authorization":"canary-token-cookie-authorization-url-account-request-response-error"}}"#.utf8)

        #expect(throws: DiagnosticRedactionError.self) {
            try DiagnosticRedactor.promoteSyntheticFixture(unsafeFixture)
        }
    }

    @Test("sensitive values are rejected before fixture promotion")
    func sensitiveValuesCannotBecomeFixtures() {
        let unsafeFixture = Data(#"{"label":"canary-token-cookie-authorization-url-account-request-response-error"}"#.utf8)

        #expect(throws: DiagnosticRedactionError.self) {
            try DiagnosticRedactor.promoteSyntheticFixture(unsafeFixture)
        }
    }
}
