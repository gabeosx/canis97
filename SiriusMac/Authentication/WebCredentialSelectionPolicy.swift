import Foundation
@_spi(AppIntegration) import SiriusXMClient

/// Pure reduction of one injected cookie snapshot into a closed outcome.  The
/// only material-bearing result is an opaque credential for the one exact match.
enum WebCredentialSelectionPolicy {
    enum Result {
        case credential(AuthenticationCredential)
        case missing([FirstPartyTokenCookiePolicy.RejectionReason])
        case ambiguous
        case malformed(AuthenticationCredentialMaterialError)
    }

    static func select(from cookies: [HTTPCookie], now: Date) -> Result {
        let candidates = FirstPartyTokenCookiePolicy.matchingCookies(in: cookies, now: now)
        switch candidates.count {
        case 0:
            return .missing(FirstPartyTokenCookiePolicy.rejectionReasons(in: cookies, now: now))
        case 1:
            let deviceGrantCandidates = FirstPartyDeviceGrantCookiePolicy.matchingCookies(in: cookies, now: now)
            let sessionRefreshCandidates = FirstPartySessionRefreshCookiePolicy.matchingCookies(
                in: cookies,
                now: now
            )
            guard sessionRefreshCandidates.count <= 1 else { return .ambiguous }
            switch deviceGrantCandidates.count {
            case 0:
                return browserCredential(
                    authenticationCookie: candidates[0],
                    deviceGrantCookie: nil,
                    sessionRefreshCookie: sessionRefreshCandidates.first,
                    allCookies: cookies
                )
            case 1:
                return browserCredential(
                    authenticationCookie: candidates[0],
                    deviceGrantCookie: deviceGrantCandidates[0],
                    sessionRefreshCookie: sessionRefreshCandidates.first,
                    allCookies: cookies
                )
            default:
                return .ambiguous
            }
        default:
            return .ambiguous
        }
    }

    private static func browserCredential(
        authenticationCookie: HTTPCookie,
        deviceGrantCookie: HTTPCookie?,
        sessionRefreshCookie: HTTPCookie?,
        allCookies: [HTTPCookie]
    ) -> Result {
        do {
            return .credential(try AuthenticationCredential(
                browserAuthenticationCookieValue: authenticationCookie.value,
                browserDeviceGrantCookieValue: deviceGrantCookie?.value,
                browserSessionRefreshCookieValue: sessionRefreshCookie?.value
            ))
        } catch let error as AuthenticationCredentialMaterialError {
            if error == .sessionRefreshCookieMissing,
               FirstPartySessionRefreshCookiePolicy.hasNamedCookie(in: allCookies) {
                return .malformed(.sessionRefreshCookieInvalid)
            }
            return .malformed(error)
        } catch {
            return .malformed(.envelopeEncodingFailed)
        }
    }

}
