import Foundation
import OSLog
import WebKit
@_spi(AppIntegration) import SiriusXMClient

enum AuthenticationBridgeDiagnostic: String, CaseIterable, Equatable {
    case webSignInStarted = "web-sign-in-started"
    case cookieStoreChangeObserved = "cookie-store-change-observed"
    case webPageStateChangeObserved = "web-page-state-change-observed"
    case automaticCredentialInspectionStarted = "automatic-credential-inspection-started"
    case automaticCredentialReady = "automatic-credential-ready"
    case credentialSelectionStarted = "credential-selection-started"
    case authCookieNameAbsent = "auth-cookie-name-absent"
    case authCookieIssuerRejected = "auth-cookie-issuer-rejected"
    case authCookiePathRejected = "auth-cookie-path-rejected"
    case authCookieExpired = "auth-cookie-expired"
    case authCookieMissing = "auth-cookie-missing"
    case ambiguousCredentials = "ambiguous-credentials"
    case malformedCredential = "malformed-credential"
    case authenticationCookieTooLarge = "authentication-cookie-too-large"
    case authenticationCookieUnreadable = "authentication-cookie-unreadable"
    case sessionObjectMissing = "session-object-missing"
    case sessionObjectInvalid = "session-object-invalid"
    case accessTokenMissing = "access-token-missing"
    case accessTokenInvalid = "access-token-invalid"
    case accessTokenExpiryMissing = "access-token-expiry-missing"
    case accessTokenExpiryInvalid = "access-token-expiry-invalid"
    case refreshTokenMissing = "refresh-token-missing"
    case refreshTokenInvalid = "refresh-token-invalid"
    case refreshTokenExpiryMissing = "refresh-token-expiry-missing"
    case refreshTokenExpiryInvalid = "refresh-token-expiry-invalid"
    case sessionRefreshCookieMissing = "session-refresh-cookie-missing"
    case sessionRefreshCookieInvalid = "session-refresh-cookie-invalid"
    case renewalAuthorityMissing = "renewal-authority-missing"
    case sessionTypeRejected = "session-type-rejected"
    case credentialEnvelopeEncodingFailed = "credential-envelope-encoding-failed"
    case credentialEnvelopeTooLarge = "credential-envelope-too-large"
    case deviceGrantAbsent = "device-grant-absent"
    case deviceGrantAccepted = "device-grant-accepted"
    case deviceGrantDiscardedUnrecognized = "device-grant-discarded-unrecognized"
    case renewalViaRefreshToken = "renewal-via-refresh-token"
    case renewalViaSessionRefreshCookie = "renewal-via-session-refresh-cookie"
    case selectionCancelled = "selection-cancelled"
    case credentialAlreadyConsumed = "credential-already-consumed"
    case credentialTransferred = "credential-transferred"
    case browserSessionRefreshStarted = "browser-session-refresh-started"
    case browserSessionRefreshCompleted = "browser-session-refresh-completed"
    case browserSessionRefreshFailed = "browser-session-refresh-failed"
    case websiteSessionResetFailed = "web-session-reset-failed"
    case webNavigationStarted = "web-navigation-started"
    case webNavigationRequested = "web-navigation-requested"
    case webNavigationCommitted = "web-navigation-committed"
    case webNavigationFinished = "web-navigation-finished"
    case webNavigationProvisionalFailed = "web-navigation-provisional-failed"
    case webNavigationFailed = "web-navigation-failed"
    case webContentProcessTerminated = "web-content-process-terminated"
}

enum BrowserSessionRenewalDriverFailure: String, Sendable, Equatable {
    case attemptAlreadyInProgress = "attempt-already-in-progress"
    case cookieRehydrationFailed = "cookie-rehydration-failed"
    case navigationFailed = "navigation-failed"
    case timedOutWaitingForCredential = "timed-out-waiting-for-credential"
    case replacementCredentialMissing = "replacement-credential-missing"
    case replacementCredentialAmbiguous = "replacement-credential-ambiguous"
    case replacementCredentialMalformed = "replacement-credential-malformed"
    case accessTokenUnchanged = "access-token-unchanged"
    case replacementRenewalExpired = "replacement-renewal-expired"
    case nativeRenewalAuthorityUnavailable = "native-renewal-authority-unavailable"
    case nativeRenewalAuthorityExpired = "native-renewal-authority-expired"
    case nativeTransportFailed = "native-transport-failed"
    case nativeAuthorizationRejected = "native-authorization-rejected"
    case nativeRateLimited = "native-rate-limited"
    case nativeServerUnavailable = "native-server-unavailable"
    case nativeRedirectRejected = "native-redirect-rejected"
    case nativeResponseUnsupported = "native-response-unsupported"
    case nativeReplacementUnusable = "native-replacement-unusable"
    case cancelled
    case configurationUnavailable = "configuration-unavailable"
}

enum BrowserSessionRenewalDriverResult: Sendable {
    case refreshed(AuthenticationCredential)
    case failed(BrowserSessionRenewalDriverFailure)
}

@MainActor
struct AuthenticationBridgeTelemetry {
    private let recorder: (AuthenticationBridgeDiagnostic) -> Void
    private let failureRecorder: (AuthenticationBridgeDiagnostic, String, Int) -> Void

