import Foundation
import Observation
import SiriusXMClient

@MainActor
@Observable
final class AuthenticationPresentationModel {
    private(set) var state: AuthenticationPresentationState = .waitingForWebView
    private(set) var diagnostics: [SafeAuthenticationDiagnostic] = []

    func presentation(for state: AuthenticationPresentationState) -> AuthenticationPresentationCopy {
        AuthenticationPresentationCopy(
            title: "Preparing sign-in",
            message: "Sirius Mac is preparing the native sign-in experience.",
            isReady: false,
            canSignOut: false
        )
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
