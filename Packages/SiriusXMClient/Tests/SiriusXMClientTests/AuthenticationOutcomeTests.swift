import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Native response classification")
struct AuthenticationOutcomeTests {
    @Test("a verified profile response remains pending entitlement")
    func authenticationSuccessIsNeverFinalSessionSuccess() {
        let response = response(statusCode: 200, object: ["authenticated": true])

        #expect(AuthenticationFlowAdapter.classifyAuthentication(response) == .authenticatedPendingEntitlement)
    }

    @Test("a recognized entitlement response is classified independently")
    func entitlementResponseIsClassifiedSeparately() {
        let entitled = response(statusCode: 200, object: ["entitled": true])
        let notEntitled = response(statusCode: 200, object: ["entitled": false])

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
            NativeTransportResponse(statusCode: 200, contentType: "application/json", body: Data("{".utf8)),
            response(statusCode: 200, object: ["authenticated": true, "entitled": true]),
            response(
                statusCode: 200,
                object: ["authenticated": true],
                redirectLocation: "https://example.invalid/drift"
            ),
        ]

        for response in controlResponses {
            #expect(AuthenticationFlowAdapter.classifyAuthentication(response).isTerminal)
            #expect(AuthenticationFlowAdapter.classifyAuthentication(response) != .authenticatedPendingEntitlement)
        }
    }

    @Test("internal classifiers do not accept caller-authored success claims")
    func classifiersAcceptOnlyTransportResponses() {
        #expect(AdapterAuthenticationResult.authenticatedPendingEntitlement.isTerminal == false)
        #expect(AuthenticationFlowAdapter.classifyAuthentication(response(statusCode: 200, object: ["authenticated": false])) == .rejected)
    }

    private func response(
        statusCode: Int,
        object: [String: Any],
        redirectLocation: String? = nil
    ) -> NativeTransportResponse {
        let body = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return NativeTransportResponse(
            statusCode: statusCode,
            contentType: "application/json",
            body: body,
            redirectLocation: redirectLocation
        )
    }
}
