public enum SanitizedNavigationProvenance: Equatable, Sendable {
    case firstPartyNavigation
    case matchedAppBoundReturn
}

public enum SafeTerminalReason: Equatable, Sendable {
    case offProvenanceNavigation
    case unexpectedNavigation
    case challenge
    case protectedControl
    case rejection
    case redirectMismatch
    case rateLimited
    case botOrAccessControl
    case unknown
    case ambiguous
}

/// The only durable boundary produced by the browser experiment. No case contains
/// credentials, cookies, tokens, account identifiers, response data, or URLs.
public enum SafeProbeEvent: Equatable, Sendable {
    case cleanAppBoundReturn
    case authenticated
    case entitled
    case noCleanReturn(SanitizedNavigationProvenance)
    case tuneKeyAuthorized
    case audiblePlayback
    case renewed
    case renewalPending
    case terminal(SafeTerminalReason)
    case cancelled
    case signedOut
    case cleanupVerified
    case cleanupFailed
}
