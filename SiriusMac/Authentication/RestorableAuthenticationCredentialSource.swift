import SiriusXMClient

@MainActor
struct RestorableAuthenticationCredentialTelemetry {
    private let recorder: (ClosedAuthenticationTerminal) -> Void

    init(record: @escaping (ClosedAuthenticationTerminal) -> Void = { _ in }) {
        recorder = record
    }

    static let disabled = RestorableAuthenticationCredentialTelemetry()

    func record(_ terminal: ClosedAuthenticationTerminal) {
        recorder(terminal)
    }
}

/// The sole app-owned credential source used for native authentication attempts.
///
/// A saved Keychain item is merely a one-shot opaque input: the client still owns
/// native authentication, entitlement verification, and active-session publication.
@MainActor
final class RestorableAuthenticationCredentialSource: CredentialSource {
    enum ExplicitSignInCredentialPreparation: Equatable {
        case restoredCredentialReady
        case webViewRequired
        case invalidCredential
        case unavailable
    }

    enum AutomaticRestoreCredentialPreparation: Equatable {
        case restoredCredentialReady
        case missing
        case invalidCredential
        case unavailable
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
    private let telemetry: RestorableAuthenticationCredentialTelemetry
    private var attemptOrigin: AttemptOrigin = .none

    init(
        keychain: KeychainCredentialStore,
        webViewSource: WebAuthenticationBridge,
        telemetry: RestorableAuthenticationCredentialTelemetry = .disabled
    ) {
        self.keychain = keychain
        self.webViewSource = webViewSource
        self.telemetry = telemetry
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
        case .invalid:
            return .invalidCredential
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
            telemetry.record(.localCredentialMissing)
            return .missing
        case .invalid:
            telemetry.record(.localCredentialInvalid)
            return .invalidCredential
        case .unavailable:
            telemetry.record(.localCredentialUnavailable)
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
            telemetry.record(.restoreCompleted)
        }
    }

    /// Retires a rejected restored attempt without changing persistent storage.
    func finishRejectedRestore() {
        guard isRestoredAttempt else { return }
        attemptOrigin = .none
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