    init(
        record: @escaping (AuthenticationBridgeDiagnostic) -> Void = { _ in },
        recordFailure: @escaping (AuthenticationBridgeDiagnostic, String, Int) -> Void = { _, _, _ in }
    ) {
        recorder = record
        failureRecorder = recordFailure
    }

    static let disabled = AuthenticationBridgeTelemetry()
    static let live: AuthenticationBridgeTelemetry = {
        let logger = Logger(
            subsystem: ProductIdentity.appLogSubsystem,
            category: "authentication"
        )
        return AuthenticationBridgeTelemetry(record: { event in
                logger.info("\(ProductIdentity.displayName) auth bridge event \(event.rawValue, privacy: .public)")
        }, recordFailure: { event, domain, code in
            logger.error("\(ProductIdentity.displayName) auth bridge event \(event.rawValue, privacy: .public) error-domain=\(domain, privacy: .public) error-code=\(code, privacy: .public)")
        })
    }()

    func record(_ event: AuthenticationBridgeDiagnostic) {
        recorder(event)
    }

    func recordFailure(_ event: AuthenticationBridgeDiagnostic, error: Error) {
        let error = error as NSError
        failureRecorder(event, error.domain, error.code)
    }

}

@MainActor
protocol WebAuthenticationCookieStore: AnyObject {
    func allCookies() async -> [HTTPCookie]
    func delete(_ cookie: HTTPCookie) async throws
}

/// Optional capability implemented by the live WebKit adapter and test stores
/// that can announce state changes without exposing any cookie material.
@MainActor
protocol WebAuthenticationCookieChangeObserving: AnyObject {
    func setChangeHandler(_ handler: (@MainActor @Sendable () -> Void)?)
}

@MainActor
final class WebAuthenticationBridge {
    enum Result: Equatable {
        case credentialTransferred
        case authCookieMissing
        case ambiguousCredentials
        case malformedCredential
        case cancelled
        case alreadyConsumed
    }

    var webViewConfiguration: WKWebViewConfiguration { websiteSession.configuration }
    var websiteSessionGeneration: Int { websiteSession.generation }

    private var cookieStore: any WebAuthenticationCookieStore
    private let now: @MainActor () -> Date
    private let credentialConsumer: @MainActor @Sendable (AuthenticationCredential) async -> Void
    private let handoffDisposer: @MainActor @Sendable () async -> Void
    private let handoff: VolatileWebCredentialHandoff
    private let websiteSession: WebAuthenticationWebsiteSession
    private let websiteSessionRetirer: @MainActor @Sendable () async -> Bool
    private let signInRequestLoader: @MainActor (URLRequest) -> Void
    private let browserSessionRefresher: @MainActor @Sendable (BrowserAuthenticationSessionSnapshot) async -> BrowserSessionRenewalDriverResult
    private let nativeSessionRefresher: (@MainActor @Sendable (AuthenticationCredential) async -> BrowserCredentialNativeRenewalResult)?
    private let telemetry: AuthenticationBridgeTelemetry
    private let usesLiveCookieStore: Bool
    private var selectionState: CredentialSelectionState = .available
    private var selectionGeneration = 0
    private var pendingSignInRequest: URLRequest?
    private var automaticCredentialReadyHandler: (@MainActor @Sendable () -> Void)?
    private var isAutomaticCaptureEnabled = false
    private var isAutomaticInspectionInFlight = false
    private var needsAnotherAutomaticInspection = false
    private var didNotifyAutomaticCredentialReady = false
    private var emittedAutomaticDiagnostics = Set<AuthenticationBridgeDiagnostic>()
    private var renewalDiagnosticHandler: @MainActor (AuthenticationRenewalAttemptDiagnostic) -> Void = { _ in }

    init() {
        let handoff = VolatileWebCredentialHandoff()
        let websiteSession = WebAuthenticationWebsiteSession()
        let renewalDriver = WebAuthenticationRenewalDriver()
        let nativeRenewalDriver = SiriusXMCurrentCredentialRenewalDriver()
        self.websiteSession = websiteSession
        cookieStore = WebKitAuthenticationCookieStore(cookieStore: websiteSession.configuration.websiteDataStore.httpCookieStore)
        now = Date.init
        self.handoff = handoff
        websiteSessionRetirer = { await websiteSession.removeAllWebsiteData() }
        signInRequestLoader = { request in websiteSession.makeWebView().load(request) }
        browserSessionRefresher = { snapshot in await renewalDriver.refresh(snapshot) }
        nativeSessionRefresher = { credential in await nativeRenewalDriver.refresh(credential) }
        usesLiveCookieStore = true
        telemetry = .live
        handoffDisposer = { await handoff.discard() }
        credentialConsumer = { credential in
            await handoff.store(credential)
        }
        websiteSession.installNavigationObserver(WebAuthenticationNavigationObserver(telemetry: telemetry))
        websiteSession.installPageStateObserver(
            WebAuthenticationPageStateObserver { [weak self] in
                self?.webPageStateDidChange()
            }
        )
        installCookieChangeObservation()
    }

