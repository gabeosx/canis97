import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Bulk metadata transport and lifecycle", .timeLimit(.minutes(1)))
struct BulkMetadataLifecycleTests {
    @Test("The batch request is one fixed empty-marker GET with ephemeral authorization")
    func fixedRequestContract() throws {
        let credential = try browserCredential(accessToken: "synthetic-token", accessExpiresAt: Date(timeIntervalSince1970: 10_800))
        let request = try #require(FixedMetadataURLSessionTransport.lookaroundRequest(using: credential, clock: "synthetic-clock"))
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "lookaround-cache-prod.streaming.siriusxm.com")
        #expect(request.url?.path == "/playbackservices/v1/live/lookAround")
        #expect(request.url?.query == "delta=")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "x-sxm-clock") == "synthetic-clock")
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test("Many channel identities use exactly one authenticated Lookaround request and no other operation")
    func oneRequestForBatch() async throws {
        let harness = BulkMetadataHarness()
        #expect(await harness.client.authenticate() == .authenticatedPendingEntitlement)
        let ids = ["b", "a", "missing"].map(LiveChannelID.init)
        let request = Task { await harness.client.liveNow(for: ids) }
        await harness.transport.waitForRequests(1)
        await harness.transport.release(0, try lookaroundResponse([
            "a": ["cuts": [lookaroundCut("A")]], "b": ["cuts": [lookaroundCut("B")]],
        ]))
        guard case let .current(snapshot) = await request.value else { Issue.record("expected batch"); return }
        #expect(snapshot.channels.map(\.channelID) == ids)
        #expect(snapshot.observedAt == lookaroundObservation)
        #expect(snapshot.channels[2].state == .unavailable)
        #expect(await harness.transport.requestCount == 1)
        #expect(await harness.transport.artworkCount == 0)
        #expect(await harness.verifier.entitlementCount == 1) // Authentication only; no hidden second request.
    }

    @Test("A later full response replaces missing coverage instead of retaining old metadata")
    func fullReplacement() async throws {
        let harness = BulkMetadataHarness()
        _ = await harness.client.authenticate()
        let first = Task { await harness.client.liveNow(for: [LiveChannelID("a")]) }
        await harness.transport.waitForRequests(1)
        await harness.transport.release(0, try lookaroundResponse(["a": ["cuts": [lookaroundCut("Old")]]]))
        guard case .current = await first.value else { Issue.record("expected first snapshot"); return }
        let second = Task { await harness.client.liveNow(for: [LiveChannelID("a")]) }
        await harness.transport.waitForRequests(2)
        await harness.transport.release(1, try lookaroundResponse([:]))
        #expect(await second.value == .current(LiveNowSnapshot(observedAt: lookaroundObservation, channels: [LiveNowChannel(channelID: LiveChannelID("a"), state: .unavailable)])))
    }

    @Test("A newer refresh supersedes a late old completion, including the legacy projection")
    func supersededRefresh() async throws {
        let harness = BulkMetadataHarness()
        _ = await harness.client.authenticate()
        let first = Task { await harness.client.liveNow(for: [LiveChannelID("a")]) }
        await harness.transport.waitForRequests(1)
        let second = Task { await harness.client.metadata(for: LiveChannelID("b")) }
        await harness.transport.waitForRequests(2)
        await harness.transport.release(1, try lookaroundResponse(["b": ["cuts": [lookaroundCut("Current")]]]))
        guard case let .current(value) = await second.value else { Issue.record("expected current selection"); return }
        #expect(value.program?.title == "Current")
        await harness.transport.release(0, try lookaroundResponse(["a": ["cuts": [lookaroundCut("Old")]]]))
        #expect(await first.value == .failed(.superseded))
    }

    @Test("Sign-out rejects an outstanding response and subsequent calls do not request metadata")
    func signOut() async throws {
        let harness = BulkMetadataHarness()
        _ = await harness.client.authenticate()
        let request = Task { await harness.client.liveNow(for: [LiveChannelID("a")]) }
        await harness.transport.waitForRequests(1)
        #expect(await harness.client.signOut() == .signedOut)
        await harness.transport.release(0, try lookaroundResponse([:]))
        #expect(await request.value == .failed(.superseded))
        #expect(await harness.client.liveNow(for: [LiveChannelID("a")]) == .failed(.authenticationUnavailable))
        #expect(await harness.transport.requestCount == 1)
    }

