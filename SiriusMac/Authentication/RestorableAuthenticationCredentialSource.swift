import SiriusXMClient

/// The sole app-owned credential source used for native authentication attempts.
///
/// A saved Keychain item is merely a one-shot opaque input: the client still owns
/// native authentication, entitlement verification, and active-session publication.
@MainActor
final class RestorableAuthenticationCredentialSource: CredentialSource {
    enum ExplicitSignInCredentialPreparation: Equatable {
        case restoredCredentialReady
        case webViewRequired
        case invalidCredentialErased
        case cleanupFailed
        case unavailable
    }

    enum AutomaticRestoreCredentialPreparation: Equatable {
        case restoredCredentialReady
        case missing
        case invalidCredentialErased
        case cleanupFailed
        case unavailable
    }

    enum RestoreErasureOutcome: Equatable {
        case notRequired
        case erased
        case cleanupFailed
    }

    private enum AttemptOrigin {
        case none
        case restoredStaged(AuthenticationCredential)
        case restoredInFlight
        case webViewRequired
        case webViewInFlight
    }

    private let keychain: KeychainCredentialStore
    private let webViewSource: WebAuthenticationBridge
    private var attemptOrigin: AttemptOrigin = .none

    init(keychain: KeychainCredentialStore, webViewSource: WebAuthenticationBridge) {
        self.keychain = keychain
        self.webViewSource = webViewSource
    }

    /// Reads the Keychain only after a user explicitly starts Sign In.
    func prepareForExplicitSignIn() -> ExplicitSignInCredentialPreparation {
        guard case .none = attemptOrigin else { return .unavailable }

        switch keychain.loadStoredCredentialForAuthentication() {
        case let .credential(credential):
            attemptOrigin = .restoredStaged(credential)
            return .restoredCredentialReady
        case .missing:
            attemptOrigin = .webViewRequired
            return .webViewRequired
        case .invalidErased:
            return .invalidCredentialErased
        case .cleanupFailed:
            return .cleanupFailed
        case .unavailable:
            return .unavailable
        }
    }

    /// Reads only the app-owned Keychain credential for the one automatic launch
    /// restoration attempt. It never selects WebView cookies or starts an owner-
    /// operated sign-in when the stored material is absent or unusable.
    func prepareForAutomaticRestore() -> AutomaticRestoreCredentialPreparation {
        guard case .none = attemptOrigin else { return .unavailable }

        switch keychain.loadStoredCredentialForAuthentication() {
        case let .credential(credential):
            attemptOrigin = .restoredStaged(credential)
            return .restoredCredentialReady
        case .missing:
            return .missing
        case .invalidErased:
            return .invalidCredentialErased
        case .cleanupFailed:
            return .cleanupFailed
        case .unavailable:
            return .unavailable
        }
    }

    /// Supplies exactly one prepared opaque credential to the unchanged client path.
    func credential() async -> AuthenticationCredential? {
        switch attemptOrigin {
        case let .restoredStaged(credential):
            attemptOrigin = .restoredInFlight
            return credential
        case .webViewRequired:
            attemptOrigin = .webViewInFlight
            return await webViewSource.credential()
        case .none, .restoredInFlight, .webViewInFlight:
            return nil
        }
    }

    func finalizeSuccessfulRestore() {
        if case .restoredInFlight = attemptOrigin {
            attemptOrigin = .none
        }
    }

    /// Erases a rejected restored item before a terminal state becomes visible.
    func eraseRejectedRestore() async -> RestoreErasureOutcome {
        guard isRestoredAttempt else { return .notRequired }
        attemptOrigin = .none

        do {
            try await keychain.erase()
            return .erased
        } catch {
            return .cleanupFailed
        }
    }

    func finishWebViewAttempt() {
        if case .webViewRequired = attemptOrigin {
            attemptOrigin = .none
        } else if case .webViewInFlight = attemptOrigin {
            attemptOrigin = .none
        }
    }

    private var isRestoredAttempt: Bool {
        switch attemptOrigin {
        case .restoredStaged, .restoredInFlight:
            true
        case .none, .webViewRequired, .webViewInFlight:
            false
        }
    }
}