    init(
        cookieStore: any WebAuthenticationCookieStore,
        now: @escaping @MainActor () -> Date = Date.init,
        credentialConsumer: @escaping @MainActor @Sendable (AuthenticationCredential) async -> Void,
        handoffDisposer: @escaping @MainActor @Sendable () async -> Void = {},
        websiteSessionRetirer: @escaping @MainActor @Sendable () async -> Bool = { true },
        telemetry: AuthenticationBridgeTelemetry = .disabled,
        signInRequestLoader: @escaping @MainActor (URLRequest) -> Void = { _ in },
        browserSessionRefresher: @escaping @MainActor @Sendable (BrowserAuthenticationSessionSnapshot) async -> BrowserSessionRenewalDriverResult = { _ in
            .failed(.configurationUnavailable)
        },
        nativeSessionRefresher: (@MainActor @Sendable (AuthenticationCredential) async -> BrowserCredentialNativeRenewalResult)? = nil
    ) {
        let handoff = VolatileWebCredentialHandoff()
        websiteSession = WebAuthenticationWebsiteSession()
        self.cookieStore = cookieStore
        self.now = now
        self.handoff = handoff
        self.websiteSessionRetirer = websiteSessionRetirer
        self.signInRequestLoader = signInRequestLoader
        self.browserSessionRefresher = browserSessionRefresher
        self.nativeSessionRefresher = nativeSessionRefresher
        self.telemetry = telemetry
        usesLiveCookieStore = false
        self.handoffDisposer = {
            await handoff.discard()
            await handoffDisposer()
        }
        self.credentialConsumer = { credential in
            await handoff.store(credential)
            await credentialConsumer(credential)
        }
        websiteSession.installNavigationObserver(WebAuthenticationNavigationObserver(telemetry: telemetry))
        websiteSession.installPageStateObserver(
            WebAuthenticationPageStateObserver { [weak self] in
                self?.webPageStateDidChange()
            }
        )
        installCookieChangeObservation()
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }

    func makeWebView() -> WKWebView {
        websiteSession.makeWebView()
    }

