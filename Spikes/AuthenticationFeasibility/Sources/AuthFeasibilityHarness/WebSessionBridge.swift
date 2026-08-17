import Foundation

/// The only transferable browser-authentication material. It is in-memory,
/// single-consumption, non-codable, and contains the current player access token.
@MainActor
public final class VolatileWebSession {
    private var accessToken: String?

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    func consume() -> String? {
        defer { accessToken = nil }
        return accessToken
    }

    deinit {
        accessToken = nil
    }
}

enum WebSessionExtraction {
    case session(VolatileWebSession)
    case authCookieMissing
    case authCookieMalformed
}

public enum WebSessionBridgeResult: String, Equatable, Sendable {
    case verified
    case authCookieMissing = "auth-cookie-missing"
    case authCookieMalformed = "auth-cookie-malformed"
    case alreadyConsumed = "session-already-consumed"
    case rejected
    case protectedControl = "protected-control"
    case rateLimited = "rate-limited"
    case serviceUnavailable = "service-unavailable"
    case ambiguous
    case cancelled

    public var canonicalText: String {
        [
            "Schema: web-session-bridge-v1",
            "Outcome: \(rawValue)",
            "Credential persistence: none",
            "Phase 1 continuation: blocked",
            "",
        ].joined(separator: "\n")
    }

    public var ownerVisibleText: String {
        switch self {
        case .verified: "Web session imported and verified natively"
        case .authCookieMissing: "Player login cookie absent — the WebView is not signed in"
        case .authCookieMalformed: "Player login cookie found, but its session token is invalid"
        case .alreadyConsumed: "Web session was already consumed"
        case .rejected: "Imported session was rejected"
        case .protectedControl: "Protected response — stopped"
        case .rateLimited: "Rate limit encountered — stopped"
        case .serviceUnavailable: "SiriusXM session verification unavailable"
        case .ambiguous: "Session verification ambiguous — stopped"
        case .cancelled: "Session import cancelled"
        }
    }
}

enum SiriusXMAuthCookieExtractor {
    @MainActor
    static func extract(from cookies: [HTTPCookie], now: Date = Date()) -> WebSessionExtraction {
        let candidates = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let isFirstParty = domain == "siriusxm.com" || domain.hasSuffix(".siriusxm.com")
            let isCurrent = cookie.expiresDate.map { $0 > now } ?? true
            return cookie.name == "AUTH_TOKEN" && isFirstParty && isCurrent
        }
        guard candidates.count == 1 else {
            return candidates.isEmpty ? .authCookieMissing : .authCookieMalformed
        }
        let encodedValue = candidates[0].value
        let decodedValue = encodedValue.removingPercentEncoding ?? encodedValue
        guard let data = decodedValue.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = root["session"] as? [String: Any],
              let accessToken = session["accessToken"] as? String,
              (20...8192).contains(accessToken.utf8.count),
              !accessToken.contains(where: { $0.isWhitespace }) else {
            return .authCookieMalformed
        }
        return .session(VolatileWebSession(accessToken: accessToken))
    }
}

struct WebSessionHTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
}

struct WebSessionTransport: Sendable {
    let send: @MainActor @Sendable (URLRequest) async throws -> WebSessionHTTPResponse

    static let live = WebSessionTransport { request in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil

        let urlSession = URLSession(configuration: configuration)
        defer {
            urlSession.invalidateAndCancel()
        }
        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return WebSessionHTTPResponse(statusCode: response.statusCode, body: data)
    }
}

/// Consumes one extracted WebKit session and verifies it through SiriusXM's
/// normal resume operation using an ephemeral native URLSession.
@MainActor
struct NativeWebSessionVerifier: Sendable {
    private static let endpoint = URL(
        string: "https://api.edge-gateway.siriusxm.com/identity/v1/identities/status"
    )!

    private let transport: WebSessionTransport

    init(transport: WebSessionTransport = .live) {
        self.transport = transport
    }

    func verify(_ session: VolatileWebSession) async -> WebSessionBridgeResult {
        guard let accessToken = session.consume() else { return .alreadyConsumed }

        do {
            var request = URLRequest(url: Self.endpoint)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("SiriusMac/0.1 (macOS; native session bridge)", forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let response = try await transport.send(request)
            return Self.classify(response)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch {
            return .serviceUnavailable
        }
    }

    static func classify(_ response: WebSessionHTTPResponse) -> WebSessionBridgeResult {
        switch response.statusCode {
        case 200...299: return .verified
        case 401: return .rejected
        case 403: return .protectedControl
        case 429: return .rateLimited
        case 500...599: return .serviceUnavailable
        default: return .ambiguous
        }
    }
}
