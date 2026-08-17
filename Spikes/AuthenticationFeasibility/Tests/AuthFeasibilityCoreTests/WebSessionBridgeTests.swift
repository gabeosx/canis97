import Foundation
import Testing

#if canImport(AuthFeasibilityHarness)
@testable import AuthFeasibilityHarness

@Test("session extraction reads only one current first-party AUTH_TOKEN cookie")
@MainActor
func sessionCookieExtractionUsesDocumentedPlayerCookie() throws {
    let now = Date()
    let token = String(repeating: "a", count: 24)
    let authValue = #"{"session":{"accessToken":"\#(token)"}}"#.addingPercentEncoding(
        withAllowedCharacters: .alphanumerics
    )!
    let cookies = try [
        cookie(name: "AUTH_TOKEN", value: authValue, domain: ".siriusxm.com", secure: true, expires: now.addingTimeInterval(60)),
        cookie(name: "SESSION", domain: "player.siriusxm.com", secure: true, expires: nil),
        cookie(name: "THIRD", domain: ".example.com", secure: true, expires: nil),
        cookie(name: "AUTH_TOKEN", value: authValue, domain: ".example.com", secure: true, expires: nil),
        cookie(name: "AUTH_TOKEN", value: authValue, domain: ".siriusxm.com", secure: true, expires: now.addingTimeInterval(-60)),
    ]

    guard case let .session(session) = SiriusXMAuthCookieExtractor.extract(from: cookies, now: now) else {
        Issue.record("Expected an extractable player session")
        return
    }
    #expect(session.consume() == token)
    #expect(session.consume() == nil)
}

@Test("session extraction distinguishes missing and malformed player cookies")
@MainActor
func sessionCookieExtractionHasMeasurableFailures() throws {
    guard case .authCookieMissing = SiriusXMAuthCookieExtractor.extract(from: []) else {
        Issue.record("Expected missing AUTH_TOKEN result")
        return
    }
    let malformed = try cookie(name: "AUTH_TOKEN", value: "not-json", domain: ".siriusxm.com", secure: true, expires: nil)
    guard case .authCookieMalformed = SiriusXMAuthCookieExtractor.extract(from: [malformed]) else {
        Issue.record("Expected malformed AUTH_TOKEN result")
        return
    }
}

@Test("native verification consumes the session once and emits only a closed result")
@MainActor
func nativeSessionVerificationIsSingleConsumption() async throws {
    let source = VolatileWebSession(accessToken: String(repeating: "t", count: 24))
    let verifier = NativeWebSessionVerifier(transport: WebSessionTransport { request in
        #expect(request.url?.host == "api.edge-gateway.siriusxm.com")
        #expect(request.url?.path == "/profile/v4/profiles/me")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
        return WebSessionHTTPResponse(
            statusCode: 200,
            body: Data()
        )
    })

    #expect(await verifier.verify(source) == .verified)
    #expect(await verifier.verify(source) == .alreadyConsumed)
    #expect(!WebSessionBridgeResult.verified.canonicalText.contains("AUTH_TOKEN"))
}

@Test("protected and ambiguous native responses fail closed")
@MainActor
func nativeSessionVerificationClassifiesStops() {
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 403, body: Data())) == .protectedControl)
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 429, body: Data())) == .rateLimited)
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 200, body: Data("{}".utf8))) == .verified)
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 302, body: Data())) == .httpStatus(302))
}

private func cookie(
    name: String,
    value: String = "fixture-value",
    domain: String,
    secure: Bool,
    expires: Date?
) throws -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name,
        .value: value,
        .domain: domain,
        .path: "/",
    ]
    if secure { properties[.secure] = "TRUE" }
    if let expires { properties[.expires] = expires }
    guard let cookie = HTTPCookie(properties: properties) else {
        throw CocoaError(.coderInvalidValue)
    }
    return cookie
}
#endif
