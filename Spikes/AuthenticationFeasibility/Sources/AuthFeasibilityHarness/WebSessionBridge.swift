import Foundation

/// The only transferable browser-authentication material. It is in-memory,
/// single-consumption, non-codable, and contains first-party SiriusXM cookies only.
@MainActor
public final class VolatileWebSession {
    private var cookies: [HTTPCookie]?

    init(cookies: [HTTPCookie]) {
        self.cookies = cookies
    }

    func consumeCookies() -> [HTTPCookie]? {
        defer {
            cookies?.removeAll(keepingCapacity: false)
            cookies = nil
        }
        return cookies
    }

    deinit {
        cookies?.removeAll(keepingCapacity: false)
        cookies = nil
    }
}

public enum WebSessionBridgeResult: String, Equatable, Sendable {
    case verified
    case noFirstPartySession = "no-first-party-session"
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
        case .noFirstPartySession: "No SiriusXM session found — finish signing in first"
        case .rejected: "Imported session was rejected"
        case .protectedControl: "Protected response — stopped"
        case .rateLimited: "Rate limit encountered — stopped"
        case .serviceUnavailable: "SiriusXM session verification unavailable"
        case .ambiguous: "Session verification ambiguous — stopped"
        case .cancelled: "Session import cancelled"
        }
    }
}

enum FirstPartyCookieFilter {
    static func filter(_ cookies: [HTTPCookie], now: Date = Date()) -> [HTTPCookie] {
        cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let isFirstParty = domain == "siriusxm.com" || domain.hasSuffix(".siriusxm.com")
            let isCurrent = cookie.expiresDate.map { $0 > now } ?? true
            return isFirstParty && isCurrent && cookie.isSecure
        }
    }
}

struct WebSessionHTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
}

struct WebSessionTransport: Sendable {
    let send: @MainActor @Sendable ([HTTPCookie], URLRequest) async throws -> WebSessionHTTPResponse

    static let live = WebSessionTransport { cookies, request in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = true
        guard let cookieStorage = configuration.httpCookieStorage else {
            throw URLError(.cannotCreateFile)
        }
        cookies.forEach(cookieStorage.setCookie)

        let urlSession = URLSession(configuration: configuration)
        defer {
            cookieStorage.removeCookies(since: .distantPast)
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
        string: "https://player.siriusxm.com/rest/v2/experience/modules/resume?OAtrial=false"
    )!

    private let transport: WebSessionTransport

    init(transport: WebSessionTransport = .live) {
        self.transport = transport
    }

    func verify(_ session: VolatileWebSession) async -> WebSessionBridgeResult {
        guard var cookies = session.consumeCookies(), !cookies.isEmpty else {
            return .noFirstPartySession
        }
        defer { cookies.removeAll(keepingCapacity: false) }

        do {
            var request = URLRequest(url: Self.endpoint)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("SiriusMac/0.1 (macOS; native session bridge)", forHTTPHeaderField: "User-Agent")
            request.httpBody = try Self.requestBody()

            let response = try await transport.send(cookies, request)
            let bodyCount = request.httpBody?.count ?? 0
            request.httpBody?.resetBytes(in: 0..<bodyCount)
            return Self.classify(response)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch {
            return .serviceUnavailable
        }
    }

    private static func requestBody() throws -> Data {
        let payload: [String: Any] = [
            "moduleList": [
                "modules": [[
                    "moduleRequest": [
                        "resultTemplate": "web",
                        "deviceInfo": [
                            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                            "platform": "Mac",
                            "sxmAppVersion": "0.1.0",
                            "appRegion": "US",
                            "deviceModel": "SiriusMac",
                            "clientDeviceId": UUID().uuidString,
                            "player": "native",
                            "clientDeviceType": "native",
                        ],
                    ],
                ]],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func classify(_ response: WebSessionHTTPResponse) -> WebSessionBridgeResult {
        switch response.statusCode {
        case 200...299:
            guard let root = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
                return .ambiguous
            }
            let envelope = (root["ModuleListResponse"] as? [String: Any]) ?? root
            return (envelope["status"] as? NSNumber)?.intValue == 1 ? .verified : .rejected
        case 401: return .rejected
        case 403: return .protectedControl
        case 429: return .rateLimited
        case 500...599: return .serviceUnavailable
        default: return .ambiguous
        }
    }
}
