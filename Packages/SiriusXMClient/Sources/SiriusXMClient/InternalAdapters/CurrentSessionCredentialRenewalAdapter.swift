import Foundation

/// Closed outcomes from the fixed current-session renewal adapter. These cases
/// intentionally carry no URL, header, body, token, account, or device data.
@_spi(AppIntegration)
public enum BrowserCredentialNativeRenewalFailure: String, Sendable, Equatable {
    case renewalAuthorityUnavailable = "renewal-authority-unavailable"
    case renewalAuthorityExpired = "renewal-authority-expired"
    case transportFailed = "transport-failed"
    case authorizationRejected = "authorization-rejected"
    case rateLimited = "rate-limited"
    case serverUnavailable = "server-unavailable"
    case redirectRejected = "redirect-rejected"
    case unsupportedResponse = "unsupported-response"
    case replacementUnusable = "replacement-unusable"
    case cancelled
}

@_spi(AppIntegration)
public enum BrowserCredentialNativeRenewalResult: Sendable {
    case refreshed(AuthenticationCredential)
    case failed(BrowserCredentialNativeRenewalFailure)
}

/// Renews a current SiriusXM browser session through the exact Web 7.131.0
/// contract: one HttpOnly refresh cookie, no Authorization header, a fixed
/// null-location body, and a rotated refresh cookie in the response.
@_spi(AppIntegration)
public struct SiriusXMCurrentCredentialRenewalDriver: Sendable {
    private let transport: any CurrentSessionCredentialRenewalTransporting
    private let now: @Sendable () -> Date

    public init() {
        transport = CurrentSessionCredentialRenewalURLSessionTransport()
        now = Date.init
    }

    init(
        transport: any CurrentSessionCredentialRenewalTransporting,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.now = now
    }

    public func refresh(_ credential: AuthenticationCredential) async -> BrowserCredentialNativeRenewalResult {
        let referenceDate = now()
        let renewalMaterial: SessionRenewalMaterial
        switch credential.sessionRenewalMaterial(at: referenceDate) {
        case let .ready(value):
            renewalMaterial = value
        case .expired:
            return .failed(.renewalAuthorityExpired)
        case .unsupported:
            return .failed(.renewalAuthorityUnavailable)
        }

        guard !Task.isCancelled else { return .failed(.cancelled) }
        let result = await transport.refreshSession(using: renewalMaterial)
        guard !Task.isCancelled else { return .failed(.cancelled) }

        let response = result.response
        if response.redirectLocation != nil {
            return .failed(.redirectRejected)
        }
        if let failure = response.transportFailure {
            return failure == .cancelled ? .failed(.cancelled) : .failed(.transportFailed)
        }
        switch response.statusCode {
        case 200 ..< 300:
            break
        case 401, 403:
            return .failed(.authorizationRejected)
        case 429:
            return .failed(.rateLimited)
        case 500 ..< 600:
            return .failed(.serverUnavailable)
        default:
            return .failed(.unsupportedResponse)
        }
        guard response.contentType?.lowercased().hasPrefix("application/json") == true else {
            return .failed(.unsupportedResponse)
        }
        guard let replacementRefreshCookie = result.replacementRefreshCookieValue,
              let replacement = credential.replacingBrowserSession(
                  with: response.body,
                  sessionRefreshCookieValue: replacementRefreshCookie,
                  at: referenceDate
              ) else {
            return .failed(.replacementUnusable)
        }
        return .refreshed(replacement)
    }
}

struct CurrentSessionCredentialRenewalTransportResponse: Sendable {
    let response: NativeTransportResponse
    let replacementRefreshCookieValue: String?
}

protocol CurrentSessionCredentialRenewalTransporting: Sendable {
    func refreshSession(using renewalMaterial: SessionRenewalMaterial) async -> CurrentSessionCredentialRenewalTransportResponse
}

enum CurrentSessionCredentialRenewalRequestFactory {
    static let host = SiriusXMRequestContract.host
    static let path = "/session/v1/sessions/refresh"
    static let cookieName = "sxm-refresh-token"