    @Test("Client invalidation closes the window while sign-out is suspended on a collaborator")
    func signOutBeforeFetcherInvalidation() async throws {
        let resolver = BulkBlockingResolver()
        let harness = BulkMetadataHarness(resolver: resolver)
        _ = await harness.client.authenticate()
        let request = Task { await harness.client.liveNow(for: [LiveChannelID("a")]) }
        await harness.transport.waitForRequests(1)
        let signOut = Task { await harness.client.signOut() }
        await resolver.waitUntilInvalidating()
        #expect(await harness.client.liveNow(for: []) == .failed(.superseded))
        #expect(await harness.client.metadata(for: LiveChannelID("b")) == .failed(.superseded))
        #expect(await harness.transport.requestCount == 1)
        await harness.transport.release(0, try lookaroundResponse([:]))
        #expect(await request.value == .failed(.superseded))
        await resolver.release()
        #expect(await signOut.value == .signedOut)
    }

    @Test("Reauthentication with the same clock instant still retires the prior session")
    func reauthenticationAtIdenticalTime() async throws {
        let harness = BulkMetadataHarness()
        #expect(await harness.session.attemptSession() == .active)
        let request = Task { await harness.fetcher.liveNow(for: [LiveChannelID("a")]) }
        await harness.transport.waitForRequests(1)
        #expect(await harness.session.attemptSession() == .active)
        await harness.transport.release(0, try lookaroundResponse([:]))
        #expect(await request.value == .failed(.superseded))
    }

    @Test("Catalog refresh invalidates old metadata even when the refresh fails")
    func catalogGeneration() async throws {
        let harness = BulkMetadataHarness()
        _ = await harness.client.authenticate()
        let request = Task { await harness.client.liveNow(for: [LiveChannelID("a")]) }
        await harness.transport.waitForRequests(1)
        #expect(await harness.client.catalog() == .failed(.unavailable))
        await harness.transport.release(0, try lookaroundResponse([:]))
        #expect(await request.value == .failed(.superseded))
    }

    @Test("Cancellation closes late success without depending on transport cooperation")
    func cancellationDuringRequest() async throws {
        let harness = BulkMetadataHarness()
        _ = await harness.client.authenticate()
        let request = Task { await harness.client.liveNow(for: [LiveChannelID("a")]) }
        await harness.transport.waitForRequests(1)
        request.cancel()
        await harness.transport.release(0, try lookaroundResponse([:]))
        #expect(await request.value == .failed(.cancelled))
        #expect(await harness.transport.requestCount == 1)
    }

    @Test("Already cancelled demand and unauthenticated demand never reach transport")
    func cancelledAndUnauthenticatedEntry() async {
        let harness = BulkMetadataHarness()
        #expect(await harness.client.liveNow(for: []) == .failed(.authenticationUnavailable))
        _ = await harness.client.authenticate()
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await harness.client.liveNow(for: [LiveChannelID("a")])
        }
        #expect(await request.value == .failed(.cancelled))
        #expect(await harness.transport.requestCount == 0)
    }

    @Test("Confirmed access loss invalidates sibling responses and closes future requests")
    func accessLoss() async throws {
        for status in [401, 403] {
            let harness = BulkMetadataHarness()
            _ = await harness.client.authenticate()
            let sibling = CurrentSessionMetadataFetcher(sessionCoordinator: harness.session, transport: harness.transport)
            let first = Task { await harness.fetcher.liveNow(for: [LiveChannelID("a")]) }
            await harness.transport.waitForRequests(1)
            let denial = Task { await sibling.liveNow(for: [LiveChannelID("b")]) }
            await harness.transport.waitForRequests(2)
            await harness.transport.release(1, NativeTransportResponse(statusCode: status, contentType: "application/json", body: Data()))
            #expect(await denial.value == .failed(status == 401 ? .authenticationUnavailable : .notEntitled))
            await harness.transport.release(0, try lookaroundResponse([:]))
            #expect(await first.value == .failed(.superseded))
            #expect(await harness.session.entitlementAvailability != .entitled)
            #expect(await harness.fetcher.liveNow(for: []) == .failed(status == 401 ? .authenticationUnavailable : .notEntitled))
            #expect(await harness.transport.requestCount == 2)
        }
    }

    @Test("Explicit entitlement revalidation loss also retires pending metadata")
    func revalidatedEntitlementLoss() async throws {
        let harness = BulkMetadataHarness()
        _ = await harness.client.authenticate()
        let request = Task { await harness.fetcher.liveNow(for: [LiveChannelID("a")]) }
        await harness.transport.waitForRequests(1)
        await harness.verifier.denyEntitlement()
        let result = await harness.session.withCurrentEntitledCredential { _ in true }
        guard case .failed = result else { Issue.record("entitlement should fail"); return }
        await harness.transport.release(0, try lookaroundResponse([:]))
        #expect(await request.value == .failed(.superseded))
    }

    @Test("Transient failures do not retry or poison a later explicit refresh")
    func transientFailure() async throws {
        let harness = BulkMetadataHarness()
        _ = await harness.client.authenticate()
        let first = Task { await harness.client.liveNow(for: []) }
        await harness.transport.waitForRequests(1)
        await harness.transport.release(0, NativeTransportResponse(statusCode: 429, contentType: "application/json", body: Data()))
        #expect(await first.value == .failed(.rateLimited))
        #expect(await harness.transport.requestCount == 1)
        #expect(await harness.session.entitlementAvailability == .entitled)
        let retry = Task { await harness.client.liveNow(for: []) }
        await harness.transport.waitForRequests(2)
        await harness.transport.release(1, try lookaroundResponse([:]))
        #expect(await retry.value == .current(LiveNowSnapshot(observedAt: lookaroundObservation, channels: [])))
    }
}

