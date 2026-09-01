import AppKit
import Foundation
import Observation
import OSLog
import SiriusXMClient
import SwiftUI

enum CompatibilityArea: String, CaseIterable, Codable, Equatable {
    case authentication
    case entitlement
    case catalog
    case stream
    case metadata
    case playback

    var title: String { rawValue.capitalized }
}

enum CompatibilityClassification: String, Codable, Equatable {
    case available
    case checking
    case degraded
    case unavailable
    case notChecked = "not_checked"

    var title: String {
        switch self {
        case .available: "Available"
        case .checking: "Checking"
        case .degraded: "Degraded"
        case .unavailable: "Unavailable"
        case .notChecked: "Not checked"
        }
    }

    var symbolName: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .checking: "clock.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.octagon.fill"
        case .notChecked: "minus.circle.fill"
        }
    }
}

struct CompatibilityFinding: Codable, Equatable, Identifiable {
    let area: CompatibilityArea
    let classification: CompatibilityClassification

    var id: CompatibilityArea { area }

    var explanation: String {
        switch (area, classification) {
        case (.authentication, .available): "The current sign-in is accepted."
        case (.authentication, .checking): "The current sign-in is being verified."
        case (.authentication, .unavailable): "The sign-in could not be used. Sign in again before checking later stages."
        case (.entitlement, .available): "The account is entitled to listening."
        case (.entitlement, .checking): "The subscription entitlement is being verified."
        case (.entitlement, .unavailable): "The account is not currently entitled to listening."
        case (.catalog, .available): "The channel catalog is available."
        case (.catalog, .checking): "The channel catalog is loading."
        case (.catalog, .degraded): "A saved catalog is available, but its latest refresh failed."
        case (.catalog, .unavailable): "The channel catalog could not be loaded."
        case (.stream, .available): "The current channel produced an authorized media handoff."
        case (.stream, .checking): "The current channel stream is being resolved."
        case (.stream, .unavailable): "The current channel could not produce an authorized media handoff."
        case (.metadata, .available): "Current program metadata is available."
        case (.metadata, .checking): "Current program metadata is loading."
        case (.metadata, .degraded): "The last program metadata is retained, but its refresh failed."
        case (.metadata, .unavailable): "Current program metadata is unavailable."
        case (.playback, .available): "Native playback is ready."
        case (.playback, .checking): "Native playback is starting."
        case (.playback, .unavailable): "Native playback could not continue."
        case (_, .notChecked): "This stage has not run in the current session."
        case (_, .degraded): "This stage is using retained information after a recoverable failure."
        case (_, .checking): "This stage is in progress."
        case (_, .available): "This stage is available."
        case (_, .unavailable): "This stage is unavailable."
        }
    }
}

enum SupportDiagnosticSeverity: String, Codable, Equatable {
    case warning
    case error
}

enum StoredCredentialLoadPurpose: String, Codable, Equatable {
    case automaticRestore = "automatic-restore"
    case explicitSignIn = "explicit-sign-in"
}

enum StoredCredentialLoadOutcome: String, Codable, Equatable {
    case ready
    case missing
    case invalid
    case keychainUnavailable = "keychain-unavailable"
    case quarantined
}

struct StoredCredentialLoadDiagnostic: Codable, Equatable {
    let recordedAt: Date
    let purpose: StoredCredentialLoadPurpose
    let outcome: StoredCredentialLoadOutcome
    let credentialReference: String?
}

enum AuthenticationRenewalCredentialKind: String, Codable, Equatable {
    case refreshToken = "refresh-token"
    case sessionRefreshCookie = "session-refresh-cookie"
    // Retained so reports produced by the short-lived identity-grant prototype
    // remain decodable; current builds never select this credential kind.
    case identityGrant = "identity-grant"
    // Retained so schema-3 reports written by earlier builds remain decodable.
    case deviceRefreshGrant = "device-refresh-grant"
}

