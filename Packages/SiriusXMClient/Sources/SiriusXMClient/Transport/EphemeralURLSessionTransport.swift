import Foundation

/// A client-owned transport that never shares cookies, credentials, cache, or redirects.
final class EphemeralURLSessionTransport: NSObject, SessionTransport, @unchecked Sendable {
    enum RedirectDecision: Sendable, Equatable {
        case cancel
    }

    private let requestState = RequestState()
    private let configuration: URLSessionConfiguration
    private lazy var session = URLSession(
        configuration: configuration,
        delegate: self,
        delegateQueue: nil
    )

    var redirectAttemptCount: Int { requestState.redirectAttemptCount }
    var hasActiveRequest: Bool { requestState.hasActiveRequest }

    override init() {
        configuration = Self.makeConfiguration()
        super.init()
    }

    /// Internal test seam for deterministic transport behavior without a live network.
    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
        super.init()
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }

    func send(
        _ operation: SiriusXMRequestContract,
        using credential: AuthenticationCredential
    ) async throws -> NativeTransportResponse {
        try Task.checkCancellation()
        let request = try SiriusXMRequestContract.makeRequest(for: operation, using: credential)
        guard DirectHostPolicy.isAuthorizedRequest(request) else {
            throw URLError(.badURL)
        }

        requestState.begin(request)
        defer { requestState.clear() }

        let body: Data
        let response: URLResponse
        do {
            (body, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return NativeTransportResponse(
            statusCode: response.statusCode,
            contentType: response.value(forHTTPHeaderField: "Content-Type"),
            body: body,
            redirectLocation: response.value(forHTTPHeaderField: "Location")
        )
    }

    func redirectDecision(for request: URLRequest) -> RedirectDecision {
        _ = DirectHostPolicy.isContractRequest(request)
        return .cancel
    }

    func cancelCurrentRequestForTesting() {
        requestState.clear()
    }
}

extension EphemeralURLSessionTransport: URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        requestState.recordRedirectAttempt()
        _ = redirectDecision(for: request)
        completionHandler(nil)
    }
}

private final class RequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeRequest = false
    private var redirects = 0

    var redirectAttemptCount: Int {
        lock.withLock { redirects }
    }

    var hasActiveRequest: Bool {
        lock.withLock { activeRequest }
    }

    func begin(_: URLRequest) {
        lock.withLock { activeRequest = true }
    }

    func clear() {
        lock.withLock { activeRequest = false }
    }

    func recordRedirectAttempt() {
        lock.withLock { redirects += 1 }
    }
}
