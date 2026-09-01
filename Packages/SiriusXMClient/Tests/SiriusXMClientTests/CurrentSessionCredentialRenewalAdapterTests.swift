import Foundation
import Testing
@_spi(AppIntegration) @testable import SiriusXMClient

@Suite("Current session credential renewal adapter")
struct CurrentSessionCredentialRenewalAdapterTests {
    @Test("the current refresh request is fixed, cookie-authenticated, and authorization-free")
    func materializesFixedRequest() throws {
        let request = try #require(CurrentSessionCredentialRenewalRequestFactory.makeRequest(
            renewalMaterial: .sessionRefreshCookie("synthetic-session-refresh-cookie"),
            clock: "[0,7]"
        ))
        let requestBody = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])

        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "api.edge-gateway.siriusxm.com")
        #expect(request.url?.path == "/session/v1/sessions/refresh")
        #expect(request.httpMethod == "POST")
        #expect(body.count == 1)
        #expect(body["location"] is NSNull)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sxm-refresh-token=synthetic-session-refresh-cookie")
        #expect(request.value(forHTTPHeaderField: "x-sxm-clock") == "[0,7]")
    }

    @Test("the legacy refresh-token variant uses bearer authorization without a cookie")
    func materializesLegacyBearerRequest() throws {
        let request = try #require(CurrentSessionCredentialRenewalRequestFactory.makeRequest(
            renewalMaterial: .bearerRefreshToken("synthetic-refresh-token"),
            clock: "[0,8]"
        ))

        #expect(request.url?.path == "/session/v1/sessions/refresh")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-refresh-token")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("the rotated session cookie must retain the exact refresh endpoint scope")
    func parsesExactRotatedCookie() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://api.edge-gateway.siriusxm.com/session/v1/sessions/refresh")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Set-Cookie": rotatedCookieHeader(
                    value: "rotated-session-refresh-cookie",
                    expires: now.addingTimeInterval(7_776_000)
                ),
            ]
        ))

        #expect(
            SessionRefreshCookieHeaderParser.value(from: response, now: now) ==
                "rotated-session-refresh-cookie"
        )
    }

    @Test("a rotated cookie with weakened security or widened scope is rejected")
    func rejectsUnsafeRotatedCookie() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let responseURL = try #require(
            URL(string: "https://api.edge-gateway.siriusxm.com/session/v1/sessions/refresh")
        )
        let unsafeHeaders = [
            rotatedCookieHeader(
                value: "synthetic-cookie",
                expires: now.addingTimeInterval(7_776_000),
                path: "/"
            ),
            rotatedCookieHeader(
                value: "synthetic-cookie",
                expires: now.addingTimeInterval(7_776_000),
                includesHTTPOnly: false
            ),
            rotatedCookieHeader(
                value: "synthetic-cookie",
                expires: now.addingTimeInterval(7_776_000),
                includesSecure: false
            ),
        ]

        for header in unsafeHeaders {
            let response = try #require(HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Set-Cookie": header]
            ))
            #expect(SessionRefreshCookieHeaderParser.value(from: response, now: now) == nil)
        }
    }

    @Test("the current refresh cookie replaces both session material and the rotated cookie")
    func replacesCurrentSession() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let credential = try currentRefreshCookieCredential(
            accessToken: "expired-access-token-must-not-leak",
            accessExpiresAt: now.addingTimeInterval(-60),
            renewalExpiresAt: now.addingTimeInterval(90 * 24 * 60 * 60)
        )
        let response = CurrentSessionCredentialRenewalTransportResponse(
            response: NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json; charset=utf-8",
                body: currentSessionResponse(
                    accessToken: "replacement-access-token-must-not-leak",
                    accessExpiresAt: now.addingTimeInterval(10_800),
                    renewalExpiresAt: now.addingTimeInterval(90 * 24 * 60 * 60)
                )
            ),
            replacementRefreshCookieValue: "rotated-session-refresh-cookie-must-not-leak"
        )
        let driver = SiriusXMCurrentCredentialRenewalDriver(
            transport: StubCurrentSessionRenewalTransport(response: response),
            now: { now }
        )

        let result = await driver.refresh(credential)
        guard case let .refreshed(replacement) = result else {
            Issue.record("Expected a replacement credential")
            return
        }

        #expect(replacement.accessToken() == "replacement-access-token-must-not-leak")
        #expect(replacement.browserSessionSnapshot()?.renewalDisposition == .sessionRefreshCookie)
        #expect(replacement.browserSessionSnapshot()?.deviceGrantCookieValue != nil)
        #expect(
            replacement.browserSessionSnapshot()?.diagnosticCredentialIdentifier !=
                credential.browserSessionSnapshot()?.diagnosticCredentialIdentifier
        )
        #expect(!replacement.description.contains("replacement-access-token-must-not-leak"))
        #expect(!replacement.description.contains("rotated-session-refresh-cookie-must-not-leak"))
    }

    @Test("closed native failures remain distinct and secret-free")
    func classifiesNativeFailures() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let credential = try currentRefreshCookieCredential(
            accessToken: "failure-access-token-must-not-leak",
            accessExpiresAt: now.addingTimeInterval(-60),
            renewalExpiresAt: now.addingTimeInterval(90 * 24 * 60 * 60)
        )
        let scenarios: [(NativeTransportResponse, BrowserCredentialNativeRenewalFailure)] = [
            (NativeTransportResponse(statusCode: 401, contentType: "application/json", body: Data()), .authorizationRejected),
            (NativeTransportResponse(statusCode: 429, contentType: "application/json", body: Data()), .rateLimited),
            (NativeTransportResponse(statusCode: 503, contentType: "application/json", body: Data()), .serverUnavailable),
            (NativeTransportResponse(statusCode: 200, contentType: "text/html", body: Data()), .unsupportedResponse),
            (NativeTransportResponse(statusCode: 0, contentType: nil, body: Data(), transportFailure: .connection), .transportFailed),
        ]

        for (nativeResponse, expected) in scenarios {
            let response = CurrentSessionCredentialRenewalTransportResponse(
                response: nativeResponse,
                replacementRefreshCookieValue: nil
            )
            let driver = SiriusXMCurrentCredentialRenewalDriver(
                transport: StubCurrentSessionRenewalTransport(response: response),
                now: { now }
            )
            let result = await driver.refresh(credential)
            guard case let .failed(failure) = result else {
                Issue.record("Expected a closed failure")
                continue
            }
            #expect(failure == expected)
            #expect(!failure.rawValue.contains("failure-access-token-must-not-leak"))
        }
    }

    @Test("a successful body without a rotated cookie fails closed")
    func rejectsMissingCookieRotation() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let credential = try currentRefreshCookieCredential(
            accessToken: "expired-access",
            accessExpiresAt: now.addingTimeInterval(-60),
            renewalExpiresAt: now.addingTimeInterval(90 * 24 * 60 * 60)
        )
        let response = CurrentSessionCredentialRenewalTransportResponse(
            response: NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: currentSessionResponse(
                    accessToken: "replacement-access",
                    accessExpiresAt: now.addingTimeInterval(10_800),
                    renewalExpiresAt: now.addingTimeInterval(90 * 24 * 60 * 60)
                )
            ),
            replacementRefreshCookieValue: nil
        )
        let driver = SiriusXMCurrentCredentialRenewalDriver(
            transport: StubCurrentSessionRenewalTransport(response: response),
            now: { now }
        )

        let result = await driver.refresh(credential)
        guard case let .failed(failure) = result else {
            Issue.record("Expected a closed failure")
            return
        }
        #expect(failure == .replacementUnusable)
    }

    @Test("expired session refresh authority fails before transport")
    func rejectsExpiredAuthorityBeforeTransport() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let credential = try currentRefreshCookieCredential(
            accessToken: "expired-authority-access",
            accessExpiresAt: now.addingTimeInterval(-60),
            renewalExpiresAt: now.addingTimeInterval(-1)
        )
        let transport = CountingCurrentSessionRenewalTransport()
        let driver = SiriusXMCurrentCredentialRenewalDriver(transport: transport, now: { now })

        let result = await driver.refresh(credential)

        guard case let .failed(failure) = result else {
            Issue.record("Expected expired authority")
            return
        }
        #expect(failure == .renewalAuthorityExpired)
        #expect(await transport.callCount == 0)
    }
}

