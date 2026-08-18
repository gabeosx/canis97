import Foundation

/// A response supplied only by the client's native transport implementation.
///
/// This remains internal so no application caller can transform a self-authored
/// claim into an authentication or entitlement result.
struct NativeTransportResponse: Sendable {
    let statusCode: Int
    let contentType: String?
    let body: Data
    let redirectLocation: String?
    let transportFailed: Bool

    init(
        statusCode: Int,
        contentType: String?,
        body: Data,
        redirectLocation: String? = nil,
        transportFailed: Bool = false
    ) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
        self.redirectLocation = redirectLocation
        self.transportFailed = transportFailed
    }
}

struct AdapterAuthenticationClassification: Sendable, Equatable {
    let result: AdapterAuthenticationResult
    let diagnosticOutcome: SafeDiagnosticOutcome
}

struct AdapterEntitlementClassification: Sendable, Equatable {
    let result: AdapterEntitlementResult
    let diagnosticOutcome: SafeDiagnosticOutcome
}

enum AdapterAuthenticationResult: Sendable, Equatable {
    case authenticatedPendingEntitlement
    case rejected
    case challengeRequired
    case rateLimited
    case redirectDrift
    case botControlDetected
    case unsupported

    var isTerminal: Bool {
        self != .authenticatedPendingEntitlement
    }

    var publicOutcome: AuthenticationOutcome {
        switch self {
        case .authenticatedPendingEntitlement:
            .authenticatedPendingEntitlement
        case .rejected:
            .rejected
        case .challengeRequired, .rateLimited, .botControlDetected:
            .challengeRequired
        case .redirectDrift, .unsupported:
            .unsupported
        }
    }
}

enum AdapterEntitlementResult: Sendable, Equatable {
    case entitled
    case authenticatedButNotEntitled
    case rejected
    case challengeRequired
    case rateLimited
    case redirectDrift
    case botControlDetected
    case unsupported

    var isTerminal: Bool {
        self != .entitled
    }

    var publicOutcome: EntitlementAvailability {
        switch self {
        case .entitled:
            .entitled
        case .authenticatedButNotEntitled:
            .authenticatedButNotEntitled
        case .rejected:
            .rejected
        case .challengeRequired, .rateLimited, .botControlDetected:
            .challengeRequired
        case .redirectDrift, .unsupported:
            .unsupported
        }
    }
}

enum AuthenticationFlowAdapter {
    static func classifyAuthentication(_ response: NativeTransportResponse) -> AdapterAuthenticationResult {
        inspectAuthentication(response).result
    }

    static func inspectAuthentication(_ response: NativeTransportResponse) -> AdapterAuthenticationClassification {
        switch preflight(response) {
        case .accepted:
            break
        case let .authentication(result, diagnosticOutcome):
            return AdapterAuthenticationClassification(result: result, diagnosticOutcome: diagnosticOutcome)
        }

        if let control = controlResult(in: response.body) {
            return AdapterAuthenticationClassification(
                result: control,
                diagnosticOutcome: diagnosticOutcome(for: control)
            )
        }

        if ProfileResponseV4Decoder.accepts(response.body) {
            return AdapterAuthenticationClassification(
                result: .authenticatedPendingEntitlement,
                diagnosticOutcome: .completed
            )
        }
        return AdapterAuthenticationClassification(result: .unsupported, diagnosticOutcome: .unsupportedPayload)
    }

    static func classifyEntitlement(_ response: NativeTransportResponse) -> AdapterEntitlementResult {
        inspectEntitlement(response).result
    }

