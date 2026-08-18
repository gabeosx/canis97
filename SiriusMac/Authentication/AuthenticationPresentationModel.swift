import Foundation
import Observation
import SiriusXMClient

@MainActor
@Observable
final class AuthenticationPresentationModel {
    private let flow: any AuthenticationPresentationFlow

    private(set) var state: AuthenticationPresentationState = .waitingForWebView
    private(set) var diagnostics: [SafeAuthenticationDiagnostic] = []
    private(set) var isAttemptInFlight = false
    private(set) var backgroundRetryCount = 0

    init(flow: any AuthenticationPresentationFlow = UncomposedAuthenticationPresentationFlow()) {
        self.flow = flow
    }

    func signIn() {
        Task { @MainActor in
            state = await flow.beginWebViewSignIn()
        }
    }

    func useLoggedInSession() {
        Task { @MainActor in
            state = await flow.useLoggedInSession()
        }
    }

    func retry() {
        signIn()
    }

    func signOut() {
        Task { @MainActor in
            let result = await flow.signOut()
            state = result.presentationState
        }
    }

    func presentation(for state: AuthenticationPresentationState) -> AuthenticationPresentationCopy {
        switch state {
        case .waitingForWebView:
            AuthenticationPresentationCopy(
                title: "Sign in to SiriusXM",
                message: "Sign in in the native window to continue.",
                iconName: "lock",
                isReady: false,
                canSignOut: false
            )
        case .verifyingAuthentication:
            AuthenticationPresentationCopy(
                title: "Verifying sign-in",
                message: "Checking your signed-in session.",
                iconName: "checkmark.shield",
                isReady: false,
                canSignOut: false
            )
        case .verifyingEntitlement:
            AuthenticationPresentationCopy(
                title: "Checking subscription",
                message: "Confirming that this account can listen.",
                iconName: "checkmark.seal",
                isReady: false,
                canSignOut: false
            )
        case .authenticatedButNotEntitled:
            AuthenticationPresentationCopy(
                title: "Subscription unavailable",
                message: "This signed-in account is not currently entitled to listen.",
                iconName: "person.crop.circle.badge.exclamationmark",
                isReady: false,
                canSignOut: false
            )
        case .entitled:
            AuthenticationPresentationCopy(
                title: "Ready to listen",
                message: "Your account is signed in and ready.",
                iconName: "checkmark.circle",
                isReady: true,
                canSignOut: true
            )
        case .rejected:
            AuthenticationPresentationCopy(
                title: "Sign-in was rejected",
                message: "SiriusXM did not accept this sign-in attempt.",
                iconName: "xmark.circle",
                isReady: false,
                canSignOut: false
            )
        case .challengeRequired:
            AuthenticationPresentationCopy(
                title: "Additional verification is required",
                message: "This sign-in needs a challenge that Sirius Mac does not handle.",
                iconName: "exclamationmark.shield",
                isReady: false,
                canSignOut: false
            )
        case .unsupported:
            AuthenticationPresentationCopy(
                title: "Sign-in flow unsupported",
                message: "This sign-in flow is unsupported. No workaround was attempted.",
                iconName: "exclamationmark.triangle",
                isReady: false,
                canSignOut: false
            )
        case .signedOut:
            AuthenticationPresentationCopy(
                title: "Signed out",
                message: "You are signed out of Sirius Mac.",
                iconName: "rectangle.portrait.and.arrow.right",
                isReady: false,
                canSignOut: false
            )
        case .cleanupFailed:
            AuthenticationPresentationCopy(
                title: "Signed out with cleanup warning",
                message: "You are signed out. Local cleanup was incomplete.",
                iconName: "exclamationmark.triangle",
                isReady: false,
                canSignOut: false
            )
        }
    }

    func record(_ diagnostic: SafeAuthenticationDiagnostic) {
        diagnostics.append(diagnostic)
    }
}

enum AuthenticationPresentationState: Equatable {
    case waitingForWebView
    case verifyingAuthentication
    case verifyingEntitlement
    case authenticatedButNotEntitled
    case entitled
    case rejected
    case challengeRequired
    case unsupported
    case signedOut
    case cleanupFailed(SignOutCleanupFailure)
}

struct AuthenticationPresentationCopy: Equatable {
    let title: String
    let message: String
    let iconName: String
    let isReady: Bool
    let canSignOut: Bool
}

enum SafeAuthenticationDiagnostic: Equatable {
    case signInStarted
    case authenticationRejected
    case challengeRequired
    case unsupported
    case signedOut
    case cleanupFailed
}

protocol AuthenticationPresentationFlow: Sendable {
    func beginWebViewSignIn() async -> AuthenticationPresentationState
    func useLoggedInSession() async -> AuthenticationPresentationState
    func signOut() async -> SignOutOutcome
}

private struct UncomposedAuthenticationPresentationFlow: AuthenticationPresentationFlow {
    func beginWebViewSignIn() async -> AuthenticationPresentationState {
        .waitingForWebView
    }

    func useLoggedInSession() async -> AuthenticationPresentationState {
        .waitingForWebView
    }

    func signOut() async -> SignOutOutcome {
        .alreadySignedOut
    }
}

private extension SignOutOutcome {
    var presentationState: AuthenticationPresentationState {
        switch self {
        case .alreadySignedOut, .signedOut:
            .signedOut
        case .cleanupFailed(let failure):
            .cleanupFailed(failure)
        }
    }
}