/// Closed, provider-material-free outcomes for the isolated browser renewal.
/// These values intentionally contain no response text, URLs, cookies, or tokens.
enum AuthenticationRenewalOutcome: String, Codable, Equatable {
    case inProgress = "in-progress"
    case replacementReceived = "replacement-received"
    case renewalCredentialExpired = "renewal-credential-expired"
    case deviceRefreshGrantExpired = "device-refresh-grant-expired"
    case attemptAlreadyInProgress = "attempt-already-in-progress"
    case cookieRehydrationFailed = "cookie-rehydration-failed"
    case navigationFailed = "navigation-failed"
    case timedOutWaitingForCredential = "timed-out-waiting-for-credential"
    case replacementCredentialMissing = "replacement-credential-missing"
    case replacementCredentialAmbiguous = "replacement-credential-ambiguous"
    case replacementCredentialMalformed = "replacement-credential-malformed"
    case accessTokenUnchanged = "access-token-unchanged"
    case replacementRenewalExpired = "replacement-renewal-expired"
    case replacementCredentialUnusable = "replacement-credential-unusable"
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

struct AuthenticationRenewalAttemptDiagnostic: Codable, Equatable, Identifiable {
    let id: UUID
    let attemptedAt: Date
    let completedAt: Date?
    let sourceCredentialReference: String?
    let renewalCredential: AuthenticationRenewalCredentialKind
    let accessTokenExpiresAt: Date
    let sessionRenewalExpiresAt: Date
    let renewalCredentialExpiresAt: Date
    let deviceGrantExpiresAt: Date?
    let outcome: AuthenticationRenewalOutcome
    let replacementCredentialReference: String?
}

struct AuthenticationStateDiagnostic: Codable, Equatable {
    let recordedAt: Date
    let state: String
}

struct NativeAuthenticationAttemptDiagnostic: Codable, Equatable {
    let recordedAt: Date
    let outcome: AuthenticationDiagnosticOutcome
}

struct AuthenticationSupportSnapshot: Codable, Equatable {
    let currentState: AuthenticationStateDiagnostic
    let lastSuccessfulAuthenticationAt: Date?
    let lastStoredCredentialLoad: StoredCredentialLoadDiagnostic?
    let lastRenewalAttempt: AuthenticationRenewalAttemptDiagnostic?
    let lastNativeAuthenticationAttempt: NativeAuthenticationAttemptDiagnostic?

    static let unknown = AuthenticationSupportSnapshot(
        currentState: AuthenticationStateDiagnostic(recordedAt: .distantPast, state: "unknown"),
        lastSuccessfulAuthenticationAt: nil,
        lastStoredCredentialLoad: nil,
        lastRenewalAttempt: nil,
        lastNativeAuthenticationAttempt: nil
    )
}

/// Fixed, reviewed diagnostic codes that are safe to persist and export. The
/// journal has no API for provider text, response bodies, URLs, headers,
/// credentials, account values, channel identities, or arbitrary errors.
enum SupportDiagnosticCode: String, Codable, Equatable {
    case authenticationStoredSessionUnavailable = "authentication.stored-session-unavailable"
    case authenticationStoredSessionInvalid = "authentication.stored-session-invalid"
    case authenticationRejected = "authentication.rejected"
    case authenticationChallengeRequired = "authentication.challenge-required"
    case authenticationUnsupportedResponse = "authentication.unsupported-response"
    case authenticationWebSessionResetFailed = "authentication.web-session-reset-failed"
    case authenticationCredentialPersistenceFailed = "authentication.credential-persistence-failed"
    case authenticationCleanupFailed = "authentication.cleanup-failed"
    case entitlementUnavailable = "entitlement.unavailable"
    case catalogAuthenticationUnavailable = "catalog.authentication-unavailable"
    case catalogNotEntitled = "catalog.not-entitled"
    case catalogPartialLineup = "catalog.partial-lineup"
    case catalogPaginationIncomplete = "catalog.pagination-incomplete"
    case catalogCollectionMissing = "catalog.collection-missing"
    case catalogMalformedChannel = "catalog.malformed-channel"
    case catalogConflictingIdentity = "catalog.conflicting-identity"
    case catalogUnsupportedResponse = "catalog.unsupported-response"
    case catalogUnavailable = "catalog.unavailable"
    case streamAuthorizationUnavailable = "stream.authorization-unavailable"
    case streamEntitlementUnavailable = "stream.entitlement-unavailable"
    case streamCatalogUnavailable = "stream.catalog-unavailable"
    case streamSelectionUnavailable = "stream.selection-unavailable"
    case streamResolutionUnavailable = "stream.resolution-unavailable"
    case streamProtectedControl = "stream.protected-control"
    case playbackNetworkUnavailable = "playback.network-unavailable"
    case playbackBufferingUnavailable = "playback.buffering-unavailable"
    case playbackDecoderUnavailable = "playback.decoder-unavailable"
    case playbackRecoveryExhausted = "playback.recovery-exhausted"
    case playbackUnsupported = "playback.unsupported"
    case metadataRefreshFailed = "metadata.refresh-failed"
    case metadataUnavailable = "metadata.unavailable"