    /// Installs the app-lifetime presentation callback. The callback carries no
    /// credential material; it only reports that the allow-listed cookie shape
    /// is complete and ready for the existing single-consumption transaction.
    func setAutomaticCredentialReadyHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) {
        automaticCredentialReadyHandler = handler
    }

    func setRenewalDiagnosticHandler(
        _ handler: @escaping @MainActor (AuthenticationRenewalAttemptDiagnostic) -> Void
    ) {
        renewalDiagnosticHandler = handler
    }

    /// Starts the sole owner-operated authentication path without reading browser state.
    /// A new explicit attempt discards any volatile prior handoff before re-arming selection.
    func beginUserOperatedSignIn() async -> Bool {
        telemetry.record(.webSignInStarted)
        isAutomaticCaptureEnabled = false
        needsAnotherAutomaticInspection = false
        didNotifyAutomaticCredentialReady = false
        emittedAutomaticDiagnostics.removeAll(keepingCapacity: true)
        // Keep selection fail-closed while stale handoff and website state retire.
        let reservation = beginSelection()
        pendingSignInRequest = nil
        await handoffDisposer()
        guard await retireAuthenticationWebsiteSession() else {
            telemetry.record(.websiteSessionResetFailed)
            return false
        }
        completeUncommittedSelection(reservation)
        guard let url = URL(string: "https://www.siriusxm.com/player") else { return false }
        pendingSignInRequest = URLRequest(url: url)
        isAutomaticCaptureEnabled = true
        return true
    }

    /// Starts the queued request only after SwiftUI has installed this bridge's
    /// current WebView in the visible AppKit host. Repeated view updates cannot
    /// issue a second navigation.
    func loadPendingSignInRequestIfNeeded() {
        guard let request = pendingSignInRequest else { return }
        pendingSignInRequest = nil
        telemetry.record(.webNavigationRequested)
        signInRequestLoader(request)
    }

    /// Explicit fallback for checking the same allow-listed browser session that
    /// the post-consent cookie observer normally detects automatically.
    func useLoggedInSession() async -> Result {
        telemetry.record(.credentialSelectionStarted)
        guard selectionState == .available else {
            telemetry.record(.credentialAlreadyConsumed)
            return .alreadyConsumed
        }
        let reservation = beginSelection()
        defer { completeUncommittedSelection(reservation) }

        let cookies = await cookieStore.allCookies()
        guard !Task.isCancelled else {
            telemetry.record(.selectionCancelled)
            return .cancelled
        }
        switch WebCredentialSelectionPolicy.select(from: cookies, now: now()) {
        case let .missing(reasons):
            for reason in reasons {
                telemetry.record(reason.bridgeDiagnostic)
            }
            telemetry.record(.authCookieMissing)
            return .authCookieMissing
        case .ambiguous:
            telemetry.record(.ambiguousCredentials)
            return .ambiguousCredentials
        case let .malformed(reason):
            telemetry.record(reason.bridgeDiagnostic)
            telemetry.record(.malformedCredential)
            return .malformedCredential
        case let .credential(credential):
            guard !Task.isCancelled else {
                telemetry.record(.selectionCancelled)
                return .cancelled
            }

            selectionState = .consumed
            isAutomaticCaptureEnabled = false
            if let snapshot = credential.browserSessionSnapshot() {
                telemetry.record(snapshot.renewalDisposition.bridgeDiagnostic)
                telemetry.record(snapshot.deviceGrantDisposition.bridgeDiagnostic)
            }
            await credentialConsumer(credential)
            telemetry.record(.credentialTransferred)
            return .credentialTransferred
        }
    }

    private func beginSelection() -> Int {
        selectionGeneration &+= 1
        selectionState = .selecting
        return selectionGeneration
    }

    private func completeUncommittedSelection(_ reservation: Int) {
        guard selectionState == .selecting, selectionGeneration == reservation else { return }
        selectionState = .available
    }

    private func installCookieChangeObservation() {
        guard let observableStore = cookieStore as? any WebAuthenticationCookieChangeObserving else {
            return
        }
        observableStore.setChangeHandler { [weak self] in
            self?.cookieStoreDidChange()
        }
    }

    private func cookieStoreDidChange() {
        telemetry.record(.cookieStoreChangeObserved)
        startAutomaticCredentialInspectionIfNeeded()
    }

    /// Receives a material-free signal from the first-party page when its Cookie
    /// Store changes or an XHR/fetch completes. SiriusXM's SPA currently updates
    /// AUTH_TOKEN without a second WKHTTPCookieStoreObserver callback.
    func webPageStateDidChange() {
        telemetry.record(.webPageStateChangeObserved)
        startAutomaticCredentialInspectionIfNeeded()
    }

    private func startAutomaticCredentialInspectionIfNeeded() {
        guard isAutomaticCaptureEnabled,
              selectionState == .available,
              !didNotifyAutomaticCredentialReady else {
            return
        }
        if isAutomaticInspectionInFlight {
            needsAnotherAutomaticInspection = true
            return
        }
        isAutomaticInspectionInFlight = true
        telemetry.record(.automaticCredentialInspectionStarted)
        Task { @MainActor [weak self] in
            await self?.inspectCookiesForAutomaticCapture()
        }
    }

    private func inspectCookiesForAutomaticCapture() async {
        defer {
            isAutomaticInspectionInFlight = false
            if needsAnotherAutomaticInspection {
                needsAnotherAutomaticInspection = false
                startAutomaticCredentialInspectionIfNeeded()
            }
        }
        guard isAutomaticCaptureEnabled,
              selectionState == .available,
              !didNotifyAutomaticCredentialReady else {
            return
        }

        let cookies = await cookieStore.allCookies()
        guard isAutomaticCaptureEnabled,
              selectionState == .available,
              !didNotifyAutomaticCredentialReady else {
            return
        }

        switch WebCredentialSelectionPolicy.select(from: cookies, now: now()) {
        case let .missing(reasons):
            for reason in reasons {
                recordAutomaticDiagnosticOnce(reason.bridgeDiagnostic)
            }
            recordAutomaticDiagnosticOnce(.authCookieMissing)
        case .ambiguous:
            recordAutomaticDiagnosticOnce(.ambiguousCredentials)
        case let .malformed(reason):
            recordAutomaticDiagnosticOnce(reason.bridgeDiagnostic)
            recordAutomaticDiagnosticOnce(.malformedCredential)
        case let .credential(credential):
            if let snapshot = credential.browserSessionSnapshot() {
                recordAutomaticDiagnosticOnce(snapshot.renewalDisposition.bridgeDiagnostic)
                recordAutomaticDiagnosticOnce(snapshot.deviceGrantDisposition.bridgeDiagnostic)
            }
            didNotifyAutomaticCredentialReady = true
            telemetry.record(.automaticCredentialReady)
            automaticCredentialReadyHandler?()
        }
    }

    private func recordAutomaticDiagnosticOnce(_ diagnostic: AuthenticationBridgeDiagnostic) {
        guard emittedAutomaticDiagnostics.insert(diagnostic).inserted else { return }
        telemetry.record(diagnostic)
    }

    /// Retires the bridge-owned nonpersistent website session without inspecting its records.
    /// The only observable result is whether its bulk removal completed before rotation.
    func retireAuthenticationWebsiteSession() async -> Bool {
        isAutomaticCaptureEnabled = false
        needsAnotherAutomaticInspection = false
        (cookieStore as? any WebAuthenticationCookieChangeObserving)?.setChangeHandler(nil)
        websiteSession.stopLoading()
        guard await websiteSessionRetirer() else { return false }
        websiteSession.installFreshNonpersistentSession()
        if usesLiveCookieStore {
            cookieStore = WebKitAuthenticationCookieStore(
                cookieStore: websiteSession.configuration.websiteDataStore.httpCookieStore
            )
        }
        installCookieChangeObservation()
        return true
    }
}

private extension FirstPartyTokenCookiePolicy.RejectionReason {
    var bridgeDiagnostic: AuthenticationBridgeDiagnostic {
        switch self {
        case .nameAbsent: .authCookieNameAbsent
        case .issuerRejected: .authCookieIssuerRejected
        case .pathRejected: .authCookiePathRejected
        case .expired: .authCookieExpired
        }
    }
}

