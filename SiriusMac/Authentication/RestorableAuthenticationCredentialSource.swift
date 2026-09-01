import Foundation
import OSLog
import SiriusXMClient

@MainActor
struct RestorableAuthenticationCredentialTelemetry {
    private let recorder: (ClosedAuthenticationTerminal) -> Void

    init(record: @escaping (ClosedAuthenticationTerminal) -> Void = { _ in }) {
        recorder = record
    }

    static let disabled = RestorableAuthenticationCredentialTelemetry()

    static let live: RestorableAuthenticationCredentialTelemetry = {
        let logger = Logger(
            subsystem: ProductIdentity.appLogSubsystem,
            category: "authentication-lifecycle"
        )
        return RestorableAuthenticationCredentialTelemetry { terminal in
            // Authentication lifecycle events are intentionally restricted to the
            // closed terminal vocabulary. Never include credentials, cookies,
            // provider responses, or Keychain status values here.
            logger.notice("\(ProductIdentity.displayName) authentication lifecycle: \(terminal.rawValue, privacy: .public)")
        }
    }()

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
    private var supportDiagnosticRecorder: (StoredCredentialLoadDiagnostic) -> Void = { _ in }
    private var nativeAuthenticationDiagnosticRecorder: (NativeAuthenticationAttemptDiagnostic) -> Void = { _ in }
    private var attemptOrigin: AttemptOrigin = .none
    private var isStoredCredentialQuarantined = false

    init(
        keychain: KeychainCredentialStore,
        webViewSource: WebAuthenticationBridge,
        telemetry: RestorableAuthenticationCredentialTelemetry = .disabled
    ) {
        self.keychain = keychain
        self.webViewSource = webViewSource
        self.telemetry = telemetry
    }

    func setStoredCredentialLoadDiagnosticHandler(
        _ handler: @escaping @MainActor (StoredCredentialLoadDiagnostic) -> Void
    ) {
        supportDiagnosticRecorder = handler
    }

    func setNativeAuthenticationDiagnosticHandler(
        _ handler: @escaping @MainActor (NativeAuthenticationAttemptDiagnostic) -> Void
    ) {
        nativeAuthenticationDiagnosticRecorder = handler
    }

    func recordNativeAuthenticationDiagnostic(_ outcome: AuthenticationDiagnosticOutcome) {
        nativeAuthenticationDiagnosticRecorder(NativeAuthenticationAttemptDiagnostic(
            recordedAt: Date(),
            outcome: outcome
        ))
    }

    /// Reads the Keychain only after a user explicitly starts Sign In.
    func prepareForExplicitSignIn() -> ExplicitSignInCredentialPreparation {
        guard case .none = attemptOrigin else { return .unavailable }

        // A native rejection proves that re-reading the same stored material in
        // this process cannot advance the user. Preserve it in Keychain, but
        // require the next explicit attempt to obtain a fresh WebView session.
        if isStoredCredentialQuarantined {
            attemptOrigin = .webViewRequired
            recordStoredCredentialLoad(purpose: .explicitSignIn, outcome: .quarantined)
            return .webViewRequired
        }

        switch keychain.loadStoredCredentialForAuthentication() {
        case let .credential(credential):
            attemptOrigin = .restoredStaged(credential)
            recordStoredCredentialLoad(
                purpose: .explicitSignIn,
                outcome: .ready,
                credentialReference: credential.supportDiagnosticReference
            )
            return .restoredCredentialReady
        case .missing:
            attemptOrigin = .webViewRequired
            recordStoredCredentialLoad(purpose: .explicitSignIn, outcome: .missing)
            return .webViewRequired
        case .invalid:
            // Automatic restore fails closed, but an explicit owner action must
            // remain capable of replacing unusable material through SiriusXM's
            // browser sign-in. The existing item is not deleted here.
            attemptOrigin = .webViewRequired
            recordStoredCredentialLoad(purpose: .explicitSignIn, outcome: .invalid)
            return .webViewRequired
        case .unavailable:
            attemptOrigin = .webViewRequired
            recordStoredCredentialLoad(purpose: .explicitSignIn, outcome: .keychainUnavailable)
            return .webViewRequired
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
            recordStoredCredentialLoad(
                purpose: .automaticRestore,
                outcome: .ready,
                credentialReference: credential.supportDiagnosticReference
            )
            return .restoredCredentialReady
        case .missing:
            telemetry.record(.localCredentialMissing)
            recordStoredCredentialLoad(purpose: .automaticRestore, outcome: .missing)
            return .missing
        case .invalid:
            telemetry.record(.localCredentialInvalid)
            recordStoredCredentialLoad(purpose: .automaticRestore, outcome: .invalid)
            return .invalidCredential
        case .unavailable:
            telemetry.record(.localCredentialUnavailable)
            recordStoredCredentialLoad(purpose: .automaticRestore, outcome: .keychainUnavailable)
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
        isStoredCredentialQuarantined = false
        if case .restoredInFlight = attemptOrigin {
            attemptOrigin = .none
            telemetry.record(.restoreCompleted)
        }
    }

    /// Retires a rejected restored attempt without changing persistent storage.
    func finishRejectedRestore(_ terminal: ClosedAuthenticationTerminal) {
        guard isRestoredAttempt else { return }
        attemptOrigin = .none
        isStoredCredentialQuarantined = true
        telemetry.record(terminal)
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

    private func recordStoredCredentialLoad(
        purpose: StoredCredentialLoadPurpose,
        outcome: StoredCredentialLoadOutcome,
        credentialReference: String? = nil
    ) {
        supportDiagnosticRecorder(StoredCredentialLoadDiagnostic(
            recordedAt: Date(),
            purpose: purpose,
            outcome: outcome,
            credentialReference: credentialReference
        ))
    }
}
