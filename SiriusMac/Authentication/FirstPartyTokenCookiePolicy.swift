import Foundation

/// The one exact predicate shared by first-party token extraction and cleanup.
enum FirstPartyTokenCookiePolicy {
    /// Exact normalized domains grounded in the sign-in host and historical apex cookie evidence.
    private static let acceptedDomains: Set<String> = ["siriusxm.com", "www.siriusxm.com"]

    enum Selection: Equatable {
        case missing
        case one
        case ambiguous
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

    static func matches(_ cookie: HTTPCookie, now: Date) -> Bool {
        guard cookie.name == "AUTH_TOKEN",
              cookie.path == "/",
              cookie.isSecure,
              cookie.expiresDate.map({ $0 > now }) ?? true else {
            return false
        }

        let domain = cookie.domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .drop(while: { $0 == "." })

        return acceptedDomains.contains(String(domain))
    }
}
