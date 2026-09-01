import Foundation
import Observation
import SiriusXMClient

@MainActor
@Observable
final class AuthenticationPresentationModel {
    private let flow: any AuthenticationPresentationFlow
    private var attemptID: UUID?
    private var hasAttemptedLaunchRestore = false
    private var hasPendingAutomaticallyDetectedSession = false

    private(set) var state: AuthenticationPresentationState = .signedOut
    private(set) var isAttemptInFlight = false
    private(set) var backgroundRetryCount = 0

    var isReady: Bool {
        presentation(for: state).isReady
    }

    init(flow: any AuthenticationPresentationFlow = UncomposedAuthenticationPresentationFlow()) {
        self.flow = flow
    }

    @discardableResult
    func signIn() -> Task<Void, Never>? {
        guard canStartWebViewSignIn else { return nil }
        // Keep the current terminal/signed-out subtree mounted until the bridge
        // has retired its old session and queued the new request. Publishing
        // waitingForWebView here would create the representable too early.
        let identifier = startAttempt()
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
            self?.finishAttempt(identifier, with: result == .entitled ? .restoreCompleted : result)
        }
    }

    @discardableResult
    func useLoggedInSession() -> Task<Void, Never>? {
        guard isUsingCurrentWebViewSession, !isAttemptInFlight else { return nil }

        let identifier = startAttempt(at: .verifyingAuthentication)
        let flow = flow
        return Task { [weak self, flow] in
            let result = await flow.useLoggedInSession { [weak self] in
                self?.state = .verifyingEntitlement
            }
            self?.finishAttempt(identifier, with: result)
        }
    }

    /// Receives a material-free readiness signal from the app-owned WebView bridge.
    /// If the signal races the short sign-in setup task, it is retained until the
    /// visible WebView state is published and then consumed exactly once.
    func useAutomaticallyDetectedSession() {
        guard state != .entitled, state != .restoreCompleted else { return }
        guard isUsingCurrentWebViewSession || isAttemptInFlight else { return }
        hasPendingAutomaticallyDetectedSession = true
        consumeAutomaticallyDetectedSessionIfPossible()
    }

    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard isRetryableTerminalState else { return nil }
        return signIn()
    }

    @discardableResult
    func signOut() -> Task<Void, Never>? {
        guard isReady, !isAttemptInFlight else { return nil }

        let identifier = startAttempt(at: .finishingCleanup)
        let flow = flow
        return Task { [weak self, flow] in
            let result = await flow.signOut()
            self?.finishAttempt(identifier, with: result.presentationState)
        }
    }

    @discardableResult
    func clearLocalSession() -> Task<Void, Never>? {
        guard state != .entitled, !isAttemptInFlight else { return nil }

        let identifier = startAttempt(at: .finishingCleanup)
        let flow = flow
        return Task { [weak self, flow] in
            let result = await flow.signOut()
            self?.finishAttempt(identifier, with: result.presentationState)
        }
    }

    private var canStartWebViewSignIn: Bool {
        guard !isAttemptInFlight else { return false }
        return state == .waitingForWebView || isRetryableTerminalState
    }

    private var isUsingCurrentWebViewSession: Bool {
        switch state {
        case .waitingForWebView, .webCredentialMissing, .webCredentialMalformed, .webCredentialAmbiguous:
            true
        default:
            false
        }
    }

    private var isRetryableTerminalState: Bool {
        switch state {
        case .localCredentialMissing,
             .authenticatedButNotEntitled,
             .profileAuthorizationRejected,
             .entitlementAuthorizationRejected,
             .credentialNotDurable,
             .rejected,
             .challengeRequired,
             .unsupported,
             .localCredentialInvalid,
             .localCredentialUnavailable,
             .webSessionResetFailed,
             .signedOut,
             .cleanupFailed:
            true
        case .waitingForWebView,
             .webCredentialMissing,
             .webCredentialMalformed,
             .webCredentialAmbiguous,
             .verifyingAuthentication,
             .verifyingEntitlement,
             .entitled,
             .restoreCompleted,
             .finishingCleanup:
            false
        }
    }

    private func startAttempt(at state: AuthenticationPresentationState? = nil) -> UUID {
        let identifier = UUID()
        attemptID = identifier
        isAttemptInFlight = true
        if let state {
            self.state = state
        }
        return identifier
    }

    private func finishAttempt(_ identifier: UUID, with state: AuthenticationPresentationState) {
        guard attemptID == identifier else { return }
        attemptID = nil
        isAttemptInFlight = false
        self.state = state
        guard isUsingCurrentWebViewSession else {
            hasPendingAutomaticallyDetectedSession = false
            return
        }
        consumeAutomaticallyDetectedSessionIfPossible()
    }

    private func consumeAutomaticallyDetectedSessionIfPossible() {
        guard hasPendingAutomaticallyDetectedSession,
              isUsingCurrentWebViewSession,
              !isAttemptInFlight else {
            return
        }
        hasPendingAutomaticallyDetectedSession = false
        _ = useLoggedInSession()
    }

    func presentation(for state: AuthenticationPresentationState) -> AuthenticationPresentationCopy {
        ClosedAuthenticationOracle.presentation(for: state.closedTerminal)
    }
}

