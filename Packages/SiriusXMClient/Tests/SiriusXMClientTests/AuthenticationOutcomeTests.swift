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

    @Test("subscription item states remain exact and fail closed")
    func entitlementAcceptsOnlyObservedSubscriptionStates() {
        let missing = response(object: ["items": [["fixture_marker": "missing-state"]]])
        let nonString = response(object: ["items": [["state": 1]]])
        let unknown = response(object: ["items": [["state": "fixture-unknown"]]])

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
                NativeTransportResponse(
                    statusCode: 0,
                    contentType: nil,
                    body: Data(),
                    transportFailure: .timedOut
                ),
                .transportTimedOut
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
                .contentTypeHTML
            ),
            (
                NativeTransportResponse(statusCode: 200, contentType: nil, body: Data()),
                .contentTypeMissing
            ),
            (
                NativeTransportResponse(statusCode: 200, contentType: "text/plain", body: Data()),
                .unsupportedContentType
            ),
            (response(statusCode: 404, body: Data("{}".utf8)), .httpNotFound),
            (response(statusCode: 418, body: Data("{}".utf8)), .httpClientError),
            (response(statusCode: 500, body: Data("{}".utf8)), .httpServerError),
            (response(statusCode: 302, body: Data("{}".utf8)), .unsupportedHTTPStatus),
            (response(statusCode: 429, body: Data("{}".utf8)), .rateLimited),
            (response(statusCode: 200, object: ["bot": true]), .botControlDetected),
            (response(body: Data()), .payloadEmpty),
            (response(body: Data("{".utf8)), .payloadMalformedJSON),
            (response(body: Data("[]".utf8)), .payloadUnexpectedRoot),
        ]

        for (nativeResponse, expectedDiagnostic) in cases {
            #expect(AuthenticationFlowAdapter.inspectAuthentication(nativeResponse).diagnosticOutcome == expectedDiagnostic)
        }

        let inactive = response(body: SanitizedNativeResponseFixtures.subscriptionV1Inactive)
        #expect(AuthenticationFlowAdapter.inspectEntitlement(inactive).diagnosticOutcome == .notEntitled)
    }

    @Test("transport errors become bounded labels without retaining error detail")
    func transportErrorsMapToSafeClasses() {
        let cases: [(URLError.Code, SafeDiagnosticOutcome)] = [
            (.timedOut, .transportTimedOut),
            (.dnsLookupFailed, .transportNameResolutionFailed),
            (.cannotConnectToHost, .transportConnectionFailed),
            (.serverCertificateUntrusted, .transportTLSFailed),
            (.cancelled, .transportCancelled),
            (.badURL, .transportFailure),
        ]

        for (code, expectedOutcome) in cases {
            let failure = SafeTransportFailure(error: URLError(code))
            #expect(failure.diagnosticOutcome == expectedOutcome)
        }
    }

    @Test("entitlement diagnostics identify the exact live-shape boundary")
    func entitlementDiagnosticsIdentifyPayloadShape() {
        let cases: [(NativeTransportResponse, SafeDiagnosticOutcome)] = [
            (response(body: Data()), .payloadEmpty),
            (response(body: Data("{".utf8)), .payloadMalformedJSON),
            (response(body: Data("[]".utf8)), .payloadUnexpectedRoot),
            (response(object: [:]), .subscriptionsItemsMissing),
            (response(object: ["items": "unexpected"]), .subscriptionsItemsUnexpectedShape),
            (response(object: ["items": ["unexpected"]]), .subscriptionItemUnexpectedShape),
            (response(object: ["items": [[:]]]), .subscriptionStateMissing),
            (response(object: ["items": [["state": 1]]]), .subscriptionStateUnexpectedShape),
            (response(object: ["items": [["state": "fixture-unknown"]]]), .subscriptionStateUnsupported),
        ]

        for (nativeResponse, expectedDiagnostic) in cases {
            let classification = AuthenticationFlowAdapter.inspectEntitlement(nativeResponse)
            #expect(classification.result == .unsupported)
            #expect(classification.diagnosticOutcome == expectedDiagnostic)
        }
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