private struct StubCurrentSessionRenewalTransport: CurrentSessionCredentialRenewalTransporting {
    let response: CurrentSessionCredentialRenewalTransportResponse

    func refreshSession(using _: SessionRenewalMaterial) async -> CurrentSessionCredentialRenewalTransportResponse {
        response
    }
}

private actor CountingCurrentSessionRenewalTransport: CurrentSessionCredentialRenewalTransporting {
    private(set) var callCount = 0

    func refreshSession(using _: SessionRenewalMaterial) async -> CurrentSessionCredentialRenewalTransportResponse {
        callCount += 1
        return CurrentSessionCredentialRenewalTransportResponse(
            response: NativeTransportResponse(statusCode: 500, contentType: "application/json", body: Data()),
            replacementRefreshCookieValue: nil
        )
    }
}

private func currentRefreshCookieCredential(
    accessToken: String,
    accessExpiresAt: Date,
    renewalExpiresAt: Date
) throws -> AuthenticationCredential {
    let authenticationCookie = renewalEncodedCookie([
        "handle": "synthetic-handle",
        "identityGrant": ["grant": "synthetic-identity-grant", "identityId": "synthetic-identity"],
        "session": [
            "accessToken": accessToken,
            "accessTokenExpiresAt": renewalProviderDate(accessExpiresAt),
            "refreshTokenExpiresAt": renewalProviderDate(renewalExpiresAt),
            "sessionType": "authenticated",
        ],
    ])
    let deviceGrantCookie = renewalEncodedCookie([
        "deviceId": "synthetic-device",
        "grant": "synthetic-device-grant",
        "grantExpiresAt": renewalProviderDate(Date(timeIntervalSince1970: 2_592_000)),
        "grantVersion": "v2",
        "refreshGrant": "synthetic-device-refresh-grant",
        "refreshGrantExpiresAt": renewalProviderDate(Date(timeIntervalSince1970: 15_552_000)),
    ])
    return try AuthenticationCredential(
        browserAuthenticationCookieValue: authenticationCookie,
        browserDeviceGrantCookieValue: deviceGrantCookie,
        browserSessionRefreshCookieValue: "synthetic-session-refresh-cookie"
    )
}

private func currentSessionResponse(
    accessToken: String,
    accessExpiresAt: Date,
    renewalExpiresAt: Date
) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "accessToken": accessToken,
        "accessTokenExpiresAt": renewalProviderDate(accessExpiresAt),
        "accessTokenId": "synthetic-access-id",
        "refreshTokenExpiresAt": renewalProviderDate(renewalExpiresAt),
        "sessionId": "synthetic-session-id",
        "sessionType": "authenticated",
    ], options: [.sortedKeys])
}

private func renewalEncodedCookie(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let json = String(data: data, encoding: .utf8)!
    return json.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
}

private func renewalProviderDate(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func rotatedCookieHeader(
    value: String,
    expires: Date,
    path: String = "/session/v1/sessions/refresh",
    includesHTTPOnly: Bool = true,
    includesSecure: Bool = true
) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    var attributes = [
        "sxm-refresh-token=\(value)",
        "Domain=api.edge-gateway.siriusxm.com",
        "Path=\(path)",
        "Expires=\(formatter.string(from: expires))",
    ]
    if includesHTTPOnly { attributes.append("HttpOnly") }
    if includesSecure { attributes.append("Secure") }
    attributes.append("SameSite=None")
    return attributes.joined(separator: "; ")
}