private extension AuthenticationCredentialMaterialError {
    var bridgeDiagnostic: AuthenticationBridgeDiagnostic {
        switch self {
        case .authenticationCookieTooLarge: .authenticationCookieTooLarge
        case .authenticationCookieUnreadable: .authenticationCookieUnreadable
        case .sessionObjectMissing: .sessionObjectMissing
        case .sessionObjectInvalid: .sessionObjectInvalid
        case .accessTokenMissing: .accessTokenMissing
        case .accessTokenInvalid: .accessTokenInvalid
        case .accessTokenExpiryMissing: .accessTokenExpiryMissing
        case .accessTokenExpiryInvalid: .accessTokenExpiryInvalid
        case .refreshTokenMissing: .refreshTokenMissing
        case .refreshTokenInvalid: .refreshTokenInvalid
        case .refreshTokenExpiryMissing: .refreshTokenExpiryMissing
        case .refreshTokenExpiryInvalid: .refreshTokenExpiryInvalid
        case .sessionRefreshCookieMissing: .sessionRefreshCookieMissing
        case .sessionRefreshCookieInvalid: .sessionRefreshCookieInvalid
        case .renewalAuthorityMissing: .renewalAuthorityMissing
        case .sessionTypeRejected: .sessionTypeRejected
        case .envelopeEncodingFailed: .credentialEnvelopeEncodingFailed
        case .envelopeTooLarge: .credentialEnvelopeTooLarge
        }
    }
}

private extension BrowserDeviceGrantDisposition {
    var bridgeDiagnostic: AuthenticationBridgeDiagnostic {
        switch self {
        case .absent: .deviceGrantAbsent
        case .accepted: .deviceGrantAccepted
        case .discardedUnrecognized: .deviceGrantDiscardedUnrecognized
        }
    }
}

private extension BrowserRenewalDisposition {
    var bridgeDiagnostic: AuthenticationBridgeDiagnostic {
        switch self {
        case .refreshToken: .renewalViaRefreshToken
        case .sessionRefreshCookie: .renewalViaSessionRefreshCookie
        }
    }

    var supportCredentialKind: AuthenticationRenewalCredentialKind {
        switch self {
        case .refreshToken: .refreshToken
        case .sessionRefreshCookie: .sessionRefreshCookie
        }
    }
}

extension AuthenticationCredential {
    var supportDiagnosticReference: String? {
        browserSessionSnapshot()?.diagnosticCredentialIdentifier.map {
            "credential:\($0.uuidString.lowercased())"
        }
    }
}

private extension BrowserSessionRenewalDriverFailure {
    var supportOutcome: AuthenticationRenewalOutcome {
        switch self {
        case .attemptAlreadyInProgress: .attemptAlreadyInProgress
        case .cookieRehydrationFailed: .cookieRehydrationFailed
        case .navigationFailed: .navigationFailed
        case .timedOutWaitingForCredential: .timedOutWaitingForCredential
        case .replacementCredentialMissing: .replacementCredentialMissing
        case .replacementCredentialAmbiguous: .replacementCredentialAmbiguous
        case .replacementCredentialMalformed: .replacementCredentialMalformed
        case .accessTokenUnchanged: .accessTokenUnchanged
        case .replacementRenewalExpired: .replacementRenewalExpired
        case .nativeRenewalAuthorityUnavailable: .nativeRenewalAuthorityUnavailable
        case .nativeRenewalAuthorityExpired: .nativeRenewalAuthorityExpired
        case .nativeTransportFailed: .nativeTransportFailed
        case .nativeAuthorizationRejected: .nativeAuthorizationRejected
        case .nativeRateLimited: .nativeRateLimited
        case .nativeServerUnavailable: .nativeServerUnavailable
        case .nativeRedirectRejected: .nativeRedirectRejected
        case .nativeResponseUnsupported: .nativeResponseUnsupported
        case .nativeReplacementUnusable: .nativeReplacementUnusable
        case .cancelled: .cancelled
        case .configurationUnavailable: .configurationUnavailable
        }
    }
}

private extension BrowserCredentialNativeRenewalFailure {
    var bridgeFailure: BrowserSessionRenewalDriverFailure {
        switch self {
        case .renewalAuthorityUnavailable: .nativeRenewalAuthorityUnavailable
        case .renewalAuthorityExpired: .nativeRenewalAuthorityExpired
        case .transportFailed: .nativeTransportFailed
        case .authorizationRejected: .nativeAuthorizationRejected
        case .rateLimited: .nativeRateLimited
        case .serverUnavailable: .nativeServerUnavailable
        case .redirectRejected: .nativeRedirectRejected
        case .unsupportedResponse: .nativeResponseUnsupported
        case .replacementUnusable: .nativeReplacementUnusable
        case .cancelled: .cancelled
        }
    }
}

extension WebAuthenticationBridge: CredentialSource {
    /// Provides the bridge's single-consumption handoff without exposing its material.
    func credential() async -> AuthenticationCredential? {
        await handoff.credential()
    }
}

extension WebAuthenticationBridge: CredentialRefresher {
    /// Uses the fixed current native renewal transaction when the short-lived
    /// access credential is approaching expiry.
    func refreshedCredential(ifNeeded credential: AuthenticationCredential) async -> AuthenticationCredential? {
        await refreshedCredential(credential, forceQualification: false)
    }

#if DEBUG
    /// Owner-initiated qualification bypasses only the ordinary expiry gate.
    /// Request construction, response validation, diagnostics, and rotation are
    /// identical to the automatic path, and there is no retry.
    func refreshedCredentialForQualification(_ credential: AuthenticationCredential) async -> AuthenticationCredential? {
        await refreshedCredential(credential, forceQualification: true)
    }
#endif

