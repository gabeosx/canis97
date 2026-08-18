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
    case cancelled
    case authentication(AuthenticationOutcome)
    case entitlement(EntitlementAvailability)
    case credentialPersistenceFailed
}
