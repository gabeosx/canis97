import Foundation

/// An opaque, in-memory credential handoff for the app-owned authentication bridge.
///
/// The value intentionally cannot be encoded or rendered with its material.
public struct AuthenticationCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private static let maximumSecretSize = 8_192
    private static let maximumCookieValueSize = 16_384
    private static let maximumEnvelopeSize = 40_960
    private let material: Data

    /// Creates a volatile handoff value for a caller that has already performed an authorized extraction.
    public init(volatileMaterial: Data) {
        self.material = volatileMaterial
    }

    /// Creates the versioned browser-session envelope used by the app-owned WebKit bridge.
    ///
    /// Both values remain opaque outside the integration boundary. The device grant is
    /// included when WebKit exposes it, but SiriusXM may keep that separately in client
    /// storage and recreate it during browser initialization.
    @_spi(AppIntegration)
    public init(
        browserAuthenticationCookieValue: String,
        browserDeviceGrantCookieValue: String?
    ) throws {
        let envelope = BrowserCredentialEnvelope(
            format: BrowserCredentialEnvelope.expectedFormat,
            version: BrowserCredentialEnvelope.currentVersion,
            authenticationCookieValue: browserAuthenticationCookieValue,
            deviceGrantCookieValue: browserDeviceGrantCookieValue
        )
        _ = try Self.parseBrowserCredential(from: envelope)
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(envelope)
        } catch {
            throw AuthenticationCredentialMaterialError.envelopeEncodingFailed
        }
        guard encoded.count <= Self.maximumEnvelopeSize else {
            throw AuthenticationCredentialMaterialError.envelopeTooLarge
        }
        material = encoded
    }

    public var description: String { "AuthenticationCredential(redacted)" }
    public var debugDescription: String { "AuthenticationCredential(redacted)" }

    /// Performs work with the short-lived material for the app's approved integration boundary.
    ///
    /// This SPI exists solely for the app-owned Keychain adapter. It is not part of the
    /// ordinary client-consumer API and does not provide a persistent credential accessor.
    @_spi(AppIntegration)
    public func withVolatileMaterial<Result: Sendable>(_ operation: (Data) throws -> Result) rethrows -> Result {
        try operation(material)
    }

    /// Returns a bounded browser-session snapshot only to the app-owned WebKit renewal bridge.
    @_spi(AppIntegration)
    public func browserSessionSnapshot() -> BrowserAuthenticationSessionSnapshot? {
        guard let envelope = Self.decodeEnvelope(from: material) else { return nil }
        return Self.parsedBrowserCredential(from: envelope)?.snapshot
    }

    /// Performs app-integration work with only the current access token, never the
    /// persisted browser cookie envelope.
    @_spi(AppIntegration)
    public func withAccessToken<Result: Sendable>(
        _ operation: (String) throws -> Result
    ) rethrows -> Result? {
        guard let accessToken = accessToken() else { return nil }
        return try operation(accessToken)
    }

    /// Validates Keychain bytes without exposing their contents.
    @_spi(AppIntegration)
    public static func isSupportedPersistentMaterial(_ material: Data) -> Bool {
        guard let envelope = decodeEnvelope(from: material) else { return false }
        return parsedBrowserCredential(from: envelope) != nil
    }

    func accessToken() -> String? {
        if let envelope = Self.decodeEnvelope(from: material),
           let parsed = Self.parsedBrowserCredential(from: envelope) {
            return parsed.accessToken
        }
        return nil
    }

    func requiresBrowserRefresh(at date: Date, leeway: TimeInterval = 300) -> Bool {
        guard let envelope = Self.decodeEnvelope(from: material),
              let parsed = Self.parsedBrowserCredential(from: envelope) else {
            return false
        }
        return parsed.snapshot.accessTokenExpiresAt <= date.addingTimeInterval(leeway)
    }

    private static func decodeEnvelope(from material: Data) -> BrowserCredentialEnvelope? {
        guard material.count <= maximumEnvelopeSize,
              let envelope = try? JSONDecoder().decode(BrowserCredentialEnvelope.self, from: material),
              envelope.format == BrowserCredentialEnvelope.expectedFormat,
              envelope.version == BrowserCredentialEnvelope.currentVersion else {
            return nil
        }
        return envelope
    }

    private static func parsedBrowserCredential(from envelope: BrowserCredentialEnvelope) -> ParsedBrowserCredential? {
        try? parseBrowserCredential(from: envelope)
    }

    private static func parseBrowserCredential(
        from envelope: BrowserCredentialEnvelope
    ) throws -> ParsedBrowserCredential {
        guard envelope.authenticationCookieValue.utf8.count <= maximumCookieValueSize else {
            throw AuthenticationCredentialMaterialError.authenticationCookieTooLarge
        }
        guard let authenticationJSON = decodedCookieJSON(envelope.authenticationCookieValue) else {
            throw AuthenticationCredentialMaterialError.authenticationCookieUnreadable
        }
        guard let sessionValue = authenticationJSON["session"] else {
            throw AuthenticationCredentialMaterialError.sessionObjectMissing
        }
        guard let session = sessionValue as? [String: Any] else {
            throw AuthenticationCredentialMaterialError.sessionObjectInvalid
        }
        guard let accessTokenValue = session["accessToken"] else {
            throw AuthenticationCredentialMaterialError.accessTokenMissing
        }
        guard let accessToken = boundedSecret(accessTokenValue) else {
            throw AuthenticationCredentialMaterialError.accessTokenInvalid
        }
        guard let accessTokenExpiryValue = session["accessTokenExpiresAt"] else {
            throw AuthenticationCredentialMaterialError.accessTokenExpiryMissing
        }
        guard let accessTokenExpiresAt = providerDate(accessTokenExpiryValue) else {
            throw AuthenticationCredentialMaterialError.accessTokenExpiryInvalid
        }
        // Older/current browser-session variants do not all serialize this
        // discriminator. Reject a known non-authenticated session, but let the
        // native profile and entitlement verifiers remain authoritative when the
        // otherwise complete renewable session omits it.
        if let sessionType = session["sessionType"] as? String,
           sessionType != "authenticated" {
            throw AuthenticationCredentialMaterialError.sessionTypeRejected
        }

        let deviceGrant: ParsedDeviceGrant?
        let deviceGrantDisposition: BrowserDeviceGrantDisposition
        if let deviceGrantCookieValue = envelope.deviceGrantCookieValue {
            deviceGrant = parsedDeviceGrant(from: deviceGrantCookieValue)
            deviceGrantDisposition = deviceGrant == nil ? .discardedUnrecognized : .accepted
        } else {
            deviceGrant = nil
            deviceGrantDisposition = .absent
        }

        // SiriusXM 7.131.0 no longer serializes refreshToken in an authenticated
        // AUTH_TOKEN. Its browser client retains renewable authority across the
        // paired DEVICE_GRANT instead. Preserve the older direct-refresh variant,
        // but require one complete renewal path before accepting persistent
        // material; an access token alone remains insufficient.
        let refreshToken: String?
        let renewalDisposition: BrowserRenewalDisposition
        if let refreshTokenValue = session["refreshToken"] {
            guard let parsedRefreshToken = boundedSecret(refreshTokenValue) else {
                throw AuthenticationCredentialMaterialError.refreshTokenInvalid
            }
            refreshToken = parsedRefreshToken
            renewalDisposition = .refreshToken
        } else if deviceGrant != nil {
            refreshToken = nil
            renewalDisposition = .deviceGrant
        } else {
            throw AuthenticationCredentialMaterialError.refreshTokenMissing
        }
        guard let refreshTokenExpiryValue = session["refreshTokenExpiresAt"] else {
            throw AuthenticationCredentialMaterialError.refreshTokenExpiryMissing
        }
        guard let refreshTokenExpiresAt = providerDate(refreshTokenExpiryValue) else {
            throw AuthenticationCredentialMaterialError.refreshTokenExpiryInvalid
        }

        _ = refreshToken
        return ParsedBrowserCredential(
            accessToken: accessToken,
            snapshot: BrowserAuthenticationSessionSnapshot(
                authenticationCookieValue: envelope.authenticationCookieValue,
                deviceGrantCookieValue: deviceGrant?.cookieValue,
                accessTokenExpiresAt: accessTokenExpiresAt,
                refreshTokenExpiresAt: refreshTokenExpiresAt,
                deviceGrantExpiresAt: deviceGrant?.grantExpiresAt,
                deviceRefreshGrantExpiresAt: deviceGrant?.refreshGrantExpiresAt,
                deviceGrantDisposition: deviceGrantDisposition,
                renewalDisposition: renewalDisposition
            )
        )
    }

    private static func parsedDeviceGrant(from cookieValue: String) -> ParsedDeviceGrant? {
        guard cookieValue.utf8.count <= maximumCookieValueSize,
              let deviceGrantJSON = decodedCookieJSON(cookieValue),
              boundedSecret(deviceGrantJSON["deviceId"]) != nil,
              boundedSecret(deviceGrantJSON["grant"]) != nil,
              let grantExpiresAt = providerDate(deviceGrantJSON["grantExpiresAt"]),
              boundedSecret(deviceGrantJSON["refreshGrant"]) != nil,
              let refreshGrantExpiresAt = providerDate(deviceGrantJSON["refreshGrantExpiresAt"]) else {
            // DEVICE_GRANT is an auxiliary browser credential. SiriusXM's web
            // client reconciles and can recreate it independently, so an
            // unfamiliar optional device shape must not poison a valid AUTH_TOKEN.
            return nil
        }
        return ParsedDeviceGrant(
            cookieValue: cookieValue,
            grantExpiresAt: grantExpiresAt,
            refreshGrantExpiresAt: refreshGrantExpiresAt
        )
    }

    private static func decodedCookieJSON(_ encoded: String) -> [String: Any]? {
        var candidate = encoded
        for _ in 0..<3 {
            guard candidate.utf8.count <= maximumCookieValueSize else { return nil }
            if let dictionary = JSONDictionary.decode(candidate) {
                return dictionary
            }
            guard let decoded = candidate.removingPercentEncoding,
                  decoded != candidate else {
                return nil
            }
            candidate = decoded
        }
        guard candidate.utf8.count <= maximumCookieValueSize else { return nil }
        return JSONDictionary.decode(candidate)
    }

    private static func boundedSecret(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.count <= maximumSecretSize,
              !value.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            return nil
        }
        return value
    }

    private static func providerDate(_ value: Any?) -> Date? {
        if let value = value as? String {
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }
            return ISO8601DateFormatter().date(from: value)
        }

        // JavaScript Date accepts epoch milliseconds, and provider adapters have
        // historically used both ISO strings and numeric timestamps. Keep numeric
        // acceptance bounded to plausible modern credential lifetimes.
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        let seconds = raw >= 100_000_000_000 ? raw / 1_000 : raw
        let date = Date(timeIntervalSince1970: seconds)
        let lowerBound = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01
        let upperBound = Date(timeIntervalSince1970: 7_258_118_400) // 2200-01-01
        return (lowerBound...upperBound).contains(date) ? date : nil
    }

}

