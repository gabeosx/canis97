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

    init(statusCode: Int, contentType: String?, body: Data, redirectLocation: String? = nil) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
        self.redirectLocation = redirectLocation
    }
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
        switch preflight(response) {
        case .accepted:
            break
        case let .authentication(result):
            return result
        }

        guard let object = exactJSONObject(response.body) else {
            return .unsupported
        }

        if object["authenticated"] as? Bool == true {
            return .authenticatedPendingEntitlement
        }
        if object["authenticated"] as? Bool == false {
            return .rejected
        }
        if object["bot"] as? Bool == true {
            return .botControlDetected
        }
        if let challenge = object["challenge"] as? String,
           ["captcha", "mfa", "control"].contains(challenge.lowercased()) {
            return .challengeRequired
        }
        return .unsupported
    }

    static func classifyEntitlement(_ response: NativeTransportResponse) -> AdapterEntitlementResult {
        switch preflight(response) {
        case .accepted:
            break
        case let .authentication(result):
            return entitlementResult(from: result)
        }

        guard let object = exactJSONObject(response.body) else {
            return .unsupported
        }

        if object["entitled"] as? Bool == true {
            return .entitled
        }
        if object["entitled"] as? Bool == false {
            return .authenticatedButNotEntitled
        }
        if object["bot"] as? Bool == true {
            return .botControlDetected
        }
        if let challenge = object["challenge"] as? String,
           ["captcha", "mfa", "control"].contains(challenge.lowercased()) {
            return .challengeRequired
        }
        return .unsupported
    }

    private static func exactJSONObject(_ data: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              dictionary.count == 1
        else {
            return nil
        }
        return dictionary
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
        case authentication(AdapterAuthenticationResult)
    }

    private static func preflight(_ response: NativeTransportResponse) -> Preflight {
        guard response.redirectLocation == nil else {
            return .authentication(.redirectDrift)
        }
        guard response.contentType?.lowercased().hasPrefix("application/json") == true else {
            return .authentication(.unsupported)
        }

        switch response.statusCode {
        case 200 ... 299:
            return .accepted
        case 401, 403:
            return .authentication(.rejected)
        case 429:
            return .authentication(.rateLimited)
        default:
            return .authentication(.unsupported)
        }
    }
}
