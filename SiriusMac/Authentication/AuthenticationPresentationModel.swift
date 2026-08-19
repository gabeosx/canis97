import Foundation
import Observation
import SiriusXMClient

@MainActor
@Observable
final class AuthenticationPresentationModel {
    private let flow: any AuthenticationPresentationFlow
    private var attemptID: UUID?
    private var hasAttemptedLaunchRestore = false

    private(set) var state: AuthenticationPresentationState = .signedOut
    private(set) var diagnostics: [SafeAuthenticationDiagnostic] = []
    private(set) var isAttemptInFlight = false
    private(set) var backgroundRetryCount = 0

    init(flow: any AuthenticationPresentationFlow = UncomposedAuthenticationPresentationFlow()) {
        self.flow = flow
    }

    @discardableResult
    func signIn() -> Task<Void, Never>? {
        guard canStartWebViewSignIn else { return nil }
        let identifier = startAttempt(at: .waitingForWebView)
        let flow = flow
        return Task { [weak self, flow] in
            let result = await flow.prepareForExplicitSignIn(
                onAuthenticationVerification: { [weak self] in
                    self?.state = .verifyingAuthentication
                },
                onEntitlementVerification: { [weak self] in
                    self?.state = .verifyingEntitlement
                }
            )
            self?.finishAttempt(identifier, with: result)
        }
    }

    /// Makes the sole automatic Keychain restore attempt for this presentation model.
    ///
    /// This never selects WebView cookies or begins a user-operated sign-in. Missing
    /// credentials settle into the signed-out UI; terminal storage and client outcomes
    /// are supplied unchanged by the composed flow.
    @discardableResult
    func restoreStoredCredentialOnLaunch() -> Task<Void, Never>? {
        guard !hasAttemptedLaunchRestore, !isAttemptInFlight else { return nil }

        hasAttemptedLaunchRestore = true
        let identifier = startAttempt(at: .verifyingAuthentication)
        let flow = flow
        return Task { [weak self, flow] in
            let result = await flow.restoreStoredCredential(
                onAuthenticationVerification: { [weak self] in
                    self?.state = .verifyingAuthentication
                },
                onEntitlementVerification: { [weak self] in
                    self?.state = .verifyingEntitlement
                }
            )
            self?.finishAttempt(identifier, with: result)
        }
    }