    private func refreshedCredential(
        _ credential: AuthenticationCredential,
        forceQualification: Bool
    ) async -> AuthenticationCredential? {
        guard let snapshot = credential.browserSessionSnapshot() else {
            return nil
        }

        let currentTime = now()
        guard forceQualification || snapshot.accessTokenExpiresAt <= currentTime.addingTimeInterval(300) else {
            return credential
        }

        let attemptID = UUID()
        let renewalCredential = snapshot.renewalDisposition.supportCredentialKind
        let renewalCredentialExpiresAt = switch snapshot.renewalDisposition {
        case .refreshToken:
            snapshot.refreshTokenExpiresAt
        case .sessionRefreshCookie:
            snapshot.refreshTokenExpiresAt
        }
        recordRenewalAttempt(
            id: attemptID,
            attemptedAt: currentTime,
            completedAt: nil,
            snapshot: snapshot,
            renewalCredential: renewalCredential,
            renewalCredentialExpiresAt: renewalCredentialExpiresAt,
            outcome: .inProgress,
            replacementCredentialReference: nil
        )

        guard snapshot.refreshTokenExpiresAt > currentTime else {
            telemetry.record(.browserSessionRefreshFailed)
            recordRenewalAttempt(
                id: attemptID,
                attemptedAt: currentTime,
                completedAt: now(),
                snapshot: snapshot,
                renewalCredential: renewalCredential,
                renewalCredentialExpiresAt: renewalCredentialExpiresAt,
                outcome: .renewalCredentialExpired,
                replacementCredentialReference: nil
            )
            return nil
        }
        telemetry.record(.browserSessionRefreshStarted)
        let result: BrowserSessionRenewalDriverResult
        if let nativeSessionRefresher {
            switch await nativeSessionRefresher(credential) {
            case let .refreshed(refreshed):
                result = .refreshed(refreshed)
            case let .failed(failure):
                result = .failed(failure.bridgeFailure)
            }
        } else if snapshot.renewalDisposition == .sessionRefreshCookie {
            result = .failed(.configurationUnavailable)
        } else {
            result = await browserSessionRefresher(snapshot)
        }
        guard case let .refreshed(refreshed) = result else {
            telemetry.record(.browserSessionRefreshFailed)
            if case let .failed(failure) = result {
                recordRenewalAttempt(
                    id: attemptID,
                    attemptedAt: currentTime,
                    completedAt: now(),
                    snapshot: snapshot,
                    renewalCredential: renewalCredential,
                    renewalCredentialExpiresAt: renewalCredentialExpiresAt,
                    outcome: failure.supportOutcome,
                    replacementCredentialReference: nil
                )
            }
            return nil
        }

        guard let refreshedSnapshot = refreshed.browserSessionSnapshot(),
              refreshedSnapshot.accessTokenExpiresAt > currentTime.addingTimeInterval(300) else {
            telemetry.record(.browserSessionRefreshFailed)
            recordRenewalAttempt(
                id: attemptID,
                attemptedAt: currentTime,
                completedAt: now(),
                snapshot: snapshot,
                renewalCredential: renewalCredential,
                renewalCredentialExpiresAt: renewalCredentialExpiresAt,
                outcome: .replacementCredentialUnusable,
                replacementCredentialReference: refreshed.supportDiagnosticReference
            )
            return nil
        }
        telemetry.record(.browserSessionRefreshCompleted)
        recordRenewalAttempt(
            id: attemptID,
            attemptedAt: currentTime,
            completedAt: now(),
            snapshot: snapshot,
            renewalCredential: renewalCredential,
            renewalCredentialExpiresAt: renewalCredentialExpiresAt,
            outcome: .replacementReceived,
            replacementCredentialReference: refreshedSnapshot.diagnosticCredentialIdentifier.map {
                "credential:\($0.uuidString.lowercased())"
            }
        )
        return refreshed
    }

    private func recordRenewalAttempt(
        id: UUID,
        attemptedAt: Date,
        completedAt: Date?,
        snapshot: BrowserAuthenticationSessionSnapshot,
        renewalCredential: AuthenticationRenewalCredentialKind,
        renewalCredentialExpiresAt: Date,
        outcome: AuthenticationRenewalOutcome,
        replacementCredentialReference: String?
    ) {
        renewalDiagnosticHandler(AuthenticationRenewalAttemptDiagnostic(
            id: id,
            attemptedAt: attemptedAt,
            completedAt: completedAt,
            sourceCredentialReference: snapshot.diagnosticCredentialIdentifier.map {
                "credential:\($0.uuidString.lowercased())"
            },
            renewalCredential: renewalCredential,
            accessTokenExpiresAt: snapshot.accessTokenExpiresAt,
            sessionRenewalExpiresAt: snapshot.refreshTokenExpiresAt,
            renewalCredentialExpiresAt: renewalCredentialExpiresAt,
            deviceGrantExpiresAt: snapshot.deviceGrantExpiresAt,
            outcome: outcome,
            replacementCredentialReference: replacementCredentialReference
        ))
    }
}

