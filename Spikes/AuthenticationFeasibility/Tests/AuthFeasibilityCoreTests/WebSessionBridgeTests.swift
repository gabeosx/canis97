import Foundation
import Testing
@testable import AuthFeasibilityCore

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

    #expect(await verifier.verify(source) == .authenticated)
    #expect(await verifier.verify(source) == .alreadyConsumed)
    #expect(!WebSessionBridgeResult.authenticated.canonicalText.contains("AUTH_TOKEN"))
}

@Test("protected and ambiguous native responses fail closed")
@MainActor
func nativeSessionVerificationClassifiesStops() {
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 403, body: Data())) == .protectedControl)
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 429, body: Data())) == .rateLimited)
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 200, body: Data("{}".utf8))) == .authenticated)
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 302, body: Data())) == .httpStatus(302))
}

@Test("a supported entitlement predicate is a separate native request")
@MainActor
func nativeEntitlementVerificationCannotPromoteProfileAuthentication() async throws {
    let contract = try EntitlementContract.parse([
        "Schema: entitlement-contract-v1",
        "Status: supported",
        "Method: GET",
        "Host: api.edge-gateway.siriusxm.com",
        "Path: /subscription/v1/status",
        "Public provenance URL: https://www.siriusxm.com/player",
        "Retrieved on: 2026-08-17",
        "Success field: subscription.status",
        "Success value: active",
        "Denial field: subscription.status",
        "Denial value: inactive",
        "Malformed rule: missing-or-non-string-field",
        "",
    ].joined(separator: "\n"))
    let verifier = try NativeEntitlementVerifier(contract: contract, transport: WebSessionTransport { request in
        #expect(request.url?.path == "/subscription/v1/status")
        return .init(statusCode: 200, body: Data(#"{"subscription":{"status":"active"}}"#.utf8))
    })

    #expect(await verifier.verify(accessToken: String(repeating: "t", count: 24)) == .entitled)
    #expect(throws: ContractError.self) { try NativeEntitlementVerifier(contract: .parse(EntitlementContract.unsupportedCanonicalText)) }
}

@Test("sign-out presence check exposes no cookie value")
@MainActor
func signOutPresenceIsClosedAndNameScoped() throws {
    let current = try cookie(name: "AUTH_TOKEN", domain: ".siriusxm.com", secure: true, expires: nil)
    #expect(WebSessionSignOutChecker.classify(cookies: []) == .absent)
    #expect(WebSessionSignOutChecker.classify(cookies: [current]) == .present)
    #expect(WebSessionSignOutChecker.classify(cookies: [current, current]) == .ambiguous)
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