    var area: CompatibilityArea {
        switch self {
        case .authenticationStoredSessionUnavailable, .authenticationStoredSessionInvalid,
             .authenticationRejected, .authenticationChallengeRequired,
             .authenticationUnsupportedResponse, .authenticationWebSessionResetFailed,
             .authenticationCredentialPersistenceFailed, .authenticationCleanupFailed:
            .authentication
        case .entitlementUnavailable:
            .entitlement
        case .catalogAuthenticationUnavailable, .catalogNotEntitled, .catalogPartialLineup,
             .catalogPaginationIncomplete,
             .catalogCollectionMissing,
             .catalogMalformedChannel, .catalogConflictingIdentity, .catalogUnsupportedResponse,
             .catalogUnavailable:
            .catalog
        case .streamAuthorizationUnavailable, .streamEntitlementUnavailable,
             .streamCatalogUnavailable, .streamSelectionUnavailable,
             .streamResolutionUnavailable, .streamProtectedControl:
            .stream
        case .playbackNetworkUnavailable, .playbackBufferingUnavailable,
             .playbackDecoderUnavailable, .playbackRecoveryExhausted, .playbackUnsupported:
            .playback
        case .metadataRefreshFailed, .metadataUnavailable:
            .metadata
        }
    }

    var severity: SupportDiagnosticSeverity {
        switch self {
        case .metadataRefreshFailed, .metadataUnavailable, .playbackNetworkUnavailable,
             .playbackBufferingUnavailable, .catalogUnavailable:
            .warning
        default:
            .error
        }
    }

    var summary: String {
        switch self {
        case .authenticationStoredSessionUnavailable: "The saved sign-in expired or could not be refreshed."
        case .authenticationStoredSessionInvalid: "The saved sign-in data was no longer usable."
        case .authenticationRejected: "SiriusXM rejected the sign-in."
        case .authenticationChallengeRequired: "SiriusXM required an interactive account challenge."
        case .authenticationUnsupportedResponse: "SiriusXM returned an authentication response this app does not recognize."
        case .authenticationWebSessionResetFailed: "The private sign-in session could not be reset."
        case .authenticationCredentialPersistenceFailed: "The verified sign-in could not be saved securely."
        case .authenticationCleanupFailed: "The local sign-out cleanup did not finish."
        case .entitlementUnavailable: "The account’s listening entitlement could not be confirmed."
        case .catalogAuthenticationUnavailable: "The channel lineup request no longer had a usable sign-in."
        case .catalogNotEntitled: "The channel lineup request did not have confirmed listening entitlement."
        case .catalogPartialLineup: "SiriusXM returned a curated subset instead of the complete channel lineup."
        case .catalogPaginationIncomplete: "SiriusXM's paginated channel lineup stopped before every channel was received."
        case .catalogCollectionMissing: "SiriusXM responded without a supported channel collection."
        case .catalogMalformedChannel: "SiriusXM returned a channel record this app could not safely interpret."
        case .catalogConflictingIdentity: "SiriusXM returned conflicting channel identities."
        case .catalogUnsupportedResponse: "SiriusXM returned a catalog response this app does not recognize."
        case .catalogUnavailable: "The channel lineup service was unavailable."
        case .streamAuthorizationUnavailable: "The channel stream request no longer had a usable sign-in."
        case .streamEntitlementUnavailable: "The channel stream request did not have confirmed listening entitlement."
        case .streamCatalogUnavailable: "Playback could not use the current channel lineup."
        case .streamSelectionUnavailable: "Playback did not have a valid channel selection."
        case .streamResolutionUnavailable: "SiriusXM did not produce a supported stream handoff."
        case .streamProtectedControl: "SiriusXM required a protected or interactive control."
        case .playbackNetworkUnavailable: "Playback lost its network connection."
        case .playbackBufferingUnavailable: "Playback could not recover from buffering."
        case .playbackDecoderUnavailable: "macOS could not decode the resolved stream."
        case .playbackRecoveryExhausted: "Playback still failed after its bounded recovery attempt."
        case .playbackUnsupported: "This version cannot play the resolved stream contract."
        case .metadataRefreshFailed: "Current program information could not be refreshed."
        case .metadataUnavailable: "Current program information was unavailable."
        }
    }

