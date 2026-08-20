import Foundation
import SiriusXMClient

/// Pure reduction of one injected cookie snapshot into a closed outcome.  The
/// only material-bearing result is an opaque credential for the one exact match.
enum WebCredentialSelectionPolicy {
    enum Result {
        case credential(AuthenticationCredential)
        case missing([FirstPartyTokenCookiePolicy.RejectionReason])
        case ambiguous
        case malformed
    }

    static func select(from cookies: [HTTPCookie], now: Date) -> Result {
        let candidates = FirstPartyTokenCookiePolicy.matchingCookies(in: cookies, now: now)
        switch candidates.count {
        case 0:
            return .missing(FirstPartyTokenCookiePolicy.rejectionReasons(in: cookies, now: now))
        case 1:
            return credential(from: candidates[0])
        default:
            return .ambiguous
        }
    }

    private static func credential(from cookie: HTTPCookie) -> Result {
        var encodedCookieValue = cookie.value
        defer { encodedCookieValue = "" }
        guard encodedCookieValue.utf8.count <= 16_384,
              var decodedCookieValue = encodedCookieValue.removingPercentEncoding,
              decodedCookieValue.utf8.count <= 8_192 else {
            return .malformed
        }
        defer { decodedCookieValue = "" }

        var payloadData: Data? = Data(decodedCookieValue.utf8)
        defer { payloadData = nil }
        guard let payloadData,
              let payload = try? JSONDecoder().decode(TokenCookiePayload.self, from: payloadData),
              payload.session.accessToken.utf8.count <= 8_192,
              !payload.session.accessToken.isEmpty,
              !payload.session.accessToken.contains(where: { $0.isWhitespace }) else {
            return .malformed
        }

        return .credential(AuthenticationCredential(volatileMaterial: Data(payload.session.accessToken.utf8)))
    }
}

private struct TokenCookiePayload: Decodable {
    let session: TokenSession

    struct TokenSession: Decodable {
        let accessToken: String
    }
}