private enum JSONDictionary {
    static func decode(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        if let dictionary = object as? [String: Any] {
            return dictionary
        }
        guard let nested = object as? String,
              nested.utf8.count <= 16_384,
              let nestedData = nested.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: nestedData) as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}

@_spi(AppIntegration)
public struct BrowserAuthenticationSessionSnapshot: Sendable {
    public let authenticationCookieValue: String
    public let deviceGrantCookieValue: String?
    public let accessTokenExpiresAt: Date
    public let refreshTokenExpiresAt: Date
    public let deviceGrantExpiresAt: Date?
    public let deviceRefreshGrantExpiresAt: Date?
    public let deviceGrantDisposition: BrowserDeviceGrantDisposition
    public let renewalDisposition: BrowserRenewalDisposition
}

@_spi(AppIntegration)
public enum BrowserDeviceGrantDisposition: String, Sendable, Equatable {
    case absent
    case accepted
    case discardedUnrecognized = "discarded-unrecognized"
}

/// The complete browser-owned mechanism that can renew the persisted session.
/// This classification contains no credential material and is safe to expose to
/// the app's fixed-vocabulary diagnostics.
@_spi(AppIntegration)
public enum BrowserRenewalDisposition: String, Sendable, Equatable {
    case refreshToken = "refresh-token"
    case deviceGrant = "device-grant"
}