    @discardableResult
    func useLoggedInSession() -> Task<Void, Never>? {
        guard state == .waitingForWebView, !isAttemptInFlight else { return nil }

        let identifier = startAttempt(at: .verifyingAuthentication)
        let flow = flow
        return Task { [weak self, flow] in
            let result = await flow.useLoggedInSession { [weak self] in
                self?.state = .verifyingEntitlement
            }
            self?.finishAttempt(identifier, with: result)
        }
    }

    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard isRetryableTerminalState else { return nil }
        state = .waitingForWebView
        return signIn()
    }

    @discardableResult
    func signOut() -> Task<Void, Never>? {
        guard state == .entitled, !isAttemptInFlight else { return nil }

        let identifier = startAttempt(at: .entitled)
        let flow = flow
        return Task { [weak self, flow] in
            let result = await flow.signOut()
            self?.finishAttempt(identifier, with: result.presentationState)
        }
    }

    @discardableResult
    func clearLocalSession() -> Task<Void, Never>? {
        guard state != .entitled, !isAttemptInFlight else { return nil }

        let identifier = startAttempt(at: state)
        let flow = flow
        return Task { [weak self, flow] in
            let result = await flow.signOut()
            self?.finishAttempt(identifier, with: result.presentationState)
        }
    }

    private var canStartWebViewSignIn: Bool {
        guard !isAttemptInFlight else { return false }
        return switch state {
        case .waitingForWebView, .signedOut:
            true
        default:
            false
        }
    }

    private var isRetryableTerminalState: Bool {
        switch state {
        case .authenticatedButNotEntitled,
             .rejected,
             .challengeRequired,
             .unsupported,
             .signedOut,
             .cleanupFailed:
            true
        case .waitingForWebView,
             .verifyingAuthentication,
             .verifyingEntitlement,
             .entitled:
            false
        }
    }

    private func startAttempt(at state: AuthenticationPresentationState) -> UUID {
        let identifier = UUID()
        attemptID = identifier
        isAttemptInFlight = true
        self.state = state
        return identifier
    }

    private func finishAttempt(_ identifier: UUID, with state: AuthenticationPresentationState) {
        guard attemptID == identifier else { return }
        attemptID = nil
        isAttemptInFlight = false
        self.state = state
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
    func restoreStoredCredential(
        onAuthenticationVerification: @MainActor @escaping @Sendable () -> Void,
        onEntitlementVerification: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState
    func prepareForExplicitSignIn(
        onAuthenticationVerification: @MainActor @escaping @Sendable () -> Void,
        onEntitlementVerification: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState
    func useLoggedInSession(
        onEntitlementVerification: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState
    func signOut() async -> SignOutOutcome
}

extension AuthenticationPresentationFlow {
    func restoreStoredCredential(
        onAuthenticationVerification _: @MainActor @escaping @Sendable () -> Void,
        onEntitlementVerification _: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        .signedOut
    }

    func prepareForExplicitSignIn(
        onAuthenticationVerification _: @MainActor @escaping @Sendable () -> Void,
        onEntitlementVerification _: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        await beginWebViewSignIn()
    }
}

protocol ClientAuthenticationFlow: Sendable {
    func authenticate() async -> AuthenticationOutcome
    func entitlementAvailability() async -> EntitlementAvailability
    func signOut() async -> SignOutOutcome
}

extension SiriusXMClient: ClientAuthenticationFlow {
    func entitlementAvailability() async -> EntitlementAvailability {
        await entitlement()
    }
}

@MainActor
struct ComposedAuthenticationPresentationFlow: AuthenticationPresentationFlow {
    let bridge: WebAuthenticationBridge
    let client: any ClientAuthenticationFlow
    let credentialSource: RestorableAuthenticationCredentialSource?

    init(
        bridge: WebAuthenticationBridge,
        client: any ClientAuthenticationFlow,
        credentialSource: RestorableAuthenticationCredentialSource? = nil
    ) {
        self.bridge = bridge
        self.client = client
        self.credentialSource = credentialSource
    }

    func beginWebViewSignIn() async -> AuthenticationPresentationState {
        await bridge.beginUserOperatedSignIn()
        return .waitingForWebView
    }

    func restoreStoredCredential(
        onAuthenticationVerification: @MainActor @escaping @Sendable () -> Void,
        onEntitlementVerification: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        guard let credentialSource else { return .signedOut }

        switch credentialSource.prepareForAutomaticRestore() {
        case .restoredCredentialReady:
            onAuthenticationVerification()
            return await completeClientTransaction(
                credentialSource: credentialSource,
                onEntitlementVerification: onEntitlementVerification
            )
        case .missing:
            return .signedOut
        case .invalidCredential, .unavailable:
            return .unsupported
        }
    }

    func prepareForExplicitSignIn(
        onAuthenticationVerification: @MainActor @escaping @Sendable () -> Void,
        onEntitlementVerification: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        guard let credentialSource else {
            return await beginWebViewSignIn()
        }

        switch credentialSource.prepareForExplicitSignIn() {
        case .restoredCredentialReady:
            onAuthenticationVerification()
            return await completeClientTransaction(
                credentialSource: credentialSource,
                onEntitlementVerification: onEntitlementVerification
            )
        case .webViewRequired:
            return await beginWebViewSignIn()
        case .invalidCredential, .unavailable:
            return .unsupported
        }
    }

    func useLoggedInSession(
        onEntitlementVerification: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        guard await bridge.useLoggedInSession() == .credentialTransferred else {
            credentialSource?.finishWebViewAttempt()
            return .unsupported
        }
        return await completeClientTransaction(
            credentialSource: credentialSource,
            onEntitlementVerification: onEntitlementVerification
        )
    }

    func signOut() async -> SignOutOutcome {
        await client.signOut()
    }

    private func presentationState(for entitlement: EntitlementAvailability) -> AuthenticationPresentationState {
        switch entitlement {
        case .entitled:
            .entitled
        case .authenticatedButNotEntitled:
            .authenticatedButNotEntitled
        case .rejected:
            .rejected
        case .challengeRequired:
            .challengeRequired
        case .unavailable, .unsupported, .cancelled:
            .unsupported
        }
    }

    private func completeClientTransaction(
        credentialSource: RestorableAuthenticationCredentialSource?,
        onEntitlementVerification: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        let state: AuthenticationPresentationState
        switch await client.authenticate() {
        case .authenticatedPendingEntitlement:
            onEntitlementVerification()
            state = presentationState(for: await client.entitlementAvailability())
        case .waitingForAuthenticationComposition, .unsupported, .cancelled:
            state = .unsupported
        case .rejected:
            state = .rejected
        case .challengeRequired:
            state = .challengeRequired
        }

        guard state != .entitled else {
            credentialSource?.finalizeSuccessfulRestore()
            credentialSource?.finishWebViewAttempt()
            return state
        }

        credentialSource?.finishRejectedRestore()
        credentialSource?.finishWebViewAttempt()
        return state
    }
}

private struct UncomposedAuthenticationPresentationFlow: AuthenticationPresentationFlow {
    func beginWebViewSignIn() async -> AuthenticationPresentationState {
        .waitingForWebView
    }

    func useLoggedInSession(
        onEntitlementVerification _: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
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
