import Foundation

/// The fixed, ordered native requests established by the settled authentication architecture.
///
/// This type deliberately provides no arbitrary URL or header construction surface.
enum SiriusXMRequestContract: CaseIterable, Sendable {
    case authentication
    case entitlement
    case catalog
    case tune
    case playbackKey
    case liveUpdate
    case channelPeek
    case streamEnforcement

    static let host = "api.edge-gateway.siriusxm.com"
    static let publicChannelGuideHost = "www.siriusxm.com"
    static let opaqueMediaDeliveryHost = "live-akc-prod-device.streaming.siriusxm.com"

    static func isOpaqueMediaDeliveryHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == opaqueMediaDeliveryHost ||
            (host.hasPrefix("live-") && host.hasSuffix(".streaming.siriusxm.com"))
    }

    static var all: [Self] { Array(allCases) }

    /// The only provider operations approved for Phase 02. Path-template values
    /// are compatibility facts, not a generic request-construction API.
    static let liveListeningOperations: [Self] = [
        .catalog,
        .tune,
        .playbackKey,
        .liveUpdate,
        .channelPeek,
        .streamEnforcement,
    ]

    /// The only authorized runtime sequence: authenticate, then verify entitlement.
    static let authenticationSequence: [Self] = [.authentication, .entitlement]

    var operationID: String {
        switch self {
        case .authentication: "authentication"
        case .entitlement: "entitlement"
        case .catalog: "catalog"
        case .tune: "tune"
        case .playbackKey: "playback-key"
        case .liveUpdate: "live-update"
        case .channelPeek: "channel-peek"
        case .streamEnforcement: "stream-enforcement"
        }
    }

    var host: String {
        switch self {
        case .catalog: Self.publicChannelGuideHost
        default: Self.host
        }
    }

    var method: String {
        switch self {
        case .tune, .liveUpdate: "POST"
        case .authentication, .entitlement, .catalog, .playbackKey, .channelPeek, .streamEnforcement: "GET"
        }
    }

    var pathTemplate: String {
        switch self {
        case .authentication:
            "/profile/v4/profiles/me"
        case .entitlement:
            "/subscription/v1/subscriptions"
        case .catalog:
            "/v2/channelfeed/SXM_SIR_AUD_TOTAL_ACCESS"
        case .tune:
            "/playback/play/v1/tuneSource"
        case .playbackKey:
            "/playback/key/v1/{keyId}"
        case .liveUpdate:
            "/playback/play/v1/liveUpdate"
        case .channelPeek:
            "/channel-guide/v1/channel/{channelId}/peek"
        case .streamEnforcement:
            "/playback/stream-enforcement/v1/status"
        }
    }

    /// Backward-compatible exact path spelling for materialized Phase 01
    /// requests. Phase 02 template cases are deliberately not materializable.
    var path: String { pathTemplate }

    /// Only the settled Phase 01 requests are materialized by the transport.
    /// Phase 02 mappings remain semantic scaffolding until their subsequent
    /// capability plans establish the required opaque request inputs.
    var isTransportMaterializable: Bool {
        switch self {
        case .authentication, .entitlement: true
        case .catalog, .tune, .playbackKey, .liveUpdate, .channelPeek, .streamEnforcement: false
        }
    }

    var bodyContract: SiriusXMRequestBodyContract {
        switch self {
        case .tune:
            .tuneSource
        case .liveUpdate:
            .liveActivity
        case .authentication, .entitlement, .catalog, .playbackKey, .channelPeek, .streamEnforcement:
            .none
        }
    }

    var accept: String { "application/json" }

    var url: URL {
        URL(string: "https://\(host)\(pathTemplate)")!
    }

    static func makeRequest(for operation: Self, authorization: String) throws -> URLRequest {
        guard operation.isTransportMaterializable else {
            throw SiriusXMRequestContractError.operationNotMaterializable
        }
        guard !authorization.isEmpty,
              !authorization.contains(where: { $0.isWhitespace || $0.isNewline })
        else {
            throw SiriusXMRequestContractError.invalidAuthorizationMaterial
        }

        var request = URLRequest(url: operation.url)
        request.httpMethod = operation.method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(operation.accept, forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func makeRequest(
        for operation: Self,
        using credential: AuthenticationCredential
    ) throws -> URLRequest {
        guard let authorization = credential.accessToken() else {
            throw SiriusXMRequestContractError.invalidAuthorizationMaterial
        }
        return try makeRequest(for: operation, authorization: authorization)
    }
}

enum SiriusXMRequestContractError: Error, Sendable {
    case invalidAuthorizationMaterial
    case operationNotMaterializable
}

/// The complete non-secret body facts approved for Phase 02. This model does
/// not serialize a provider request or retain a channel, key, resource, or
/// timestamp value.
enum SiriusXMRequestBodyContract: Sendable, Equatable {
    case none
    case tuneSource
    case liveActivity

    var fixedFieldNames: [String] {
        fixedSemantics.keys.sorted()
    }

    /// Values are modeled only when the canonical contract records them. The
    /// opaque and logical cases deliberately contain no provider material.
    var fixedSemantics: [String: SiriusXMFixedRequestSemantic] {
        switch self {
        case .none:
            [:]
        case .tuneSource:
            [
                "type": .string("channel-linear"),
                "hlsVersion": .string("V3"),
                "manifestVariant": .string("WEB"),
                "mtcVersion": .string("V2"),
                "trackResumeSupported": .boolean(false),
                "x-sxm-clock": .epochCounter,
            ]
        case .liveActivity:
            [
                "channelId": .opaqueValue,
                "startTimestamp": .opaqueValue,
                "endTimestamp": .opaqueValue,
            ]
        }
    }
}

enum SiriusXMFixedRequestSemantic: Sendable, Equatable {
    case string(String)
    case boolean(Bool)
    case epochCounter
    case opaqueValue
}
