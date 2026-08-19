import Foundation

struct ActiveSession: Sendable, Equatable {
    let establishedAt: Date
}

enum SessionState: Sendable, Equatable {
    case signedOut
    case verifyingAuthentication
    case verifyingEntitlement
    case active(ActiveSession)
}

enum SessionAttemptOutcome: Sendable, Equatable {
    case active
    case authentication(AuthenticationOutcome)
    case entitlement(EntitlementAvailability)
    case attemptInProgress
}

protocol NativeAuthenticationVerifying: Sendable {
    func verifyAuthentication(using credential: AuthenticationCredential) async -> NativeTransportResponse
}

protocol NativeEntitlementVerifying: Sendable {
    func verifyEntitlement(using credential: AuthenticationCredential) async -> NativeTransportResponse
}

protocol SessionClock: Sendable {
    func now() -> Date
}

protocol SessionDiagnostics: Sendable {
    func record(_ event: SessionDiagnosticEvent) async
}

enum SessionDiagnosticEvent: Sendable, Equatable {
    case authentication(SafeDiagnosticOutcome)
    case entitlement(SafeDiagnosticOutcome)
    case credentialPersistenceFailed
}

/// Internal result of one current-session operation. The credential remains
/// inside `SessionCoordinator`; callers receive only their semantic result or
/// a closed failure classification.
enum CurrentEntitledOperationResult<Value: Sendable>: Sendable {
    case completed(Value)
    case failed(LiveStreamResolutionFailure)
}

/// Closed outcomes for one fixed catalog operation. Catalog freshness is
/// browse-only, but its request must still use the current active session.
enum CurrentCatalogOperationResult<Value: Sendable>: Sendable {
    case completed(Value)
    case authenticationUnavailable
    case notEntitled
    case superseded
}
