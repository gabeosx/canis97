import Foundation

/// The closed, secret-free vocabulary that crosses authentication boundaries into
/// native presentation and diagnostics.  It intentionally has no transport,
/// cookie, Keychain, or provider payload types in its API.
enum ClosedAuthenticationStage: String, CaseIterable, Equatable {
    case localCredential = "local-credential"
    case webCredential = "web-credential"
    case nativeProfile = "native-profile"
    case entitlement = "entitlement"
    case persistence = "persistence"
    case restore = "restore"
}

enum ClosedAuthenticationTerminal: String, CaseIterable, Equatable {
    case waitingForWebView
    case verifyingAuthentication
    case verifyingEntitlement
    case authenticatedButNotEntitled
    case durableReady
    case restoreCompleted
    case profileUnauthorized
    case profileForbidden
    case entitlementUnauthorized
    case entitlementForbidden
    case persistenceFailed
    case rejected
    case challengeRequired
    case unsupported
    case signedOut
    case cleanupFailed
}

struct AuthenticationPresentationCopy: Equatable {
    let title: String
    let message: String
    let iconName: String
    let statusLabel: String
    let isReady: Bool
    let canSignOut: Bool
}

enum ClosedAuthenticationOracle {
    static func presentation(for terminal: ClosedAuthenticationTerminal) -> AuthenticationPresentationCopy {
        switch terminal {
        case .waitingForWebView:
            AuthenticationPresentationCopy(
                title: "Sign in to SiriusXM",
                message: "Sign in in the native window to continue.",
                iconName: "lock",
                statusLabel: "web-sign-in-required",
                isReady: false,
                canSignOut: false
            )
        case .verifyingAuthentication:
            AuthenticationPresentationCopy(
                title: "Verifying sign-in",
                message: "Checking your signed-in session.",
                iconName: "checkmark.shield",
                statusLabel: "profile-verification-in-progress",
                isReady: false,
                canSignOut: false
            )
        case .verifyingEntitlement:
            AuthenticationPresentationCopy(
                title: "Checking subscription",
                message: "Confirming that this account can listen.",
                iconName: "checkmark.seal",
                statusLabel: "entitlement-verification-in-progress",
                isReady: false,
                canSignOut: false
            )
        case .authenticatedButNotEntitled:
            AuthenticationPresentationCopy(
                title: "Subscription unavailable",
                message: "This signed-in account is not currently entitled to listen.",
                iconName: "person.crop.circle.badge.exclamationmark",
                statusLabel: "subscription-unavailable",
                isReady: false,
                canSignOut: false
            )
        case .durableReady:
            AuthenticationPresentationCopy(
                title: "Ready to listen",
                message: "Your account is signed in and ready.",
                iconName: "checkmark.circle",
                statusLabel: "durable-ready",
                isReady: true,
                canSignOut: true
            )
        case .restoreCompleted:
            AuthenticationPresentationCopy(
                title: "Ready to listen",
                message: "Your stored sign-in is ready.",
                iconName: "checkmark.circle",
                statusLabel: "restore-completed",
                isReady: true,
                canSignOut: true
            )
        case .profileUnauthorized, .profileForbidden:
            AuthenticationPresentationCopy(
                title: "Sign-in verification was rejected",
                message: "SiriusXM did not accept this sign-in at the profile check.",
                iconName: "xmark.circle",
                statusLabel: "profile-authorization-rejected",
                isReady: false,
                canSignOut: false
            )
        case .entitlementUnauthorized, .entitlementForbidden:
            AuthenticationPresentationCopy(
                title: "Subscription verification was rejected",
                message: "SiriusXM did not accept this sign-in at the subscription check.",
                iconName: "xmark.circle",
                statusLabel: "entitlement-authorization-rejected",
                isReady: false,
                canSignOut: false
            )
        case .persistenceFailed:
            AuthenticationPresentationCopy(
                title: "Sign-in could not be saved",
                message: "Sirius Mac could not safely save this sign-in.",
                iconName: "exclamationmark.triangle",
                statusLabel: "credential-not-durable",
                isReady: false,
                canSignOut: false
            )
        case .rejected:
            AuthenticationPresentationCopy(
                title: "Sign-in was rejected",
                message: "SiriusXM did not accept this sign-in attempt.",
                iconName: "xmark.circle",
                statusLabel: "sign-in-rejected",
                isReady: false,
                canSignOut: false
            )
        case .challengeRequired:
            AuthenticationPresentationCopy(
                title: "Additional verification is required",
                message: "This sign-in needs a challenge that Sirius Mac does not handle.",
                iconName: "exclamationmark.shield",
                statusLabel: "challenge-required",
                isReady: false,
                canSignOut: false
            )
        case .unsupported:
            AuthenticationPresentationCopy(
                title: "Sign-in flow unsupported",
                message: "This sign-in flow is unsupported. No workaround was attempted.",
                iconName: "exclamationmark.triangle",
                statusLabel: "sign-in-unsupported",
                isReady: false,
                canSignOut: false
            )
        case .signedOut:
            AuthenticationPresentationCopy(
                title: "Signed out",
                message: "You are signed out of Sirius Mac.",
                iconName: "rectangle.portrait.and.arrow.right",
                statusLabel: "signed-out",
                isReady: false,
                canSignOut: false
            )
        case .cleanupFailed:
            AuthenticationPresentationCopy(
                title: "Signed out with cleanup warning",
                message: "You are signed out. Local cleanup was incomplete.",
                iconName: "exclamationmark.triangle",
                statusLabel: "cleanup-incomplete",
                isReady: false,
                canSignOut: false
            )
        }
    }
}
