import Foundation

/// The one exact predicate shared by first-party token extraction and cleanup.
enum FirstPartyTokenCookiePolicy {
    enum Selection: Equatable {
        case missing
        case one
        case ambiguous
    }

    enum RejectionReason: CaseIterable, Equatable, Hashable {
        case nameAbsent
        case issuerRejected
        case pathRejected
        case insecure
        case expired
    }

    static func select(from cookies: [HTTPCookie], now: Date) -> Selection {
        switch matchingCookies(in: cookies, now: now).count {
        case 0: .missing
        case 1: .one
        default: .ambiguous
        }
    }

    static func matchingCookies(in cookies: [HTTPCookie], now: Date) -> [HTTPCookie] {
        cookies.filter { matches($0, now: now) }
    }

    static func isFirstParty(_ cookie: HTTPCookie) -> Bool {
        isFirstPartyDomain(normalizedDomain(of: cookie))
    }

    /// Describes only closed policy failures and never returns cookie values or metadata.
    static func rejectionReasons(in cookies: [HTTPCookie], now: Date) -> [RejectionReason] {
        let namedCookies = cookies.filter { $0.name == "AUTH_TOKEN" }
        guard !namedCookies.isEmpty else { return [.nameAbsent] }

        var reasons = Set<RejectionReason>()
        for cookie in namedCookies {
            if !isFirstPartyDomain(normalizedDomain(of: cookie)) {
                reasons.insert(.issuerRejected)
            }
            if cookie.path != "/" {
                reasons.insert(.pathRejected)
            }
            if !cookie.isSecure {
                reasons.insert(.insecure)
            }
            if cookie.expiresDate.map({ $0 <= now }) ?? false {
                reasons.insert(.expired)
            }
        }
        return RejectionReason.allCases.filter(reasons.contains)
    }

    static func matches(_ cookie: HTTPCookie, now: Date) -> Bool {
        guard cookie.name == "AUTH_TOKEN",
              cookie.path == "/",
              cookie.isSecure,
              cookie.expiresDate.map({ $0 > now }) ?? true else {
            return false
        }

        return isFirstPartyDomain(normalizedDomain(of: cookie))
    }

    private static func normalizedDomain(of cookie: HTTPCookie) -> String {
        String(cookie.domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .drop(while: { $0 == "." }))
    }

    private static func isFirstPartyDomain(_ domain: String) -> Bool {
        domain == "siriusxm.com" || domain.hasSuffix(".siriusxm.com")
    }
}