    var suggestedAction: String {
        switch self {
        case .authenticationStoredSessionUnavailable, .authenticationStoredSessionInvalid,
             .authenticationRejected:
            "Sign in again. Maintainers should inspect session renewal if this repeats."
        case .authenticationChallengeRequired:
            "Complete the challenge in the SiriusXM sign-in view; the app will not bypass it."
        case .authenticationUnsupportedResponse:
            "Maintainers should compare the authentication adapter with the current response contract."
        case .authenticationWebSessionResetFailed:
            "Quit and reopen the app, then try signing in again."
        case .authenticationCredentialPersistenceFailed:
            "Check Keychain access and include this report with a bug."
        case .authenticationCleanupFailed:
            "Quit the app before retrying sign-out or clearing the local session."
        case .entitlementUnavailable, .catalogNotEntitled, .streamEntitlementUnavailable:
            "Confirm the SiriusXM subscription in the official service, then sign in again."
        case .catalogAuthenticationUnavailable, .streamAuthorizationUnavailable:
            "Sign in again. Maintainers should inspect persisted-session renewal if this repeats."
        case .catalogPartialLineup, .catalogPaginationIncomplete, .catalogCollectionMissing, .catalogMalformedChannel, .catalogConflictingIdentity,
             .catalogUnsupportedResponse:
            "Refresh once. If it repeats, submit this report so maintainers can update the catalog adapter."
        case .catalogUnavailable, .playbackNetworkUnavailable, .playbackBufferingUnavailable,
             .metadataRefreshFailed, .metadataUnavailable:
            "Check the connection and retry once. Submit this report if the problem continues."
        case .streamCatalogUnavailable:
            "Refresh the channel lineup before trying playback again."
        case .streamSelectionUnavailable:
            "Select a channel from the current lineup and try again."
        case .streamResolutionUnavailable, .playbackDecoderUnavailable,
             .playbackRecoveryExhausted, .playbackUnsupported:
            "Retry once. If it repeats, submit this report so maintainers can inspect playback compatibility."
        case .streamProtectedControl:
            "Use the official SiriusXM experience to complete any required account control; the app will not bypass it."
        }
    }
}

struct SupportDiagnosticEntry: Codable, Equatable, Identifiable {
    let recordedAt: Date
    let code: SupportDiagnosticCode

    var id: String { "\(recordedAt.timeIntervalSinceReferenceDate)-\(code.rawValue)" }
    var area: CompatibilityArea { code.area }
    var severity: SupportDiagnosticSeverity { code.severity }
    var summary: String { code.summary }
    var suggestedAction: String { code.suggestedAction }

    private enum CodingKeys: String, CodingKey {
        case recordedAt
        case area
        case severity
        case code
        case summary
        case suggestedAction
    }

    init(recordedAt: Date, code: SupportDiagnosticCode) {
        self.recordedAt = recordedAt
        self.code = code
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        code = try values.decode(SupportDiagnosticCode.self, forKey: .code)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(recordedAt, forKey: .recordedAt)
        try values.encode(area, forKey: .area)
        try values.encode(severity, forKey: .severity)
        try values.encode(code, forKey: .code)
        try values.encode(summary, forKey: .summary)
        try values.encode(suggestedAction, forKey: .suggestedAction)
    }
}

@MainActor
@Observable
final class SupportDiagnosticJournal {
    static let maximumEntries = 40
    private static let storageKey = "support-diagnostics-v1"
    private static let authenticationStorageKey = "authentication-support-v1"
    private static let logger = Logger(subsystem: ProductIdentity.appLogSubsystem, category: "Support")