/// Redacted structural reason that browser material could not become a reusable
/// credential. Cases intentionally describe no values, lengths, dates, domains,
/// identifiers, or account data and are safe for fixed-vocabulary diagnostics.
@_spi(AppIntegration)
public enum AuthenticationCredentialMaterialError: String, Error, Sendable, Equatable {
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
    case sessionTypeRejected = "session-type-rejected"
    case envelopeEncodingFailed = "envelope-encoding-failed"
    case envelopeTooLarge = "envelope-too-large"
}

private struct BrowserCredentialEnvelope: Codable {
    static let expectedFormat = "siriusxm-browser-session"
    static let currentVersion = 1

    let format: String
    let version: Int
    let authenticationCookieValue: String
    let deviceGrantCookieValue: String?
}

private struct ParsedBrowserCredential {
    let accessToken: String
    let snapshot: BrowserAuthenticationSessionSnapshot
}

private struct ParsedDeviceGrant {
    let cookieValue: String
    let grantExpiresAt: Date
    let refreshGrantExpiresAt: Date
}

/// Supplies an opaque credential to the client without exposing integration mechanics.
public protocol CredentialSource: Sendable {
    func credential() async -> AuthenticationCredential?
}

/// Persists only client-approved opaque credential material at the app boundary.
public protocol CredentialStore: Sendable {
    func save(_ credential: AuthenticationCredential) async throws
    func erase() async throws
}