extension WebAuthenticationBridge: AuthenticationResidueCleaner {
    /// Deletes only cookies selected by the same predicates used for extraction,
    /// rescans that exact set, then retires the app-owned nonpersistent website session.
    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome {
        let currentTime = now()
        let initialCookies = await cookieStore.allCookies()
        let initialMatches = FirstPartyTokenCookiePolicy.matchingCookies(in: initialCookies, now: currentTime) +
            FirstPartyDeviceGrantCookiePolicy.matchingCookies(in: initialCookies, now: currentTime) +
            FirstPartySessionRefreshCookiePolicy.matchingCookies(in: initialCookies, now: currentTime)

        var deletionFailed = false
        for cookie in initialMatches {
            do {
                try await cookieStore.delete(cookie)
            } catch {
                deletionFailed = true
            }
        }

        let remainingCookies = await cookieStore.allCookies()
        let remainingMatches = FirstPartyTokenCookiePolicy.matchingCookies(in: remainingCookies, now: currentTime) +
            FirstPartyDeviceGrantCookiePolicy.matchingCookies(in: remainingCookies, now: currentTime) +
            FirstPartySessionRefreshCookiePolicy.matchingCookies(in: remainingCookies, now: currentTime)
        let didRetireWebsiteSession = await retireAuthenticationWebsiteSession()
        return !deletionFailed && remainingMatches.isEmpty && didRetireWebsiteSession ? .removed : .cleanupFailed
    }
}

@MainActor
private final class WebAuthenticationWebsiteSession {
    private(set) var configuration: WKWebViewConfiguration = WebAuthenticationBridge.makeConfiguration()
    private(set) var generation = 0
    private var webView: WKWebView?
    private var navigationObserver: WebAuthenticationNavigationObserver?
    private var pageStateObserver: WebAuthenticationPageStateObserver?

    func installNavigationObserver(_ observer: WebAuthenticationNavigationObserver) {
        navigationObserver = observer
        webView?.navigationDelegate = observer
    }

    func installPageStateObserver(_ observer: WebAuthenticationPageStateObserver) {
        configuration.userContentController.removeScriptMessageHandler(
            forName: WebAuthenticationPageStateObserver.messageName
        )
        pageStateObserver = observer
        installPageStateObservation(on: configuration, observer: observer)
    }

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationObserver
        self.webView = webView
        return webView
    }

    func stopLoading() {
        webView?.stopLoading()
    }

    func removeAllWebsiteData() async -> Bool {
        await configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
        return true
    }

    func installFreshNonpersistentSession() {
        configuration.userContentController.removeScriptMessageHandler(
            forName: WebAuthenticationPageStateObserver.messageName
        )
        webView = nil
        configuration = WebAuthenticationBridge.makeConfiguration()
        if let pageStateObserver {
            installPageStateObservation(on: configuration, observer: pageStateObserver)
        }
        generation &+= 1
    }

    private func installPageStateObservation(
        on configuration: WKWebViewConfiguration,
        observer: WebAuthenticationPageStateObserver
    ) {
        let controller = configuration.userContentController
        controller.add(observer, name: WebAuthenticationPageStateObserver.messageName)
        controller.addUserScript(WebAuthenticationPageStateObserver.userScript)
    }
}

