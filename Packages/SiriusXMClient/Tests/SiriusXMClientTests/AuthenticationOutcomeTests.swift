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
            response(statusCode: 403, object: ["authenticated": true]),
            response(statusCode: 429, object: ["authenticated": true]),
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

    @Test("legacy booleans do not provide profile or entitlement semantics")
    func classifiersDoNotInterpretLegacySuccessBooleans() {
        #expect(AdapterAuthenticationResult.authenticatedPendingEntitlement.isTerminal == false)
        #expect(AuthenticationFlowAdapter.classifyAuthentication(response(statusCode: 200, object: ["authenticated": false])) == .authenticatedPendingEntitlement)
        #expect(AuthenticationFlowAdapter.classifyEntitlement(response(statusCode: 200, object: ["entitled": true])) == .unsupported)
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
