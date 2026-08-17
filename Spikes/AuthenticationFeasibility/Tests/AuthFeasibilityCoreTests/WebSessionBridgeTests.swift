import Foundation
import Testing

#if canImport(AuthFeasibilityHarness)
@testable import AuthFeasibilityHarness

@Test("session extraction keeps only current secure SiriusXM cookies")
func sessionCookieFilterIsFirstPartyOnly() throws {
    let now = Date()
    let cookies = try [
        cookie(name: "SESSION", domain: ".siriusxm.com", secure: true, expires: now.addingTimeInterval(60)),
        cookie(name: "HOST", domain: "player.siriusxm.com", secure: true, expires: nil),
        cookie(name: "THIRD", domain: ".example.com", secure: true, expires: nil),
        cookie(name: "INSECURE", domain: ".siriusxm.com", secure: false, expires: nil),
        cookie(name: "EXPIRED", domain: ".siriusxm.com", secure: true, expires: now.addingTimeInterval(-60)),
    ]

    let filtered = FirstPartyCookieFilter.filter(cookies, now: now)
    #expect(filtered.map(\.name) == ["SESSION", "HOST"])
}

@Test("native verification consumes the session once and emits only a closed result")
@MainActor
func nativeSessionVerificationIsSingleConsumption() async throws {
    let source = VolatileWebSession(cookies: [
        try cookie(name: "SESSION", domain: ".siriusxm.com", secure: true, expires: nil),
    ])
    let verifier = NativeWebSessionVerifier(transport: WebSessionTransport { cookies, request in
        #expect(cookies.count == 1)
        #expect(request.url?.host == "player.siriusxm.com")
        return WebSessionHTTPResponse(
            statusCode: 200,
            body: Data(#"{"ModuleListResponse":{"status":1}}"#.utf8)
        )
    })

    #expect(await verifier.verify(source) == .verified)
    #expect(await verifier.verify(source) == .noFirstPartySession)
    #expect(!WebSessionBridgeResult.verified.canonicalText.contains("SESSION"))
}

@Test("protected and ambiguous native responses fail closed")
@MainActor
func nativeSessionVerificationClassifiesStops() {
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 403, body: Data())) == .protectedControl)
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 429, body: Data())) == .rateLimited)
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 200, body: Data("{}".utf8))) == .rejected)
    #expect(NativeWebSessionVerifier.classify(.init(statusCode: 302, body: Data())) == .ambiguous)
}

private func cookie(
    name: String,
    domain: String,
    secure: Bool,
    expires: Date?
) throws -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name,
        .value: "fixture-value",
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
