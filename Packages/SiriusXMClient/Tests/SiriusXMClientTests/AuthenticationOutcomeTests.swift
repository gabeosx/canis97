import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Native response classification")
struct AuthenticationOutcomeTests {
    @Test("a representative profile-v4 response remains pending entitlement")
    func authenticationSuccessIsNeverFinalSessionSuccess() {
        let response = response(body: SanitizedNativeResponseFixtures.profileV4Authenticated)

        #expect(AuthenticationFlowAdapter.classifyAuthentication(response) == .authenticatedPendingEntitlement)
    }

    @Test("a representative subscription-v1 response is classified independently")
    func entitlementResponseIsClassifiedSeparately() {
        let entitled = response(body: SanitizedNativeResponseFixtures.subscriptionV1Active)
        let notEntitled = response(body: SanitizedNativeResponseFixtures.subscriptionV1Inactive)

        #expect(AuthenticationFlowAdapter.classifyEntitlement(entitled) == .entitled)
        #expect(AuthenticationFlowAdapter.classifyEntitlement(notEntitled) == .authenticatedButNotEntitled)
    }

    @Test("control and ambiguous native responses fail closed")
    func terminalAndAmbiguousResponsesAreNeverAccepted() {
        let controlResponses = [
            response(statusCode: 403, body: Data("{}".utf8)),
            response(statusCode: 429, body: Data("{}".utf8)),
            response(statusCode: 200, object: ["challenge": "captcha"]),
            response(statusCode: 200, object: ["challenge": "mfa"]),
            response(statusCode: 200, object: ["bot": true]),
            response(body: Data()),
            response(body: Data("[]".utf8)),
            response(body: Data("{".utf8)),
            NativeTransportResponse(statusCode: 200, contentType: "text/html", body: Data("{}".utf8)),
            response(
                statusCode: 200,
                body: SanitizedNativeResponseFixtures.profileV4Authenticated,
                redirectLocation: "https://example.invalid/drift"
            ),
        ]

        for response in controlResponses {
            #expect(AuthenticationFlowAdapter.classifyAuthentication(response).isTerminal)
            #expect(AuthenticationFlowAdapter.classifyAuthentication(response) != .authenticatedPendingEntitlement)
        }
    }

    @Test("subscription status remains exact and fail closed")
    func entitlementAcceptsOnlySettledSubscriptionStatus() {
        let missing = response(object: ["subscription": ["fixture_marker": "missing-status"]])
        let nonString = response(object: ["subscription": ["status": 1]])
        let unknown = response(object: ["subscription": ["status": "fixture-unknown"]])

        #expect(AuthenticationFlowAdapter.classifyEntitlement(missing) == .unsupported)
        #expect(AuthenticationFlowAdapter.classifyEntitlement(nonString) == .unsupported)
        #expect(AuthenticationFlowAdapter.classifyEntitlement(unknown) == .unsupported)
    }

    @Test("diagnostics distinguish safe failure classes without response material")
    func diagnosticsIdentifyTheCompatibilityBoundary() {
        let cases: [(NativeTransportResponse, SafeDiagnosticOutcome)] = [
            (
                NativeTransportResponse(
                    statusCode: 500,
                    contentType: nil,
                    body: Data(),
                    transportFailed: true
                ),
                .transportFailure
            ),
            (
                response(
                    body: SanitizedNativeResponseFixtures.profileV4Authenticated,
                    redirectLocation: "https://example.invalid/drift"
                ),
                .redirectDrift
            ),
            (
                NativeTransportResponse(statusCode: 200, contentType: "text/html", body: Data()),
                .unsupportedContentType
            ),
            (response(statusCode: 500, body: Data("{}".utf8)), .unsupportedHTTPStatus),
            (response(statusCode: 429, body: Data("{}".utf8)), .rateLimited),
            (response(statusCode: 200, object: ["bot": true]), .botControlDetected),
            (response(body: Data()), .unsupportedPayload),
        ]

        for (nativeResponse, expectedDiagnostic) in cases {
            #expect(AuthenticationFlowAdapter.inspectAuthentication(nativeResponse).diagnosticOutcome == expectedDiagnostic)
        }

        let inactive = response(body: SanitizedNativeResponseFixtures.subscriptionV1Inactive)
        #expect(AuthenticationFlowAdapter.inspectEntitlement(inactive).diagnosticOutcome == .notEntitled)
    }

    private func response(
        statusCode: Int = 200,
        object: [String: Any] = [:],
        redirectLocation: String? = nil
    ) -> NativeTransportResponse {
        let body = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return response(statusCode: statusCode, body: body, redirectLocation: redirectLocation)
    }

    private func response(
        statusCode: Int = 200,
        body: Data,
        redirectLocation: String? = nil
    ) -> NativeTransportResponse {
        return NativeTransportResponse(
            statusCode: statusCode,
            contentType: "application/json",
            body: body,
            redirectLocation: redirectLocation
        )
    }
}
