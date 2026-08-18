import Foundation

/// The fixed, ordered native requests established by the settled authentication architecture.
///
/// This type deliberately provides no arbitrary URL or header construction surface.
enum SiriusXMRequestContract: CaseIterable, Sendable {
    case authentication
    case entitlement

    static let host = "api.edge-gateway.siriusxm.com"

    static var all: [Self] { Array(allCases) }

    /// The only authorized runtime sequence: authenticate, then verify entitlement.
    static let authenticationSequence: [Self] = [.authentication, .entitlement]

    var method: String { "GET" }

    var path: String {
        switch self {
        case .authentication:
            "/profile/v4/profiles/me"
        case .entitlement:
            "/subscription/v1/status"
        }
    }

    var accept: String { "application/json" }

    var url: URL {
        URL(string: "https://\(Self.host)\(path)")!
    }

    static func makeRequest(for operation: Self, authorization: String) throws -> URLRequest {
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
        try credential.withVolatileMaterial { material in
            guard let authorization = String(data: material, encoding: .utf8) else {
                throw SiriusXMRequestContractError.invalidAuthorizationMaterial
            }
            return try makeRequest(for: operation, authorization: authorization)
        }
    }
}

enum SiriusXMRequestContractError: Error, Sendable {
    case invalidAuthorizationMaterial
}
