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

    @Test("only exact settled request shapes are eligible for authorization")
    func acceptsOnlyContractRequests() throws {
        for contract in SiriusXMRequestContract.all {
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
        let transport = EphemeralURLSessionTransport()

        transport.cancelCurrentRequestForTesting()

        #expect(transport.redirectAttemptCount == 0)
        #expect(transport.hasActiveRequest == false)
    }

    private func request(_ value: String) -> URLRequest {
        URLRequest(url: URL(string: value)!)
    }
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
