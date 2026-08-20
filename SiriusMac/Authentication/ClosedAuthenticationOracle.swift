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
    case localCredentialMissing
    case localCredentialInvalid
    case localCredentialUnavailable
    case webCredentialMissing
    case webCredentialMalformed
    case webCredentialAmbiguous
    case webCredentialTransferred
    case webSessionResetFailed
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
    case finishingCleanup
}

enum ClosedWebCredentialOutcome: Equatable {
    case missing
    case malformed
    case ambiguous
    case transferred
    case resetFailed
}

struct ClosedWebOutcome: Equatable {
    let statusLabel: String
    let isSingleConsumption: Bool
    let allowsPlayerLoad: Bool
}

enum LocalCredentialAvailability: Equatable {
    case missing
    case invalid
    case unavailable
    case credential
}

struct ClosedRestoreOutcome: Equatable {
    let terminal: ClosedAuthenticationTerminal
    let webViewLoads: Int
    let nativeTransactions: Int
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
    static func webOutcome(for outcome: ClosedWebCredentialOutcome) -> ClosedWebOutcome {
        switch outcome {
        case .missing:
            ClosedWebOutcome(statusLabel: "web-credential-missing", isSingleConsumption: false, allowsPlayerLoad: false)
        case .malformed:
            ClosedWebOutcome(statusLabel: "web-credential-malformed", isSingleConsumption: false, allowsPlayerLoad: false)
        case .ambiguous:
            ClosedWebOutcome(statusLabel: "web-credential-ambiguous", isSingleConsumption: false, allowsPlayerLoad: false)
        case .transferred:
            ClosedWebOutcome(statusLabel: "web-credential-transferred", isSingleConsumption: true, allowsPlayerLoad: false)
        case .resetFailed:
            ClosedWebOutcome(statusLabel: "web-session-reset-failed", isSingleConsumption: false, allowsPlayerLoad: false)
        }
    }

    static func restoreOutcome(for availability: LocalCredentialAvailability) -> ClosedRestoreOutcome {
        switch availability {
        case .missing:
            ClosedRestoreOutcome(terminal: .localCredentialMissing, webViewLoads: 0, nativeTransactions: 0)
        case .invalid:
            ClosedRestoreOutcome(terminal: .localCredentialInvalid, webViewLoads: 0, nativeTransactions: 0)
        case .unavailable:
            ClosedRestoreOutcome(terminal: .localCredentialUnavailable, webViewLoads: 0, nativeTransactions: 0)
        case .credential:
            ClosedRestoreOutcome(terminal: .restoreCompleted, webViewLoads: 0, nativeTransactions: 1)
        }
    }

    static func presentation(for terminal: ClosedAuthenticationTerminal) -> AuthenticationPresentationCopy {
        switch terminal {
        case .localCredentialMissing:
            AuthenticationPresentationCopy(
                title: "No saved sign-in",
                message: "Sign in to SiriusXM to continue.",
                iconName: "lock",
                statusLabel: "local-credential-missing",
                isReady: false,
                canSignOut: false
            )
        case .localCredentialInvalid:
            AuthenticationPresentationCopy(
                title: "Saved sign-in unavailable",
                message: "The saved sign-in cannot be used.",
                iconName: "exclamationmark.triangle",
                statusLabel: "local-credential-invalid",
                isReady: false,
                canSignOut: false
            )
        case .localCredentialUnavailable:
            AuthenticationPresentationCopy(
                title: "Saved sign-in cannot be accessed",
                message: "Sirius Mac cannot access the saved sign-in.",
                iconName: "exclamationmark.triangle",
                statusLabel: "local-credential-unavailable",
                isReady: false,
                canSignOut: false
            )
        case .webCredentialMissing:
            AuthenticationPresentationCopy(
                title: "Sign-in is incomplete",
                message: "Sirius Mac could not find a usable sign-in.",
                iconName: "exclamationmark.triangle",
                statusLabel: "web-credential-missing",
                isReady: false,
                canSignOut: false
            )
        case .webCredentialMalformed:
            AuthenticationPresentationCopy(
                title: "Sign-in is incomplete",
                message: "Sirius Mac could not use this sign-in.",
                iconName: "exclamationmark.triangle",
                statusLabel: "web-credential-malformed",
                isReady: false,
                canSignOut: false
            )
        case .webCredentialAmbiguous:
            AuthenticationPresentationCopy(
                title: "Sign-in needs attention",
                message: "Sirius Mac could not choose one sign-in.",
                iconName: "exclamationmark.triangle",
                statusLabel: "web-credential-ambiguous",
                isReady: false,
                canSignOut: false
            )
        case .webCredentialTransferred:
            AuthenticationPresentationCopy(
                title: "Verifying sign-in",
                message: "Checking your signed-in session.",
                iconName: "checkmark.shield",
                statusLabel: "web-credential-transferred",
                isReady: false,
                canSignOut: false
            )
        case .webSessionResetFailed:
            AuthenticationPresentationCopy(
                title: "Sign-in could not start",
                message: "Sirius Mac could not start a fresh sign-in session.",
                iconName: "exclamationmark.triangle",
                statusLabel: "web-session-reset-failed",
                isReady: false,
                canSignOut: false
            )
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
                title: "Restored sign-in ready",
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
        case .finishingCleanup:
            AuthenticationPresentationCopy(
                title: "Finishing local cleanup",
                message: "Sirius Mac is finishing local sign-out cleanup.",
                iconName: "hourglass",
                statusLabel: "cleanup-in-progress",
                isReady: false,
                canSignOut: false
            )
        }
    }
}