@MainActor
private final class WebAuthenticationPageStateObserver: NSObject, WKScriptMessageHandler {
    static let messageName = "siriusMacSessionStateMayHaveChanged"
    static let userScript = WKUserScript(
        source: """
        (() => {
          const notifyNative = () => {
            try {
              globalThis.webkit?.messageHandlers?.siriusMacSessionStateMayHaveChanged?.postMessage(null);
            } catch (_) {}
          };

          try {
            globalThis.cookieStore?.addEventListener?.("change", notifyNative);
            if (typeof globalThis.PerformanceObserver === "function") {
              const observer = new PerformanceObserver((list) => {
                for (const entry of list.getEntries()) {
                  if (entry.initiatorType === "fetch" || entry.initiatorType === "xmlhttprequest") {
                    notifyNative();
                    return;
                  }
                }
              });
              observer.observe({ type: "resource", buffered: false });
            }
            globalThis.addEventListener("pageshow", notifyNative);
          } catch (_) {}
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    private let handler: @MainActor @Sendable () -> Void

    init(handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageName,
              let host = message.frameInfo.request.url?.host,
              FirstPartyTokenCookiePolicy.isFirstPartyHost(host) else {
            return
        }
        handler()
    }
}

@MainActor
private final class WebAuthenticationNavigationObserver: NSObject, WKNavigationDelegate {
    private let telemetry: AuthenticationBridgeTelemetry

    init(telemetry: AuthenticationBridgeTelemetry) {
        self.telemetry = telemetry
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        telemetry.record(.webNavigationStarted)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        telemetry.record(.webNavigationCommitted)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        telemetry.record(.webNavigationFinished)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        telemetry.recordFailure(.webNavigationProvisionalFailed, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        telemetry.recordFailure(.webNavigationFailed, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        telemetry.record(.webContentProcessTerminated)
    }
}

private enum CredentialSelectionState {
    case available
    case selecting
    case consumed
}

private actor VolatileWebCredentialHandoff: CredentialSource {
    private var storedCredential: AuthenticationCredential?

    func store(_ credential: AuthenticationCredential) {
        storedCredential = credential
    }

    func credential() -> AuthenticationCredential? {
        defer { storedCredential = nil }
        return storedCredential
    }

    func discard() {
        storedCredential = nil
    }
}

@MainActor
private final class WebAuthenticationRenewalDriver {
    private var activeAttempt: WebAuthenticationRenewalAttempt?

    func refresh(_ snapshot: BrowserAuthenticationSessionSnapshot) async -> BrowserSessionRenewalDriverResult {
        guard activeAttempt == nil else { return .failed(.attemptAlreadyInProgress) }
        let attempt = WebAuthenticationRenewalAttempt(snapshot: snapshot)
        activeAttempt = attempt
        defer { activeAttempt = nil }
        return await attempt.run()
    }
}

@MainActor
private final class WebAuthenticationRenewalAttempt: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    private let snapshot: BrowserAuthenticationSessionSnapshot
    private let configuration = WebAuthenticationBridge.makeConfiguration()
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<BrowserSessionRenewalDriverResult, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completed = false
    private var latestObservedFailure: BrowserSessionRenewalDriverFailure?

    init(snapshot: BrowserAuthenticationSessionSnapshot) {
        self.snapshot = snapshot
    }

    func run() async -> BrowserSessionRenewalDriverResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                Task { @MainActor [weak self] in
                    await self?.start()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failed(.cancelled)) }
        }
    }

    private func start() async {
        guard !completed else { return }
        guard let authenticationCookie = makeCookie(
                name: "AUTH_TOKEN",
                value: snapshot.authenticationCookieValue,
                expires: snapshot.refreshTokenExpiresAt
              ) else {
            finish(.failed(.cookieRehydrationFailed))
            return
        }
        guard let playerURL = URL(string: "https://www.siriusxm.com/player") else {
            finish(.failed(.configurationUnavailable))
            return
        }

        let cookieStore = configuration.websiteDataStore.httpCookieStore
        cookieStore.add(self)
        await cookieStore.setCookie(authenticationCookie)
        if let deviceGrantCookieValue = snapshot.deviceGrantCookieValue {
            guard let deviceGrantExpiresAt = snapshot.deviceRefreshGrantExpiresAt ?? snapshot.deviceGrantExpiresAt,
                  let deviceGrantCookie = makeCookie(
                      name: "DEVICE_GRANT",
                      value: deviceGrantCookieValue,
                      expires: deviceGrantExpiresAt
                  ) else {
                finish(.failed(.cookieRehydrationFailed))
                return
            }
            await cookieStore.setCookie(deviceGrantCookie)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = false
        webView.navigationDelegate = self
        self.webView = webView
        webView.load(URLRequest(url: playerURL))

        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.finish(.failed(self.latestObservedFailure ?? .timedOutWaitingForCredential))
        }
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            await self?.inspect(cookieStore)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            await self?.inspect(webView.configuration.websiteDataStore.httpCookieStore)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failed(.navigationFailed))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failed(.navigationFailed))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame == true else {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url,
              url.scheme == "https",
              let host = url.host?.lowercased(),
              host == "siriusxm.com" || host.hasSuffix(".siriusxm.com") else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func inspect(_ cookieStore: WKHTTPCookieStore) async {
        guard !completed else { return }
        let cookies = await cookieStore.allCookies()
        let currentTime = Date()
        switch WebCredentialSelectionPolicy.select(from: cookies, now: currentTime) {
        case .missing:
            latestObservedFailure = .replacementCredentialMissing
        case .ambiguous:
            latestObservedFailure = .replacementCredentialAmbiguous
        case .malformed:
            latestObservedFailure = .replacementCredentialMalformed
        case let .credential(credential):
            guard let refreshedSnapshot = credential.browserSessionSnapshot() else {
                latestObservedFailure = .replacementCredentialMalformed
                return
            }
            guard refreshedSnapshot.accessTokenExpiresAt > snapshot.accessTokenExpiresAt.addingTimeInterval(60) else {
                latestObservedFailure = .accessTokenUnchanged
                return
            }
            guard refreshedSnapshot.refreshTokenExpiresAt > currentTime else {
                latestObservedFailure = .replacementRenewalExpired
                return
            }
            finish(.refreshed(credential))
        }
    }

    private func finish(_ result: BrowserSessionRenewalDriverResult) {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        timeoutTask = nil
        configuration.websiteDataStore.httpCookieStore.remove(self)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func makeCookie(name: String, value: String, expires: Date) -> HTTPCookie? {
        HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: ".siriusxm.com",
            .path: "/",
            .expires: expires,
            .secure: "TRUE",
        ])
    }
}

@MainActor
private final class WebKitAuthenticationCookieStore: WebAuthenticationCookieStore, WebAuthenticationCookieChangeObserving {
    private let cookieStore: WKHTTPCookieStore
    private var changeObserver: WebKitAuthenticationCookieChangeObserver?

    init(cookieStore: WKHTTPCookieStore) {
        self.cookieStore = cookieStore
    }

    func allCookies() async -> [HTTPCookie] {
        await cookieStore.allCookies()
    }

    func delete(_ cookie: HTTPCookie) async throws {
        await withCheckedContinuation { continuation in
            cookieStore.delete(cookie) { continuation.resume() }
        }
    }

    func setChangeHandler(_ handler: (@MainActor @Sendable () -> Void)?) {
        if let changeObserver {
            cookieStore.remove(changeObserver)
            self.changeObserver = nil
        }
        guard let handler else { return }
        let observer = WebKitAuthenticationCookieChangeObserver(handler: handler)
        changeObserver = observer
        cookieStore.add(observer)
    }
}

@MainActor
private final class WebKitAuthenticationCookieChangeObserver: NSObject, WKHTTPCookieStoreObserver {
    private let handler: @MainActor @Sendable () -> Void

    init(handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [handler] in handler() }
    }
}
