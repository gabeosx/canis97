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

    @Test("redirect validation cancels all follow-up requests")
    func redirectDriftCancelsBeforeFollowUp() {
        let transport = EphemeralURLSessionTransport()
        let drift = request("https://example.invalid/not-approved")

        #expect(transport.redirectDecision(for: drift) == .cancel)
        #expect(transport.followUpRequestCount == 0)
    }

    @Test("cancellation never retries or retains credential-bearing request state")
    func cancellationDoesNotRetry() async {
        let transport = EphemeralURLSessionTransport()

        transport.cancelCurrentRequestForTesting()

        #expect(transport.followUpRequestCount == 0)
        #expect(transport.hasActiveRequest == false)
    }

    private func request(_ value: String) -> URLRequest {
        URLRequest(url: URL(string: value)!)
    }
}