    private struct PersistedAuthenticationSupport: Codable {
        let currentState: AuthenticationStateDiagnostic
        let lastSuccessfulAuthenticationAt: Date?
        let lastStoredCredentialLoad: StoredCredentialLoadDiagnostic?
        let lastRenewalAttempt: AuthenticationRenewalAttemptDiagnostic?
        let lastNativeAuthenticationAttempt: NativeAuthenticationAttemptDiagnostic?
    }

    private let userDefaults: UserDefaults?
    private(set) var entries: [SupportDiagnosticEntry]
    private(set) var authenticationSupport: AuthenticationSupportSnapshot

    init(
        entries: [SupportDiagnosticEntry] = [],
        authenticationSupport: AuthenticationSupportSnapshot = .unknown,
        userDefaults: UserDefaults? = nil
    ) {
        self.userDefaults = userDefaults
        if let data = userDefaults?.data(forKey: Self.storageKey),
           let restored = try? Self.decoder.decode([SupportDiagnosticEntry].self, from: data) {
            self.entries = Array(restored.suffix(Self.maximumEntries))
        } else {
            self.entries = Array(entries.suffix(Self.maximumEntries))
        }
        if let data = userDefaults?.data(forKey: Self.authenticationStorageKey),
           let restored = try? Self.decoder.decode(PersistedAuthenticationSupport.self, from: data) {
            self.authenticationSupport = AuthenticationSupportSnapshot(
                currentState: restored.currentState,
                lastSuccessfulAuthenticationAt: restored.lastSuccessfulAuthenticationAt,
                lastStoredCredentialLoad: restored.lastStoredCredentialLoad,
                lastRenewalAttempt: restored.lastRenewalAttempt,
                lastNativeAuthenticationAttempt: restored.lastNativeAuthenticationAttempt
            )
        } else {
            self.authenticationSupport = authenticationSupport
        }
    }

    static func persistent(userDefaults: UserDefaults = .standard) -> SupportDiagnosticJournal {
        SupportDiagnosticJournal(userDefaults: userDefaults)
    }

    func record(_ code: SupportDiagnosticCode, at date: Date = Date()) {
        if let latest = entries.last,
           latest.code == code,
           date.timeIntervalSince(latest.recordedAt) < 60 {
            return
        }
        entries.append(SupportDiagnosticEntry(recordedAt: date, code: code))
        entries = Array(entries.suffix(Self.maximumEntries))
        persist()
        Self.logger.error("Support diagnostic \(code.rawValue, privacy: .public)")
    }

    func recordAuthenticationState(_ state: String, successful: Bool, at date: Date = Date()) {
        authenticationSupport = AuthenticationSupportSnapshot(
            currentState: AuthenticationStateDiagnostic(recordedAt: date, state: state),
            lastSuccessfulAuthenticationAt: successful ? date : authenticationSupport.lastSuccessfulAuthenticationAt,
            lastStoredCredentialLoad: authenticationSupport.lastStoredCredentialLoad,
            lastRenewalAttempt: authenticationSupport.lastRenewalAttempt,
            lastNativeAuthenticationAttempt: authenticationSupport.lastNativeAuthenticationAttempt
        )
        persistAuthenticationSupport()
    }

    func recordStoredCredentialLoad(_ diagnostic: StoredCredentialLoadDiagnostic) {
        authenticationSupport = AuthenticationSupportSnapshot(
            currentState: authenticationSupport.currentState,
            lastSuccessfulAuthenticationAt: authenticationSupport.lastSuccessfulAuthenticationAt,
            lastStoredCredentialLoad: diagnostic,
            lastRenewalAttempt: authenticationSupport.lastRenewalAttempt,
            lastNativeAuthenticationAttempt: authenticationSupport.lastNativeAuthenticationAttempt
        )
        persistAuthenticationSupport()
        Self.logger.notice(
            "Stored authentication credential load purpose=\(diagnostic.purpose.rawValue, privacy: .public) outcome=\(diagnostic.outcome.rawValue, privacy: .public)"
        )
    }