private struct BulkMetadataHarness {
    let session: SessionCoordinator
    let transport = BulkControlledTransport()
    let verifier = BulkVerifier()
    let fetcher: CurrentSessionMetadataFetcher
    let client: SiriusXMClient

    init(resolver: any LiveStreamResolving = UnavailableLiveStreamResolver()) {
        session = SessionCoordinator(credentialSource: BulkCredentialSource(), authenticationVerifier: verifier,
            entitlementVerifier: verifier, credentialStore: BulkCredentialStore(), clock: BulkSessionClock(), diagnostics: BulkDiagnostics())
        fetcher = CurrentSessionMetadataFetcher(sessionCoordinator: session, transport: transport, responseObservationClock: BulkObservationClock())
        client = SiriusXMClient(sessionCoordinator: session, catalogRefresher: BulkCatalogRefresher(), liveStreamResolver: resolver, metadataFetcher: fetcher)
    }
}

private actor BulkControlledTransport: FixedMetadataTransporting {
    private(set) var requestCount = 0
    private(set) var artworkCount = 0
    private var responses: [Int: CheckedContinuation<NativeTransportResponse, Never>] = [:]
    private var starts: [(Int, CheckedContinuation<Void, Never>)] = []

    func lookaround(using _: AuthenticationCredential) async -> NativeTransportResponse {
        let index = requestCount
        requestCount += 1
        return await withCheckedContinuation { continuation in
            responses[index] = continuation
            let ready = starts.filter { $0.0 <= requestCount }
            starts.removeAll { $0.0 <= requestCount }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requestCount >= count { return }
        await withCheckedContinuation { starts.append((count, $0)) }
    }

    func release(_ index: Int, _ response: NativeTransportResponse) {
        responses.removeValue(forKey: index)?.resume(returning: response)
    }

    func artwork(for _: ChannelArtworkReference) async -> NativeTransportResponse {
        artworkCount += 1
        return NativeTransportResponse(statusCode: 0, contentType: nil, body: Data(), transportFailed: true)
    }
}

private actor BulkVerifier: NativeAuthenticationVerifying, NativeEntitlementVerifying {
    private(set) var entitlementCount = 0
    private var denied = false
    func denyEntitlement() { denied = true }
    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        NativeTransportResponse(statusCode: 200, contentType: "application/json", body: SanitizedNativeResponseFixtures.profileV4Authenticated)
    }
    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        entitlementCount += 1
        return NativeTransportResponse(statusCode: denied ? 401 : 200, contentType: "application/json", body: denied ? Data() : SanitizedNativeResponseFixtures.subscriptionV1Active)
    }
}

private struct BulkCredentialSource: CredentialSource {
    func credential() async -> AuthenticationCredential? { AuthenticationCredential(volatileMaterial: Data("synthetic".utf8)) }
}
private struct BulkCredentialStore: CredentialStore {
    func save(_: AuthenticationCredential) async throws {}
    func erase() async throws {}
}
private struct BulkSessionClock: SessionClock { func now() -> Date { Date(timeIntervalSince1970: 1) } }
private struct BulkObservationClock: MetadataResponseObservationClock { func now() -> Date { lookaroundObservation } }
private struct BulkDiagnostics: SessionDiagnostics { func record(_: SessionDiagnosticEvent) async {} }
private struct BulkCatalogRefresher: CatalogRefreshing {
    func refresh() async -> LiveCatalogSnapshotResult { LiveCatalogSnapshotResult(snapshot: nil, failure: .unavailable) }
}

private actor BulkBlockingResolver: LiveStreamResolving {
    private var invalidation: CheckedContinuation<Void, Never>?
    private var start: CheckedContinuation<Void, Never>?
    private var started = false
    func resolveLiveStream(for _: LiveChannelID) async -> LiveStreamResolutionAvailability { .unavailable }
    func invalidate() async {
        await withCheckedContinuation { continuation in
            invalidation = continuation
            started = true
            start?.resume()
            start = nil
        }
    }
    func waitUntilInvalidating() async {
        if started { return }
        await withCheckedContinuation { start = $0 }
    }
    func release() { invalidation?.resume(); invalidation = nil }
}