enum AuthenticationPresentationState: Equatable {
    case localCredentialMissing
    case localCredentialInvalid
    case localCredentialUnavailable
    case webSessionResetFailed
    case waitingForWebView
    case webCredentialMissing
    case webCredentialMalformed
    case webCredentialAmbiguous
    case verifyingAuthentication
    case verifyingEntitlement
    case authenticatedButNotEntitled
    case entitled
    case restoreCompleted
    case profileAuthorizationRejected
    case entitlementAuthorizationRejected
    case credentialNotDurable
    case rejected
    case challengeRequired
    case unsupported
    case signedOut
    case cleanupFailed(SignOutCleanupFailure)
    case finishingCleanup
}

private extension AuthenticationPresentationState {
    var closedTerminal: ClosedAuthenticationTerminal {
        switch self {
        case .localCredentialMissing: .localCredentialMissing
        case .localCredentialInvalid: .localCredentialInvalid
        case .localCredentialUnavailable: .localCredentialUnavailable
        case .webSessionResetFailed: .webSessionResetFailed
        case .waitingForWebView: .waitingForWebView
        case .webCredentialMissing: .webCredentialMissing
        case .webCredentialMalformed: .webCredentialMalformed
        case .webCredentialAmbiguous: .webCredentialAmbiguous
        case .verifyingAuthentication: .verifyingAuthentication
        case .verifyingEntitlement: .verifyingEntitlement
        case .authenticatedButNotEntitled: .authenticatedButNotEntitled
        case .entitled: .durableReady
        case .restoreCompleted: .restoreCompleted
        case .profileAuthorizationRejected: .profileUnauthorized
        case .entitlementAuthorizationRejected: .entitlementUnauthorized
        case .credentialNotDurable: .persistenceFailed
        case .rejected: .rejected
        case .challengeRequired: .challengeRequired
        case .unsupported: .unsupported
        case .signedOut: .signedOut
        case .cleanupFailed: .cleanupFailed
        case .finishingCleanup: .finishingCleanup
        }
    }
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
    func latestAuthenticationDiagnostic() async -> AuthenticationDiagnosticOutcome?
    func entitlementAvailability() async -> EntitlementAvailability
    func signOut() async -> SignOutOutcome
}

extension ClientAuthenticationFlow {
    func latestAuthenticationDiagnostic() async -> AuthenticationDiagnosticOutcome? { nil }
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
        await bridge.beginUserOperatedSignIn() ? .waitingForWebView : .webSessionResetFailed
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
                isAutomaticRestore: true,
                onEntitlementVerification: onEntitlementVerification
            )
        case .missing:
            return .localCredentialMissing
        case .invalidCredential:
            return .localCredentialInvalid
        case .unavailable:
            return .localCredentialUnavailable
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
                isAutomaticRestore: false,
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
        switch await bridge.useLoggedInSession() {
        case .credentialTransferred:
            break
        case .authCookieMissing:
            return .webCredentialMissing
        case .malformedCredential:
            return .webCredentialMalformed
        case .ambiguousCredentials:
            return .webCredentialAmbiguous
        case .cancelled, .alreadyConsumed:
            return .waitingForWebView
        }
        return await completeClientTransaction(
            credentialSource: credentialSource,
            isAutomaticRestore: false,
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
            .entitlementAuthorizationRejected
        case .challengeRequired:
            .challengeRequired
        case .unavailable, .unsupported, .cancelled:
            .unsupported
        }
    }

    private func completeClientTransaction(
        credentialSource: RestorableAuthenticationCredentialSource?,
        isAutomaticRestore: Bool,
        onEntitlementVerification: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        let state: AuthenticationPresentationState
        let authenticationOutcome = await client.authenticate()
        if let diagnostic = await client.latestAuthenticationDiagnostic() {
            credentialSource?.recordNativeAuthenticationDiagnostic(diagnostic)
        }
        switch authenticationOutcome {
        case .authenticatedPendingEntitlement:
            onEntitlementVerification()
            state = presentationState(for: await client.entitlementAvailability())
        case .credentialUnavailable:
            state = isAutomaticRestore ? .localCredentialUnavailable : .webCredentialMissing
        case .waitingForAuthenticationComposition, .unsupported, .cancelled:
            state = .unsupported
        case .credentialPersistenceFailed:
            state = .credentialNotDurable
        case .rejected:
            state = .profileAuthorizationRejected
        case .challengeRequired:
            state = .challengeRequired
        }

        guard state == .entitled else {
            credentialSource?.finishRejectedRestore(state.closedTerminal)
            credentialSource?.finishWebViewAttempt()
            return state
        }

        guard isAutomaticRestore else {
            credentialSource?.finalizeSuccessfulRestore()
            credentialSource?.finishWebViewAttempt()
            return state
        }

        credentialSource?.finalizeSuccessfulRestore()
        credentialSource?.finishWebViewAttempt()
        return .restoreCompleted
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