/// Renews an expiring browser-issued credential without collecting account credentials.
public protocol CredentialRefresher: Sendable {
    func refreshedCredential(ifNeeded credential: AuthenticationCredential) async -> AuthenticationCredential?
}

/// Removes app-owned browser residue without exposing browser APIs to the client.
public protocol AuthenticationResidueCleaner: Sendable {
    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome
}

/// Semantic completion state for one injected browser-residue cleanup operation.
public enum AuthenticationResidueCleanupOutcome: Sendable, Equatable {
    case removed
    case cleanupFailed
}

/// Semantic result of an authentication attempt.
public enum AuthenticationOutcome: Sendable, Equatable {
    case waitingForAuthenticationComposition
    case authenticatedPendingEntitlement
    case credentialPersistenceFailed
    case rejected
    case challengeRequired
    case unsupported
    case cancelled
}

/// Semantic entitlement availability for the current client state.
public enum EntitlementAvailability: Sendable, Equatable {
    case unavailable
    case entitled
    case authenticatedButNotEntitled
    case rejected
    case challengeRequired
    case unsupported
    case cancelled
}

/// Semantic result of ending a client session.
public enum SignOutOutcome: Sendable, Equatable {
    case alreadySignedOut
    case signedOut
    case cleanupFailed(SignOutCleanupFailure)
}

/// Safe aggregate classification for local cleanup that did not complete.
public enum SignOutCleanupFailure: Sendable, Equatable {
    case keychain
    case browserResidue
    case both
}
