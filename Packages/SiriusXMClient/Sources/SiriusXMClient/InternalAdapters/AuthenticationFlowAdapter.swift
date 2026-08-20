import Foundation

/// A closed, secret-free classification of failures raised before an HTTP
/// response exists. It deliberately retains no error message or URL.
enum SafeTransportFailure: Sendable, Equatable {
    case timedOut
    case nameResolution
    case connection
    case tls
    case cancelled
    case other

    init(error: any Error) {
        guard let urlError = error as? URLError else {
            self = .other
            return
        }

        switch urlError.code {
        case .timedOut:
            self = .timedOut
        case .cannotFindHost, .dnsLookupFailed:
            self = .nameResolution
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            self = .connection
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            self = .tls
        case .cancelled:
            self = .cancelled
        default:
            self = .other
        }
    }

    var diagnosticOutcome: SafeDiagnosticOutcome {
        switch self {
        case .timedOut:
            .transportTimedOut
        case .nameResolution:
            .transportNameResolutionFailed
        case .connection:
            .transportConnectionFailed
        case .tls:
            .transportTLSFailed
        case .cancelled:
            .transportCancelled
        case .other:
            .transportFailure
        }
    }
}

/// A response supplied only by the client's native transport implementation.
///
/// This remains internal so no application caller can transform a self-authored
/// claim into an authentication or entitlement result.
struct NativeTransportResponse: Sendable {
    let statusCode: Int
    let contentType: String?
    let body: Data
    let redirectLocation: String?
    let transportFailure: SafeTransportFailure?

    init(
        statusCode: Int,
        contentType: String?,
        body: Data,
        redirectLocation: String? = nil,
        transportFailed: Bool = false,
        transportFailure: SafeTransportFailure? = nil
    ) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
        self.redirectLocation = redirectLocation
        self.transportFailure = transportFailure ?? (transportFailed ? .other : nil)
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

        switch ProfileResponseV4Decoder.inspect(response.body) {
        case .accepted:
            return AdapterAuthenticationClassification(
                result: .authenticatedPendingEntitlement,
                diagnosticOutcome: .completed
            )
        case let .unsupported(diagnosticOutcome):
            return AdapterAuthenticationClassification(result: .unsupported, diagnosticOutcome: diagnosticOutcome)
        }
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

        switch SubscriptionsResponseV1Decoder.inspect(response.body) {
        case .active:
            return AdapterEntitlementClassification(result: .entitled, diagnosticOutcome: .completed)
        case .inactive:
            return AdapterEntitlementClassification(result: .authenticatedButNotEntitled, diagnosticOutcome: .notEntitled)
        case let .unsupported(diagnosticOutcome):
            return AdapterEntitlementClassification(result: .unsupported, diagnosticOutcome: diagnosticOutcome)
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
        if let transportFailure = response.transportFailure {
            return .authentication(.unsupported, transportFailure.diagnosticOutcome)
        }
        guard response.redirectLocation == nil else {
            return .authentication(.redirectDrift, .redirectDrift)
        }

        switch response.statusCode {
        case 401:
            return .authentication(.rejected, .httpUnauthorized)
        case 403:
            return .authentication(.rejected, .httpForbidden)
        case 429:
            return .authentication(.rateLimited, .rateLimited)
        case 404:
            return .authentication(.unsupported, .httpNotFound)
        case 400 ... 499:
            return .authentication(.unsupported, .httpClientError)
        case 500 ... 599:
            return .authentication(.unsupported, .httpServerError)
        case 200 ... 299:
            break
        default:
            return .authentication(.unsupported, .unsupportedHTTPStatus)
        }

        guard let contentType = response.contentType else {
            return .authentication(.unsupported, .contentTypeMissing)
        }
        let normalizedContentType = contentType.lowercased()
        guard normalizedContentType.hasPrefix("application/json") else {
            let outcome: SafeDiagnosticOutcome = normalizedContentType.hasPrefix("text/html")
                ? .contentTypeHTML
                : .unsupportedContentType
            return .authentication(.unsupported, outcome)
        }
        return .accepted
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
    enum Inspection: Sendable, Equatable {
        case accepted
        case unsupported(SafeDiagnosticOutcome)
    }

    static func inspect(_ body: Data) -> Inspection {
        guard !body.isEmpty else {
            return .unsupported(.payloadEmpty)
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) else {
            return .unsupported(.payloadMalformedJSON)
        }
        guard object is [String: Any] else {
            return .unsupported(.payloadUnexpectedRoot)
        }
        return .accepted
    }

    static func accepts(_ body: Data) -> Bool {
        inspect(body) == .accepted
    }
}

/// Current subscription-v1 compatibility predicate. Entitlement depends only
/// on the state of the returned subscription items; all other fields remain
/// deliberately ignored.
enum SubscriptionsResponseV1Decoder {
    enum Result: Sendable, Equatable {
        case active
        case inactive
        case unsupported(SafeDiagnosticOutcome)
    }

    static func classify(_ body: Data) -> Result {
        inspect(body)
    }

    static func inspect(_ body: Data) -> Result {
        guard !body.isEmpty else {
            return .unsupported(.payloadEmpty)
        }
        guard let decoded = try? JSONSerialization.jsonObject(with: body) else {
            return .unsupported(.payloadMalformedJSON)
        }
        guard let root = decoded as? [String: Any] else {
            return .unsupported(.payloadUnexpectedRoot)
        }
        guard root.keys.contains("items") else {
            return .unsupported(.subscriptionsItemsMissing)
        }
        guard let items = root["items"] as? [Any] else {
            return .unsupported(.subscriptionsItemsUnexpectedShape)
        }

        var states: [String] = []
        states.reserveCapacity(items.count)
        for value in items {
            guard let item = value as? [String: Any] else {
                return .unsupported(.subscriptionItemUnexpectedShape)
            }
            guard item.keys.contains("state") else {
                return .unsupported(.subscriptionStateMissing)
            }
            guard let state = item["state"] as? String else {
                return .unsupported(.subscriptionStateUnexpectedShape)
            }
            states.append(state)
        }

        if states.contains("active") {
            return .active
        }
        if states.allSatisfy({ $0 == "finished" }) {
            return .inactive
        }
        return .unsupported(.subscriptionStateUnsupported)
    }
}
