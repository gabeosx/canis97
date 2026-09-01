import Foundation
import Testing
@_spi(AppIntegration) @testable import SiriusXMClient

@Suite("Browser credential envelope")
struct BrowserCredentialEnvelopeTests {
    @Test("a complete browser envelope authorizes native requests without exposing its cookies")
    func extractsOnlyTheCurrentAccessToken() throws {
        let credential = try browserCredential(
            accessToken: "synthetic-renewable-access",
            accessExpiresAt: Date(timeIntervalSince1970: 10_800)
        )

        let request = try SiriusXMRequestContract.makeRequest(for: .authentication, using: credential)
        let snapshot = try #require(credential.browserSessionSnapshot())

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-renewable-access")
        #expect(snapshot.accessTokenExpiresAt == Date(timeIntervalSince1970: 10_800))
        #expect(snapshot.diagnosticCredentialIdentifier != nil)
        #expect(snapshot.renewalDisposition == .refreshToken)
        #expect(credential.description == "AuthenticationCredential(redacted)")
        #expect(credential.debugDescription == "AuthenticationCredential(redacted)")
        #expect(!credential.description.contains("synthetic-renewable-access"))
        #expect(credential.withVolatileMaterial(AuthenticationCredential.isSupportedPersistentMaterial))

        let authenticationOnly = try AuthenticationCredential(
            browserAuthenticationCookieValue: snapshot.authenticationCookieValue,
            browserDeviceGrantCookieValue: nil
        )
        let authenticationOnlyRequest = try SiriusXMRequestContract.makeRequest(
            for: .authentication,
            using: authenticationOnly
        )
        #expect(authenticationOnlyRequest.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-renewable-access")
        #expect(authenticationOnly.browserSessionSnapshot()?.deviceGrantCookieValue == nil)
        #expect(authenticationOnly.browserSessionSnapshot()?.deviceGrantDisposition == .absent)
        #expect(authenticationOnly.browserSessionSnapshot()?.renewalDisposition == .refreshToken)
        #expect(
            authenticationOnly.browserSessionSnapshot()?.diagnosticCredentialIdentifier !=
                snapshot.diagnosticCredentialIdentifier
        )
    }

    @Test("legacy envelopes gain a random diagnostic identifier without changing authorization")
    func upgradesLegacyEnvelopeForRedactedCorrelation() throws {
        let original = try browserCredential(
            accessToken: "synthetic-legacy-envelope-access",
            accessExpiresAt: Date(timeIntervalSince1970: 10_800)
        )
        let material = original.withVolatileMaterial { $0 }
        var object = try #require(JSONSerialization.jsonObject(with: material) as? [String: Any])
        object.removeValue(forKey: "diagnosticIdentifier")
        let legacyMaterial = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let legacy = AuthenticationCredential(volatileMaterial: legacyMaterial)

        #expect(legacy.browserSessionSnapshot()?.diagnosticCredentialIdentifier == nil)
        let upgraded = try #require(legacy.addingDiagnosticIdentifierIfMissing())
        #expect(upgraded.browserSessionSnapshot()?.diagnosticCredentialIdentifier != nil)
        #expect(upgraded.addingDiagnosticIdentifierIfMissing() == nil)
        let request = try SiriusXMRequestContract.makeRequest(for: .authentication, using: upgraded)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-legacy-envelope-access")
    }

    @Test("the current browser session requires the scoped refresh cookie when AUTH_TOKEN omits refreshToken")
    func acceptsCurrentSplitRenewalContract() throws {
        let authenticationCookie = encodedCookie([
            "identityGrant": ["grant": "synthetic-identity-grant", "identityId": "synthetic-identity"],
            "session": [
                "accessToken": "synthetic-current-access",
                "accessTokenExpiresAt": providerDate(Date(timeIntervalSince1970: 10_800)),
                "refreshTokenExpiresAt": providerDate(Date(timeIntervalSince1970: 7_776_000)),
                "sessionType": "authenticated",
            ],
        ])
        let deviceGrantCookie = encodedCookie([
            "deviceId": "synthetic-device",
            "grant": "synthetic-device-grant",
            "grantExpiresAt": providerDate(Date(timeIntervalSince1970: 2_592_000)),
            "refreshGrant": "synthetic-device-refresh-grant",
            "refreshGrantExpiresAt": providerDate(Date(timeIntervalSince1970: 15_552_000)),
        ])

        let credential = try AuthenticationCredential(
            browserAuthenticationCookieValue: authenticationCookie,
            browserDeviceGrantCookieValue: deviceGrantCookie,
            browserSessionRefreshCookieValue: "synthetic-session-refresh-cookie"
        )
        let snapshot = try #require(credential.browserSessionSnapshot())
        let request = try SiriusXMRequestContract.makeRequest(for: .authentication, using: credential)

        #expect(snapshot.renewalDisposition == .sessionRefreshCookie)
        #expect(snapshot.deviceGrantDisposition == .accepted)
        #expect(snapshot.deviceGrantCookieValue != nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-current-access")

        do {
            _ = try AuthenticationCredential(
                browserAuthenticationCookieValue: authenticationCookie,
                browserDeviceGrantCookieValue: deviceGrantCookie
            )
            Issue.record("Expected a current credential without its refresh cookie to fail closed")
        } catch let error as AuthenticationCredentialMaterialError {
            #expect(error == .sessionRefreshCookieMissing)
        } catch {
            Issue.record("Expected the closed material error vocabulary")
        }
    }

    @Test("refresh eligibility follows the browser access expiry while retaining the longer windows")
    func recognizesAnExpiringBrowserAccessToken() throws {
        let credential = try browserCredential(
            accessToken: "synthetic-expiring-access",
            accessExpiresAt: Date(timeIntervalSince1970: 600),
            refreshExpiresAt: Date(timeIntervalSince1970: 9_000),
            deviceRefreshExpiresAt: Date(timeIntervalSince1970: 18_000)
        )

        #expect(!credential.requiresBrowserRefresh(at: Date(timeIntervalSince1970: 1)))
        #expect(credential.requiresBrowserRefresh(at: Date(timeIntervalSince1970: 301)))
        let snapshot = try #require(credential.browserSessionSnapshot())
        #expect(snapshot.refreshTokenExpiresAt == Date(timeIntervalSince1970: 9_000))
        #expect(snapshot.deviceRefreshGrantExpiresAt == Date(timeIntervalSince1970: 18_000))
    }

    @Test("partial, malformed, oversized, and anonymous browser envelopes fail closed")
    func rejectsInvalidBrowserMaterial() {
        let legacyRawToken = AuthenticationCredential(
            volatileMaterial: Data("synthetic-legacy-access-token".utf8)
        )
        #expect(throws: SiriusXMRequestContractError.self) {
            try SiriusXMRequestContract.makeRequest(for: .authentication, using: legacyRawToken)
        }

        let validDevice = encodedCookie([
            "deviceId": "synthetic-device",
            "grant": "synthetic-device-grant",
            "grantExpiresAt": providerDate(Date(timeIntervalSince1970: 2_592_000)),
            "refreshGrant": "synthetic-refresh-grant",
            "refreshGrantExpiresAt": providerDate(Date(timeIntervalSince1970: 15_552_000)),
        ])
        let invalidAuthenticationCookies = [
            encodedCookie(["session": ["accessToken": "synthetic-only"]]),
            encodedCookie(["session": [
                "accessToken": "synthetic-access",
                "accessTokenExpiresAt": providerDate(Date(timeIntervalSince1970: 10_800)),
                "refreshToken": "synthetic-refresh-token",
                "refreshTokenExpiresAt": providerDate(Date(timeIntervalSince1970: 7_776_000)),
                "sessionType": "anonymous",
            ]]),
            String(repeating: "x", count: 16_385),
        ]

        for authenticationCookie in invalidAuthenticationCookies {
            #expect(throws: AuthenticationCredentialMaterialError.self) {
                try AuthenticationCredential(
                    browserAuthenticationCookieValue: authenticationCookie,
                    browserDeviceGrantCookieValue: validDevice
                )
            }
        }
    }

    @Test("real browser serialization variants remain renewable")
    func acceptsBrowserSerializationVariants() throws {
        let accessExpiry = "2030-01-02T03:04:05.678Z"
        let refreshExpiryMilliseconds = 2_082_758_645_000
        let authenticationCookie = encodedCookie([
            "session": [
                "accessToken": "synthetic-access",
                "accessTokenExpiresAt": accessExpiry,
                "refreshToken": "synthetic-refresh-token",
                "refreshTokenExpiresAt": refreshExpiryMilliseconds,
            ],
        ]).addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

        let credential = try AuthenticationCredential(
            browserAuthenticationCookieValue: authenticationCookie,
            browserDeviceGrantCookieValue: encodedCookie(["unexpected": "device-shape"])
        )
        let snapshot = try #require(credential.browserSessionSnapshot())

        #expect(snapshot.accessTokenExpiresAt == ISO8601DateFormatter.fractional.date(from: accessExpiry))
        #expect(snapshot.refreshTokenExpiresAt == Date(timeIntervalSince1970: 2_082_758_645))
        #expect(snapshot.deviceGrantCookieValue == nil)
        #expect(snapshot.deviceGrantDisposition == .discardedUnrecognized)
    }

    @Test("invalid primary browser fields retain one redacted structural reason")
    func classifiesInvalidBrowserMaterialWithoutValues() {
        let expiry = providerDate(Date(timeIntervalSince1970: 10_800))
        let refreshExpiry = providerDate(Date(timeIntervalSince1970: 7_776_000))
        let scenarios: [(String, AuthenticationCredentialMaterialError)] = [
            ("not-json", .authenticationCookieUnreadable),
            (encodedCookie(["unexpected": "shape"]), .sessionObjectMissing),
            (encodedCookie(["session": "unexpected"]), .sessionObjectInvalid),
            (encodedCookie(["session": [:]]), .accessTokenMissing),
            (encodedCookie(["session": ["accessToken": 42]]), .accessTokenInvalid),
            (encodedCookie(["session": ["accessToken": "access"]]), .accessTokenExpiryMissing),
            (encodedCookie(["session": [
                "accessToken": "access",
                "accessTokenExpiresAt": "unexpected",
            ]]), .accessTokenExpiryInvalid),
            (encodedCookie(["session": [
                "accessToken": "access",
                "accessTokenExpiresAt": expiry,
            ]]), .refreshTokenExpiryMissing),
            (encodedCookie(["session": [
                "accessToken": "access",
                "accessTokenExpiresAt": expiry,
                "refreshToken": 42,
            ]]), .refreshTokenInvalid),
            (encodedCookie(["session": [
                "accessToken": "access",
                "accessTokenExpiresAt": expiry,
                "refreshToken": "refresh",
            ]]), .refreshTokenExpiryMissing),
            (encodedCookie(["session": [
                "accessToken": "access",
                "accessTokenExpiresAt": expiry,
                "refreshToken": "refresh",
                "refreshTokenExpiresAt": "unexpected",
            ]]), .refreshTokenExpiryInvalid),
            (encodedCookie(["session": [
                "accessToken": "access",
                "accessTokenExpiresAt": expiry,
                "refreshToken": "refresh",
                "refreshTokenExpiresAt": refreshExpiry,
                "sessionType": "anonymous",
            ]]), .sessionTypeRejected),
            (String(repeating: "x", count: 16_385), .authenticationCookieTooLarge),
        ]

        for (cookie, expectedError) in scenarios {
            do {
                _ = try AuthenticationCredential(
                    browserAuthenticationCookieValue: cookie,
                    browserDeviceGrantCookieValue: nil
                )
                Issue.record("Expected a rejected browser credential")
            } catch let error as AuthenticationCredentialMaterialError {
                #expect(error == expectedError)
                #expect(!error.rawValue.contains("synthetic"))
            } catch {
                Issue.record("Expected the closed material error vocabulary")
            }
        }
    }
}