    static func inspectEntitlement(_ response: NativeTransportResponse) -> AdapterEntitlementClassification {
        switch preflight(response) {
        case .accepted:
            break
        case let .authentication(result, diagnosticOutcome):
            return AdapterEntitlementClassification(
                result: entitlementResult(from: result),
                diagnosticOutcome: diagnosticOutcome
            )
        }

        if let control = controlResult(in: response.body) {
            return AdapterEntitlementClassification(
                result: entitlementResult(from: control),
                diagnosticOutcome: diagnosticOutcome(for: control)
            )
        }

        switch SubscriptionStatusResponseV1Decoder.classify(response.body) {
        case .active:
            return AdapterEntitlementClassification(result: .entitled, diagnosticOutcome: .completed)
        case .inactive:
            return AdapterEntitlementClassification(result: .authenticatedButNotEntitled, diagnosticOutcome: .notEntitled)
        case .unsupported:
            return AdapterEntitlementClassification(result: .unsupported, diagnosticOutcome: .unsupportedPayload)
        }
    }

    private static func entitlementResult(from result: AdapterAuthenticationResult) -> AdapterEntitlementResult {
        switch result {
        case .authenticatedPendingEntitlement:
            .unsupported
        case .rejected:
            .rejected
        case .challengeRequired:
            .challengeRequired
        case .rateLimited:
            .rateLimited
        case .redirectDrift:
            .redirectDrift
        case .botControlDetected:
            .botControlDetected
        case .unsupported:
            .unsupported
        }
    }

    private enum Preflight {
        case accepted
        case authentication(AdapterAuthenticationResult, SafeDiagnosticOutcome)
    }

    private static func preflight(_ response: NativeTransportResponse) -> Preflight {
        guard !response.transportFailed else {
            return .authentication(.unsupported, .transportFailure)
        }
        guard response.redirectLocation == nil else {
            return .authentication(.redirectDrift, .redirectDrift)
        }
        guard response.contentType?.lowercased().hasPrefix("application/json") == true else {
            return .authentication(.unsupported, .unsupportedContentType)
        }

        switch response.statusCode {
        case 200 ... 299:
            return .accepted
        case 401, 403:
            return .authentication(.rejected, .rejected)
        case 429:
            return .authentication(.rateLimited, .rateLimited)
        default:
            return .authentication(.unsupported, .unsupportedHTTPStatus)
        }
    }

    private static func diagnosticOutcome(for result: AdapterAuthenticationResult) -> SafeDiagnosticOutcome {
        switch result {
        case .authenticatedPendingEntitlement:
            .completed
        case .rejected:
            .rejected
        case .challengeRequired:
            .challengeRequired
        case .rateLimited:
            .rateLimited
        case .redirectDrift:
            .redirectDrift
        case .botControlDetected:
            .botControlDetected
        case .unsupported:
            .unsupportedPayload
        }
    }

    private static func controlResult(in body: Data) -> AdapterAuthenticationResult? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        if object["bot"] as? Bool == true {
            return .botControlDetected
        }
        if let challenge = object["challenge"] as? String,
           ["captcha", "mfa", "control"].contains(challenge.lowercased()) {
            return .challengeRequired
        }
        return nil
    }
}

/// Settled internal profile-v4 compatibility predicate. Authentication only
/// requires a non-empty JSON object after transport and control preflight.
enum ProfileResponseV4Decoder {
    static func accepts(_ body: Data) -> Bool {
        guard !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body),
              object is [String: Any] else {
            return false
        }
        return true
    }
}

/// Settled internal subscription-v1 compatibility predicate. No response
/// fields other than the exact nested status participate in entitlement.
enum SubscriptionStatusResponseV1Decoder {
    enum Result: Sendable, Equatable {
        case active
        case inactive
        case unsupported
    }

    private struct Response: Decodable {
        struct Subscription: Decodable {
            let status: String?
        }

        let subscription: Subscription?
    }

    static func classify(_ body: Data) -> Result {
        guard let response = try? JSONDecoder().decode(Response.self, from: body),
              let status = response.subscription?.status else {
            return .unsupported
        }

        switch status {
        case "active":
            return .active
        case "inactive":
            return .inactive
        default:
            return .unsupported
        }
    }
}