    static func makeRequest(renewalMaterial: SessionRenewalMaterial, clock: String) -> URLRequest? {
        guard isLogicalClock(clock),
              let url = URL(string: "https://\(host)\(path)"),
              let body = try? JSONSerialization.data(
                  withJSONObject: ["location": NSNull()],
                  options: [.sortedKeys]
              )
        else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch renewalMaterial {
        case let .sessionRefreshCookie(value):
            guard isSafeCookieValue(value) else { return nil }
            request.setValue("\(cookieName)=\(value)", forHTTPHeaderField: "Cookie")
        case let .bearerRefreshToken(value):
            guard isSafeBearerValue(value) else { return nil }
            request.setValue("Bearer \(value)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(clock, forHTTPHeaderField: "x-sxm-clock")
        return request
    }

    static func isSafeCookieValue(_ value: String) -> Bool {
        !value.isEmpty &&
            value.utf8.count <= 8_192 &&
            !value.contains(";") &&
            !value.contains(where: { $0.isWhitespace || $0.isNewline })
    }

    private static func isSafeBearerValue(_ value: String) -> Bool {
        !value.isEmpty &&
            value.utf8.count <= 8_192 &&
            !value.contains(where: { $0.isWhitespace || $0.isNewline })
    }

    private static func isLogicalClock(_ value: String) -> Bool {
        guard value.first == "[", value.last == "]" else { return false }
        let components = value.dropFirst().dropLast().split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        return components.count == 2 && components.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48 ... 57).contains($0) }
        }
    }
}

enum SessionRefreshCookieHeaderParser {
    static func value(
        from response: HTTPURLResponse,
        now: Date
    ) -> String? {
        guard let responseURL = response.url,
              responseURL.scheme == "https",
              responseURL.host?.lowercased() == CurrentSessionCredentialRenewalRequestFactory.host,
              responseURL.path == CurrentSessionCredentialRenewalRequestFactory.path,
              let setCookie = response.allHeaderFields.first(where: {
                  String(describing: $0.key).caseInsensitiveCompare("Set-Cookie") == .orderedSame
              }).map({ String(describing: $0.value) }) else {
            return nil
        }

        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": setCookie],
            for: responseURL
        )
        guard cookies.count == 1,
              let cookie = cookies.first,
              cookie.name == CurrentSessionCredentialRenewalRequestFactory.cookieName,
              normalizedDomain(cookie.domain) == CurrentSessionCredentialRenewalRequestFactory.host,
              cookie.path == CurrentSessionCredentialRenewalRequestFactory.path,
              cookie.isHTTPOnly,
              cookie.isSecure,
              cookie.expiresDate.map({ $0 > now }) == true,
              CurrentSessionCredentialRenewalRequestFactory.isSafeCookieValue(cookie.value)
        else {
            return nil
        }
        return cookie.value
    }

    private static func normalizedDomain(_ domain: String) -> String {
        String(domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .drop(while: { $0 == "." }))
    }
}

private final class CurrentSessionCredentialRenewalURLSessionTransport:
    NSObject,
    CurrentSessionCredentialRenewalTransporting,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    private let clock = CurrentSessionRenewalLogicalClock()
    private lazy var session = URLSession(
        configuration: Self.makeConfiguration(),
        delegate: self,
        delegateQueue: nil
    )

    func refreshSession(using renewalMaterial: SessionRenewalMaterial) async -> CurrentSessionCredentialRenewalTransportResponse {
        guard let request = CurrentSessionCredentialRenewalRequestFactory.makeRequest(
            renewalMaterial: renewalMaterial,
            clock: clock.next()
        ) else {
            return Self.failed
        }

        do {
            let (body, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return Self.failed }
            let nativeResponse = NativeTransportResponse(
                statusCode: response.statusCode,
                contentType: response.value(forHTTPHeaderField: "Content-Type"),
                body: body,
                redirectLocation: (300 ..< 400).contains(response.statusCode) ? "blocked" : nil
            )
            return CurrentSessionCredentialRenewalTransportResponse(
                response: nativeResponse,
                replacementRefreshCookieValue: SessionRefreshCookieHeaderParser.value(
                    from: response,
                    now: Date()
                )
            )
        } catch {
            return CurrentSessionCredentialRenewalTransportResponse(
                response: NativeTransportResponse(
                    statusCode: 0,
                    contentType: nil,
                    body: Data(),
                    transportFailure: SafeTransportFailure(error: error)
                ),
                replacementRefreshCookieValue: nil
            )
        }
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    private static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }

    private static let failed = CurrentSessionCredentialRenewalTransportResponse(
        response: NativeTransportResponse(
            statusCode: 0,
            contentType: nil,
            body: Data(),
            transportFailure: .other
        ),
        replacementRefreshCookieValue: nil
    )
}

private final class CurrentSessionRenewalLogicalClock: @unchecked Sendable {
    private let lock = NSLock()
    private var counter = -1

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        counter = counter == Int.max ? 0 : counter + 1
        return "[0,\(counter)]"
    }
}
