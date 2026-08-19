import Foundation
import SiriusXMClient
import Testing

@Test func independentConsumerUsesOnlySemanticCapabilities() async {
    let client = SiriusXMClient()
    #expect(await client.authenticate() == .waitingForAuthenticationComposition)
    #expect(await client.entitlement() == .unavailable)
    #expect(await client.signOut() == .alreadySignedOut)
    #expect(await client.catalog() == .failed(.authenticationUnavailable))
    #expect(await client.metadata() == .unavailable)
    #expect(await client.resolveLiveStream() == .failed(.selectionUnavailable))
}

@Test func credentialDescriptionIsRedacted() {
    let credential = AuthenticationCredential(volatileMaterial: Data([1, 2, 3]))

    #expect(String(describing: credential) == "AuthenticationCredential(redacted)")
    #expect(String(reflecting: credential) == "AuthenticationCredential(redacted)")
}