func browserCredential(
    accessToken: String,
    accessExpiresAt: Date,
    refreshExpiresAt: Date = Date(timeIntervalSince1970: 7_776_000),
    deviceGrantExpiresAt: Date = Date(timeIntervalSince1970: 2_592_000),
    deviceRefreshExpiresAt: Date = Date(timeIntervalSince1970: 15_552_000)
) throws -> AuthenticationCredential {
    let authenticationCookie = encodedCookie([
        "handle": "synthetic-handle",
        "identityGrant": ["grant": "synthetic-identity-grant", "identityId": "synthetic-identity"],
        "session": [
            "accessToken": accessToken,
            "accessTokenExpiresAt": providerDate(accessExpiresAt),
            "refreshToken": "synthetic-refresh-token",
            "refreshTokenExpiresAt": providerDate(refreshExpiresAt),
            "sessionType": "authenticated",
        ],
    ])
    let deviceGrantCookie = encodedCookie([
        "deviceId": "synthetic-device",
        "grant": "synthetic-device-grant",
        "grantExpiresAt": providerDate(deviceGrantExpiresAt),
        "grantVersion": "v2",
        "refreshGrant": "synthetic-device-refresh-grant",
        "refreshGrantExpiresAt": providerDate(deviceRefreshExpiresAt),
    ])
    return try AuthenticationCredential(
        browserAuthenticationCookieValue: authenticationCookie,
        browserDeviceGrantCookieValue: deviceGrantCookie
    )
}

private func encodedCookie(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let json = String(data: data, encoding: .utf8)!
    return json.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
}

private func providerDate(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
