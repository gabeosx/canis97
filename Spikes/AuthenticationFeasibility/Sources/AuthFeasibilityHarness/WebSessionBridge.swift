import AuthFeasibilityCore
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

    /// Gives the one scoped owner of a run temporary access without making the
    /// token storable or printable by the state machine. It is cleared whether
    /// the operation succeeds, fails, or returns a terminal result.
    func consumeForRun<Result>(_ operation: (String) async -> Result) async -> Result? {
        guard let accessToken else { return nil }
        defer { self.accessToken = nil }
        return await operation(accessToken)
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

public enum WebSessionBridgeResult: Equatable, Sendable {
    case authenticated
    case authCookieMissing
    case authCookieMalformed
    case alreadyConsumed
    case rejected
    case protectedControl
    case rateLimited
    case serviceUnavailable
    case malformed
    case httpStatus(Int)
    case cancelled

    private var canonicalOutcome: String {
        switch self {
        case .authenticated: "authenticated"
        case .authCookieMissing: "auth-cookie-missing"
        case .authCookieMalformed: "auth-cookie-malformed"
        case .alreadyConsumed: "session-already-consumed"
        case .rejected: "rejected"
        case .protectedControl: "protected-control"
        case .rateLimited: "rate-limited"
        case .serviceUnavailable: "service-unavailable"
        case .malformed: "malformed"
        case let .httpStatus(code): "http-status-\(code)"
        case .cancelled: "cancelled"
        }
    }

    public var canonicalText: String {
        [
            "Schema: web-session-bridge-v1",
            "Outcome: \(canonicalOutcome)",
            "Credential persistence: none",
            "Phase 1 continuation: blocked",
            "",
        ].joined(separator: "\n")
    }

    public var ownerVisibleText: String {
        switch self {
        case .authenticated: "Web session authenticated natively; entitlement still requires separate verification"
        case .authCookieMissing: "Player login cookie absent — the WebView is not signed in"
        case .authCookieMalformed: "Player login cookie found, but its session token is invalid"
        case .alreadyConsumed: "Web session was already consumed"
        case .rejected: "Imported session was rejected"
        case .protectedControl: "Protected response — stopped"
        case .rateLimited: "Rate limit encountered — stopped"
        case .serviceUnavailable: "SiriusXM session verification unavailable"
        case .malformed: "Native session verification returned an unusable response"
        case let .httpStatus(code): "Native session check returned HTTP \(code)"
        case .cancelled: "Session import cancelled"
        }
    }
}

public enum WebSessionSignOutPresence: Equatable, Sendable {
    case present
    case absent
    case ambiguous
}

/// Restricts sign-out verification to the one allowed cookie name and first-party
/// domain. It intentionally returns only presence semantics and never exposes a value.
enum WebSessionSignOutChecker {
    @MainActor
    static func classify(cookies: [HTTPCookie], now: Date = Date()) -> WebSessionSignOutPresence {
        let matches = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let isCurrent = cookie.expiresDate.map { $0 > now } ?? true
            return cookie.name == "AUTH_TOKEN" && domain == "siriusxm.com" && isCurrent
        }
        return switch matches.count {
        case 0: .absent
        case 1: .present
        default: .ambiguous
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

        let urlSession = URLSession(configuration: configuration, delegate: RedirectRejectingDelegate(), delegateQueue: nil)
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

private final class RedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Consumes one extracted WebKit session and verifies it through SiriusXM's
/// normal resume operation using an ephemeral native URLSession.
@MainActor
struct NativeWebSessionVerifier: Sendable {
    private static let endpoint = URL(
        string: "https://api.edge-gateway.siriusxm.com/profile/v4/profiles/me"
    )!

    private let transport: WebSessionTransport

    init(transport: WebSessionTransport = .live) {
        self.transport = transport
    }

    func verify(_ session: VolatileWebSession) async -> WebSessionBridgeResult {
        guard let accessToken = session.consume() else { return .alreadyConsumed }
        return await verify(accessToken: accessToken)
    }

    func verify(accessToken: String) async -> WebSessionBridgeResult {

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
        case 200...299: return response.body.isEmpty ? .malformed : .authenticated
        case 401: return .rejected
        case 403: return .protectedControl
        case 429: return .rateLimited
        case 500...599: return .serviceUnavailable
        default: return .httpStatus(response.statusCode)
        }
    }
}

public enum EntitlementVerificationResult: Equatable, Sendable {
    case entitled
    case notEntitled
    case malformed
    case rejected
    case protectedControl
    case rateLimited
    case serviceUnavailable
    case httpStatus(Int)
    case cancelled
}

/// A narrowly constructed verifier for a public, byte-canonical entitlement
/// contract. It cannot be created from an unsupported result and has no path to
/// infer entitlement from a profile request.
@MainActor
struct NativeEntitlementVerifier: Sendable {
    private let requestDefinition: EntitlementRequest
    private let successPredicate: EntitlementPredicate
    private let denialPredicate: EntitlementPredicate
    private let transport: WebSessionTransport

    init(contract: EntitlementContract, transport: WebSessionTransport = .live) throws {
        guard contract.status == .supported,
              let request = contract.request,
              let success = contract.successPredicate,
              let denial = contract.denialPredicate else {
            throw ContractError.invalidArtifact
        }
        requestDefinition = request
        successPredicate = success
        denialPredicate = denial
        self.transport = transport
    }

    func verify(accessToken: String) async -> EntitlementVerificationResult {
        guard let url = URL(string: "https://\(requestDefinition.host)\(requestDefinition.path)") else {
            return .malformed
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = requestDefinition.method
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("SiriusMac/0.1 (macOS; entitlement verifier)", forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let response = try await transport.send(request)
            return classify(response)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch {
            return .serviceUnavailable
        }
    }

    private func classify(_ response: WebSessionHTTPResponse) -> EntitlementVerificationResult {
        switch response.statusCode {
        case 200...299:
            guard let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                  let value = stringValue(for: successPredicate.field, in: object) else {
                return .malformed
            }
            if value == successPredicate.value { return .entitled }
            if value == denialPredicate.value { return .notEntitled }
            return .malformed
        case 401: return .rejected
        case 403: return .protectedControl
        case 429: return .rateLimited
        case 500...599: return .serviceUnavailable
        default: return .httpStatus(response.statusCode)
        }
    }

    private func stringValue(for field: String, in object: [String: Any]) -> String? {
        var value: Any = object
        for component in field.split(separator: ".") {
            guard let dictionary = value as? [String: Any], let next = dictionary[String(component)] else { return nil }
            value = next
        }
        return value as? String
    }
}
