import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Ephemeral native transport")
struct EphemeralSessionTests {
    @Test("the native transport owns a nonpersistent session configuration")
    func configurationHasNoSharedCredentialOrCookieStorage() {
        let configuration = EphemeralURLSessionTransport.makeConfiguration()

        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test("only exact materialized request shapes are eligible for authorization")
    func acceptsOnlyContractRequests() throws {
        #expect(SiriusXMRequestContract.entitlement.path == "/subscription/v1/subscriptions")

        for contract in SiriusXMRequestContract.all where contract.isTransportMaterializable {
            let request = try SiriusXMRequestContract.makeRequest(for: contract, authorization: "synthetic-token")
            #expect(DirectHostPolicy.isAuthorizedRequest(request))
        }

        let invalidRequests = [
            request("http://api.edge-gateway.siriusxm.com/profile/v4/profiles/me"),
            request("https://user@api.edge-gateway.siriusxm.com/profile/v4/profiles/me"),
            request("https://api.edge-gateway.siriusxm.com.example.invalid/profile/v4/profiles/me"),
            request("https://api.edge-gateway.siriusxm.com/unknown"),
            request("https://example.invalid/profile/v4/profiles/me"),
        ]

        for request in invalidRequests {
            #expect(!DirectHostPolicy.isAuthorizedRequest(request))
        }
    }

    @Test("the production redirect callback records attempts and cancels every follow-up")
    func productionRedirectCallbackCancelsEveryFollowUp() {
        let destinations = [
            try! SiriusXMRequestContract.makeRequest(for: .authentication, authorization: "synthetic-token"),
            request("https://example.invalid/not-approved"),
        ]

        for destination in destinations {
            let transport = EphemeralURLSessionTransport()
            let capture = RedirectCompletionCapture()
            let task = URLSession.shared.dataTask(with: URL(string: "https://example.invalid/original")!)
            let response = HTTPURLResponse(
                url: URL(string: "https://example.invalid/original")!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: nil
            )!

            #expect(transport.redirectAttemptCount == 0)
            #expect(transport.hasActiveRequest == false)

            transport.urlSession(
                URLSession.shared,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: destination
            ) { followUpRequest in
                capture.record(followUpRequest, observedAttemptCount: transport.redirectAttemptCount)
            }

            #expect(capture.observedAttemptCount == 1)
            #expect(capture.followUpRequest == nil)
            #expect(transport.redirectAttemptCount == 1)
            #expect(transport.hasActiveRequest == false)
        }
    }

    @Test("cancellation never retries or retains credential-bearing request state")
    func cancellationDoesNotRetry() async {
        await BlockingURLProtocol.controller.reset()
        let configuration = EphemeralURLSessionTransport.makeConfiguration()
        configuration.protocolClasses = [BlockingURLProtocol.self]
        let transport = EphemeralURLSessionTransport(configuration: configuration)
        let credential = AuthenticationCredential(volatileMaterial: Data("synthetic-token".utf8))

        let sendTask = Task {
            do {
                _ = try await transport.send(.authentication, using: credential)
                return SendOutcome.completed
            } catch is CancellationError {
                return SendOutcome.cancelled
            } catch {
                return SendOutcome.unexpectedError
            }
        }

        await BlockingURLProtocol.controller.waitUntilStarted()
        #expect(transport.hasActiveRequest)

        sendTask.cancel()

        #expect(await sendTask.value == .cancelled)
        #expect(transport.hasActiveRequest == false)
        #expect(transport.redirectAttemptCount == 0)
        #expect(await BlockingURLProtocol.controller.startCount == 1)
    }

    private func request(_ value: String) -> URLRequest {
        URLRequest(url: URL(string: value)!)
    }
}

private enum SendOutcome: Sendable, Equatable {
    case completed
    case cancelled
    case unexpectedError
}

private actor BlockingRequestController {
    private var starts = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    var startCount: Int { starts }

    func reset() {
        starts = 0
        startWaiters.removeAll()
    }

    func waitUntilStarted() async {
        guard starts == 0 else { return }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func recordStart() {
        starts += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private final class BlockingURLProtocol: URLProtocol, @unchecked Sendable {
    static let controller = BlockingRequestController()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == SiriusXMRequestContract.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task { await Self.controller.recordStart() }
    }

    override func stopLoading() {}
}

private final class RedirectCompletionCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRequest: URLRequest?
    private var capturedAttemptCount: Int?

    var followUpRequest: URLRequest? {
        lock.withLock { capturedRequest }
    }

    var observedAttemptCount: Int? {
        lock.withLock { capturedAttemptCount }
    }

    func record(_ request: URLRequest?, observedAttemptCount: Int) {
        lock.withLock {
            capturedRequest = request
            capturedAttemptCount = observedAttemptCount
        }
    }
}