    func recordRenewalAttempt(_ diagnostic: AuthenticationRenewalAttemptDiagnostic) {
        authenticationSupport = AuthenticationSupportSnapshot(
            currentState: authenticationSupport.currentState,
            lastSuccessfulAuthenticationAt: authenticationSupport.lastSuccessfulAuthenticationAt,
            lastStoredCredentialLoad: authenticationSupport.lastStoredCredentialLoad,
            lastRenewalAttempt: diagnostic,
            lastNativeAuthenticationAttempt: authenticationSupport.lastNativeAuthenticationAttempt
        )
        persistAuthenticationSupport()
        Self.logger.notice(
            "Authentication renewal mechanism=\(diagnostic.renewalCredential.rawValue, privacy: .public) outcome=\(diagnostic.outcome.rawValue, privacy: .public)"
        )
    }

    func recordNativeAuthenticationAttempt(_ diagnostic: NativeAuthenticationAttemptDiagnostic) {
        authenticationSupport = AuthenticationSupportSnapshot(
            currentState: authenticationSupport.currentState,
            lastSuccessfulAuthenticationAt: authenticationSupport.lastSuccessfulAuthenticationAt,
            lastStoredCredentialLoad: authenticationSupport.lastStoredCredentialLoad,
            lastRenewalAttempt: authenticationSupport.lastRenewalAttempt,
            lastNativeAuthenticationAttempt: diagnostic
        )
        persistAuthenticationSupport()
        Self.logger.notice(
            "Native authentication outcome=\(diagnostic.outcome.rawValue, privacy: .public)"
        )
    }

    func clear() {
        entries = []
        authenticationSupport = .unknown
        userDefaults?.removeObject(forKey: Self.storageKey)
        userDefaults?.removeObject(forKey: Self.authenticationStorageKey)
    }

    private func persist() {
        guard let userDefaults, let data = try? Self.encoder.encode(entries) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    private func persistAuthenticationSupport() {
        guard let userDefaults else { return }
        let persisted = PersistedAuthenticationSupport(
            currentState: authenticationSupport.currentState,
            lastSuccessfulAuthenticationAt: authenticationSupport.lastSuccessfulAuthenticationAt,
            lastStoredCredentialLoad: authenticationSupport.lastStoredCredentialLoad,
            lastRenewalAttempt: authenticationSupport.lastRenewalAttempt,
            lastNativeAuthenticationAttempt: authenticationSupport.lastNativeAuthenticationAttempt
        )
        guard let data = try? Self.encoder.encode(persisted) else { return }
        userDefaults.set(data, forKey: Self.authenticationStorageKey)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct SupportBundle: Codable, Equatable {
    static let schemaVersion = 3

    let schemaVersion: Int
    let product: String
    let version: String
    let build: String
    let operatingSystem: String
    let architecture: String
    let authentication: AuthenticationSupportSnapshot
    let compatibility: [CompatibilityFinding]
    let diagnostics: [SupportDiagnosticEntry]
}

struct CompatibilitySnapshot: Equatable {
    let findings: [CompatibilityFinding]

    static func make(
        authentication: AuthenticationPresentationState,
        catalog: ListeningPresentationState,
        playback: LivePlaybackState,
        metadata: MetadataPresentationAvailability
    ) -> Self {
        let authenticationStatus: CompatibilityClassification
        let entitlementStatus: CompatibilityClassification

        switch authentication {
        case .entitled, .restoreCompleted:
            authenticationStatus = .available
            entitlementStatus = .available
        case .verifyingAuthentication:
            authenticationStatus = .checking
            entitlementStatus = .notChecked
        case .verifyingEntitlement:
            authenticationStatus = .available
            entitlementStatus = .checking
        case .authenticatedButNotEntitled, .entitlementAuthorizationRejected:
            authenticationStatus = .available
            entitlementStatus = .unavailable
        case .profileAuthorizationRejected, .credentialNotDurable, .rejected, .challengeRequired,
             .unsupported, .localCredentialInvalid, .localCredentialUnavailable,
             .webCredentialMalformed, .webCredentialAmbiguous, .webSessionResetFailed,
             .cleanupFailed:
            authenticationStatus = .unavailable
            entitlementStatus = .notChecked
        case .localCredentialMissing, .waitingForWebView, .webCredentialMissing, .signedOut,
             .finishingCleanup:
            authenticationStatus = .notChecked
            entitlementStatus = .notChecked
        }

        let catalogStatus: CompatibilityClassification = switch catalog {
        case .idle: .notChecked
        case .loading: .checking
        case .available, .empty: .available
        case .stale: .degraded
        case .failed: .unavailable
        }

        let streamStatus: CompatibilityClassification
        let playbackStatus: CompatibilityClassification
        switch playback {
        case .awaitingLiveContract:
            streamStatus = .checking
            playbackStatus = .notChecked
        case .playing, .paused:
            streamStatus = .available
            playbackStatus = .available
        case .idle, .stopped:
            streamStatus = .notChecked
            playbackStatus = .notChecked
        case let .unavailable(failure):
            switch failure {
            case .authorizationUnavailable, .entitlementUnavailable, .catalogUnavailable,
                 .selectionUnavailable, .resolutionUnavailable, .protectedControl, .unsupported:
                streamStatus = .unavailable
                playbackStatus = .notChecked
            case .networkUnavailable, .bufferingUnavailable, .decoderUnavailable, .recoveryExhausted:
                streamStatus = .available
                playbackStatus = .unavailable
            case .cancelled, .superseded:
                streamStatus = .notChecked
                playbackStatus = .notChecked
            }
        }

        let metadataStatus: CompatibilityClassification = switch metadata {
        case .loading: .checking
        case .current: .available
        case .failed: .degraded
        case .unavailable: .unavailable
        }

        return Self(findings: [
            .init(area: .authentication, classification: authenticationStatus),
            .init(area: .entitlement, classification: entitlementStatus),
            .init(area: .catalog, classification: catalogStatus),
            .init(area: .stream, classification: streamStatus),
            .init(area: .metadata, classification: metadataStatus),
            .init(area: .playback, classification: playbackStatus),
        ])
    }

    static let signedOut = make(
        authentication: .signedOut,
        catalog: .idle,
        playback: .idle,
        metadata: .unavailable
    )
}

enum SupportBundleFactory {
    static func make(
        snapshot: CompatibilitySnapshot,
        authentication: AuthenticationSupportSnapshot = .unknown,
        diagnostics: [SupportDiagnosticEntry] = [],
        bundle: Bundle = .main
    ) -> SupportBundle {
        SupportBundle(
            schemaVersion: SupportBundle.schemaVersion,
            product: ProductIdentity.displayName,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Development",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            authentication: authentication,
            compatibility: snapshot.findings,
            diagnostics: diagnostics
        )
    }

    static func encoded(_ bundle: SupportBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    private static var architecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}

@MainActor
struct CompatibilitySupportView: View {
    let controller: ListeningSessionController?
    @State private var exportError: String?
#if DEBUG
    @State private var isShowingRenewalQualificationConfirmation = false
#endif

    private var snapshot: CompatibilitySnapshot {
        guard let controller else { return .signedOut }
        return .make(
            authentication: controller.authenticationModel.state,
            catalog: controller.listeningModel.state,
            playback: controller.listeningModel.playbackState,
            metadata: controller.listeningModel.metadataPresentation.availability
        )
    }

    private var supportBundle: SupportBundle {
        SupportBundleFactory.make(
            snapshot: snapshot,
            authentication: controller?.supportDiagnostics.authenticationSupport ?? .unknown,
            diagnostics: controller?.supportDiagnostics.entries ?? []
        )
    }

    private var preview: String {
        guard let data = try? SupportBundleFactory.encoded(supportBundle) else { return "Unable to create preview." }
        return String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Compatibility & Support")
                    .font(.title2.bold())
                Text("These checks show where the current session stopped. No new SiriusXM requests are made here.")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                ForEach(snapshot.findings) { finding in
                    GridRow {
                        Label(finding.area.title, systemImage: finding.classification.symbolName)
                            .frame(width: 150, alignment: .leading)
                        Text(finding.classification.title)
                            .fontWeight(.semibold)
                            .frame(width: 100, alignment: .leading)
                        Text(finding.explanation)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            GroupBox("Authentication details") {
                VStack(alignment: .leading, spacing: 8) {
                    authenticationDetail(
                        "Current state",
                        supportBundle.authentication.currentState.state,
                        date: supportBundle.authentication.currentState.recordedAt
                    )
                    if let successfulAt = supportBundle.authentication.lastSuccessfulAuthenticationAt {
                        authenticationDetail("Last successful verification", "succeeded", date: successfulAt)
                    }
                    if let load = supportBundle.authentication.lastStoredCredentialLoad {
                        authenticationDetail(
                            "Last stored credential load",
                            "\(load.purpose.rawValue): \(load.outcome.rawValue)" + referenceSuffix(load.credentialReference),
                            date: load.recordedAt
                        )
                    }
                    if let nativeAttempt = supportBundle.authentication.lastNativeAuthenticationAttempt {
                        authenticationDetail(
                            "Last native authentication",
                            nativeAttempt.outcome.rawValue,
                            date: nativeAttempt.recordedAt
                        )
                    }
                    if let renewal = supportBundle.authentication.lastRenewalAttempt {
                        authenticationDetail(
                            "Last token renewal",
                            renewal.outcome.rawValue,
                            date: renewal.attemptedAt
                        )
                        authenticationDetail(
                            "Source access credential",
                            renewal.sourceCredentialReference ?? "unidentified",
                            date: renewal.accessTokenExpiresAt
                        )
                        authenticationDetail(
                            "Session renewal window",
                            "expires",
                            date: renewal.sessionRenewalExpiresAt
                        )
                        authenticationDetail(
                            "Renewal credential",
                            renewal.renewalCredential.rawValue,
                            date: renewal.renewalCredentialExpiresAt
                        )
                        if let replacementReference = renewal.replacementCredentialReference,
                           let completedAt = renewal.completedAt {
                            authenticationDetail(
                                "Replacement credential",
                                replacementReference,
                                date: completedAt
                            )
                        }
                    } else {
                        Text("No token-renewal attempt has been recorded on this Mac.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

#if DEBUG
            GroupBox("Debug renewal qualification") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This sends exactly one real session-renewal request through the active client, validates the rotated response, and saves the replacement to Keychain. It does not retry or start playback.")
                        .foregroundStyle(.secondary)
                    Text(controller?.authenticationRenewalQualificationState.statusText ?? "The production authentication client is unavailable in this composition.")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    HStack {
                        Button("Force One Session Renewal…") {
                            isShowingRenewalQualificationConfirmation = true
                        }
                        .disabled(controller?.canQualifyAuthenticationRenewal != true)

                        if controller?.canQualifyAuthenticationRenewal == false {
                            Text("Sign in, wait for the channel load to finish, and stop playback first.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .confirmationDialog(
                "Send one live session-renewal request?",
                isPresented: $isShowingRenewalQualificationConfirmation,
                titleVisibility: .visible
            ) {
                Button("Send One Renewal Request") {
                    _ = controller?.qualifyAuthenticationRenewalOnce()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is a deliberate live compatibility check. It uses the stored refresh cookie once, never retries, and records only redacted outcome data.")
            }
#endif

            GroupBox("Recent diagnostics") {
                if supportBundle.diagnostics.isEmpty {
                    Text("No compatibility failures have been recorded on this Mac.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(supportBundle.diagnostics.reversed().prefix(8)) { diagnostic in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(diagnostic.code.rawValue)
                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                    Spacer()
                                    Text(diagnostic.recordedAt, format: .dateTime.month().day().hour().minute().second())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(diagnostic.summary)
                                Text(diagnostic.suggestedAction)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }
            }

            GroupBox("Support bundle preview") {
                ScrollView {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 170)
            }

            HStack {
                Text("The export contains version details, compatibility classifications, fixed-code diagnostics, and the redacted authentication details shown above. It never contains token or cookie values.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Support Report", action: copy)
                Button("Export Support Bundle…", action: export)
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 700)
        .alert("Support Bundle Wasn’t Exported", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Try another location.")
        }
    }

    @ViewBuilder
    private func authenticationDetail(_ label: String, _ value: String, date: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 190, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Text(date, format: .dateTime.month().day().hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func referenceSuffix(_ reference: String?) -> String {
        reference.map { " [\($0)]" } ?? ""
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(preview, forType: .string)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.title = "Export Canis97 Support Bundle"
        panel.nameFieldStringValue = "Canis97-Support-Bundle.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try SupportBundleFactory.encoded(supportBundle).write(to: url, options: .atomic)
        } catch {
            exportError = "Canis97 could not write the reviewed bundle to that location."
        }
    }
}
