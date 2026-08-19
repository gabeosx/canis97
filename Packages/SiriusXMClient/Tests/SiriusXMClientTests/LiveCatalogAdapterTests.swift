import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Provider-neutral live catalog contracts")
struct LiveCatalogAdapterTests {

    @Test("supported live operations remain fixed, first-party, and non-generic")
    func supportedOperationsStayFixed() {
        let operations = SiriusXMRequestContract.liveListeningOperations

        #expect(operations.map(\.operationID) == [
            "catalog",
            "tune",
            "playback-key",
            "live-update",
            "channel-peek",
            "stream-enforcement",
        ])
        #expect(operations.map(\.method) == ["GET", "POST", "GET", "POST", "GET", "GET"])
        #expect(operations.map(\.pathTemplate) == [
            "/browse/v1/pages/curated-grouping/403ab6a5-d3c9-4c2a-a722-a94a6a5fd056",
            "/playback/play/v1/tuneSource",
            "/playback/key/v1/{keyId}",
            "/playback/play/v1/liveUpdate",
            "/channel-guide/v1/channel/{channelId}/peek",
            "/playback/stream-enforcement/v1/status",
        ])
        #expect(operations.allSatisfy { $0.host == "api.edge-gateway.siriusxm.com" })
        #expect(SiriusXMRequestContract.opaqueMediaDeliveryHost == "live-akc-prod-device.streaming.siriusxm.com")
        #expect(!SiriusXMRequestContract.all.contains { $0.operationID == "media-resource" })
    }

    @Test("playback-key decoding accepts only the recorded opaque two-string shape after preflight")
    func playbackKeyDecoderFailsClosed() {
        let accepted = NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"keyId":"fixture-key-id","key":"fixture-key-material"}"#.utf8)
        )
        let malformed = NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"keyId":"fixture-key-id","unexpected":"fixture-value"}"#.utf8)
        )
        let control = NativeTransportResponse(
            statusCode: 403,
            contentType: "application/json",
            body: Data(#"{"fixture_marker":"blocked"}"#.utf8)
        )

        #expect(LiveListeningAdapter.inspectPlaybackKey(accepted) == .accepted)
        #expect(LiveListeningAdapter.inspectPlaybackKey(malformed) == .unsupported(.playbackKeyUnexpectedShape))
        #expect(LiveListeningAdapter.inspectPlaybackKey(control) == .unsupported(.rejected))
    }

    @Test("playback-key preflight stops redirects, controls, and non-JSON before shape inspection")
    func playbackKeyPreflightStopsUnsafeInputs() {
        let redirect = NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"keyId":"fixture-key-id","key":"fixture-key-material"}"#.utf8),
            redirectLocation: "fixture-redirect"
        )
        let html = NativeTransportResponse(
            statusCode: 200,
            contentType: "text/html",
            body: Data("fixture-html".utf8)
        )
        let challenge = NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"challenge":"captcha"}"#.utf8)
        )

        #expect(LiveListeningAdapter.inspectPlaybackKey(redirect) == .unsupported(.redirectDrift))
        #expect(LiveListeningAdapter.inspectPlaybackKey(html) == .unsupported(.contentTypeHTML))
        #expect(LiveListeningAdapter.inspectPlaybackKey(challenge) == .unsupported(.challengeRequired))
    }

    @Test("tune semantics include only the recorded non-secret values and clock shape")
    func tuneBodyContractStaysBounded() {
        #expect(SiriusXMRequestContract.tune.bodyContract.fixedSemantics == [
            "type": .string("channel-linear"),
            "hlsVersion": .string("V3"),
            "manifestVariant": .string("WEB"),
            "mtcVersion": .string("V2"),
            "trackResumeSupported": .boolean(false),
            "x-sxm-clock": .epochCounter,
        ])
        #expect(SiriusXMRequestContract.liveUpdate.bodyContract.fixedSemantics == [
            "channelId": .opaqueValue,
            "startTimestamp": .opaqueValue,
            "endTimestamp": .opaqueValue,
        ])
    }

    @Test("only explicitly linear classifications enter a stable ordered catalog")
    func filtersAndOrdersSemanticCandidates() {
        let adapter = LiveCatalogAdapter()
        let catalog = adapter.makeSnapshot(
            from: [
                LiveCatalogCandidate(id: LiveChannelID("fixture-echo"), title: "Echo", displayNumber: 15, category: "Music", classification: .appLinear),
                LiveCatalogCandidate(id: LiveChannelID("fixture-bravo"), title: "Bravo", displayNumber: 2, category: "News", classification: .standardLinear),
                LiveCatalogCandidate(id: LiveChannelID("fixture-charlie"), title: "Charlie", displayNumber: 9, category: "Music", classification: .nonlinear),
                LiveCatalogCandidate(id: LiveChannelID("fixture-alpha"), title: "Alpha", displayNumber: 3, category: "News", classification: .ambiguous),
            ],
            freshness: .fresh
        )

        #expect(catalog.channels.map(\.id) == [LiveChannelID("fixture-echo"), LiveChannelID("fixture-bravo")])
        #expect(catalog.channels.map(\.category) == ["Music", "News"])
    }

    @Test("a retained catalog becomes stale browsing data and never authorizes playback")
    func cachedCatalogHasNoPlaybackAuthority() {
        let adapter = LiveCatalogAdapter()
        let fresh = adapter.makeSnapshot(
            from: [
                LiveCatalogCandidate(id: LiveChannelID("fixture-cached"), title: "Cached", displayNumber: 1, category: "Talk", classification: .standardLinear),
            ],
            freshness: .fresh
        )

        let stale = adapter.retainingForBrowsing(fresh)

        #expect(stale.freshness == .stale)
        #expect(stale.channels == fresh.channels)
        #expect(stale.allowsPlaybackAuthorization == false)
    }
}

@Suite("Entitled semantic catalog snapshots")
struct EntitledLiveCatalogSnapshotTests {
    @Test("only entitled standard and app-only linear records survive")
    func filtersOnlyEntitledLinearCandidates() {
        let result = LiveCatalogAdapter.snapshot(
            from: [
                fixture(identity: "fixture-standard", entity: .channelLinear, entitlement: .entitledStandard),
                fixture(identity: "fixture-app", entity: .channelLinear, entitlement: .entitledAppOnly),
                fixture(identity: "fixture-xtra", entity: .xtra, entitlement: .entitledStandard),
                fixture(identity: "fixture-replay", entity: .replay, entitlement: .entitledStandard),
                fixture(identity: "fixture-on-demand", entity: .onDemand, entitlement: .entitledStandard),
                fixture(identity: "fixture-unentitled", entity: .channelLinear, entitlement: .notEntitled),
            ]
        )

        #expect(result.snapshot?.channels.map(\.id) == [
            LiveChannelID("fixture-app"),
            LiveChannelID("fixture-standard"),
        ])
        #expect(result.failure == nil)
    }

    @Test("identity is mandatory while presentation is independently optional and an empty collection is valid")
    func preservesOptionalPresentationAndAcceptsEmptyCollection() {
        let optional = LiveCatalogAdapter.snapshot(
            from: [fixture(identity: "fixture-id", number: nil, name: nil, description: nil, category: nil, artwork: nil)]
        )
        let empty = LiveCatalogAdapter.snapshot(from: [])

        let channel = try! #require(optional.snapshot?.channels.first)
        #expect(channel.id == LiveChannelID("fixture-id"))
        #expect(channel.displayNumber == nil)
        #expect(channel.name == nil)
        #expect(channel.description == nil)
        #expect(channel.category == nil)
        #expect(channel.artwork == nil)
        #expect(empty.snapshot?.channels.isEmpty == true)
        #expect(empty.failure == nil)
    }

    @Test("missing collections and malformed or ambiguous candidate data fail closed")
    func rejectsInvalidCatalogInputs() {
        let invalidInputs: [LiveCatalogSnapshotResult] = [
            LiveCatalogAdapter.snapshot(from: nil),
            LiveCatalogAdapter.snapshot(from: [fixture(identity: "", entity: .channelLinear, entitlement: .entitledStandard)]),
            LiveCatalogAdapter.snapshot(from: [fixture(identity: "fixture-fraction", number: 12.5)]),
            LiveCatalogAdapter.snapshot(from: [fixture(identity: "fixture-overflow", number: Double.greatestFiniteMagnitude)]),
            LiveCatalogAdapter.snapshot(from: [fixture(identity: "fixture-unknown-entity", entity: .unknown, entitlement: .entitledStandard)]),
            LiveCatalogAdapter.snapshot(from: [fixture(identity: "fixture-unknown-entitlement", entity: .channelLinear, entitlement: .unknown)]),
        ]

        #expect(invalidInputs.allSatisfy { $0.snapshot == nil && $0.failure != nil })
        #expect(LiveListeningAdapter.inspectCatalogPreflight(NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data("fixture".utf8),
            redirectLocation: "fixture-redirect"
        )) == .unsupported(.redirectDrift))
    }

    @Test("exact duplicates collapse while conflicting identities fail")
    func handlesDuplicateIdentitiesDeterministically() {
        let duplicate = fixture(identity: "fixture-duplicate", number: 7, name: "Duplicate", category: "Music")
        let collapsed = LiveCatalogAdapter.snapshot(from: [duplicate, duplicate])
        let conflicting = LiveCatalogAdapter.snapshot(from: [
            duplicate,
            fixture(identity: "fixture-duplicate", number: 8, name: "Conflict", category: "Music"),
        ])

        #expect(collapsed.snapshot?.channels.map(\.id) == [LiveChannelID("fixture-duplicate")])
        #expect(collapsed.failure == nil)
        #expect(conflicting.snapshot == nil)
        #expect(conflicting.failure == .conflictingIdentity)
    }

    @Test("category number name and opaque identity establish the stable order")
    func ordersCandidatesWithoutLossyUnicodeHandling() {
        let decomposed = "Cafe\u{301}"
        let composed = "Café"
        let result = LiveCatalogAdapter.snapshot(from: [
            fixture(identity: "fixture-z", number: 10, name: "Zulu", category: "Music"),
            fixture(identity: "fixture-b", number: 2, name: composed, category: "Music"),
            fixture(identity: "fixture-a", number: 2, name: decomposed, category: "Music"),
            fixture(identity: "fixture-news", number: 1, name: "News", category: "News"),
        ])

        #expect(result.snapshot?.channels.map(\.id) == [
            LiveChannelID("fixture-a"),
            LiveChannelID("fixture-b"),
            LiveChannelID("fixture-z"),
            LiveChannelID("fixture-news"),
        ])
        #expect(result.snapshot?.channels.map(\.name).contains(composed) == true)
        #expect(result.snapshot?.channels.map(\.name).contains(decomposed) == true)
    }

    @Test("a prior snapshot becomes explicitly stale after a refresh failure and never authorizes tuning")
    func retainsLastValidSnapshotOnlyForBrowsing() {
        let fresh = try! #require(LiveCatalogAdapter.snapshot(from: [fixture(identity: "fixture-last-valid")]).snapshot)
        let stale = LiveCatalogAdapter.withStaleSnapshot(fresh, after: .unsupportedResponse)

        #expect(stale.snapshot?.freshness == .stale)
        #expect(stale.failure == .unsupportedResponse)
        #expect(stale.snapshot?.allowsPlaybackAuthorization == false)
        #expect(LiveCatalogAdapter.withStaleSnapshot(nil, after: .unsupportedResponse).snapshot == nil)
    }

    private func fixture(
        identity: String,
        number: Double? = 1,
        name: String? = "Fixture Channel",
        description: String? = "Fixture description",
        category: String? = "Music",
        artwork: ChannelArtworkReference? = ChannelArtworkReference(),
        entity: CatalogEntityKind = .channelLinear,
        entitlement: ChannelEntitlement = .entitledStandard
    ) -> LiveCatalogCandidate {
        LiveCatalogCandidate(
            identity: identity,
            displayNumber: number,
            name: name,
            description: description,
            category: category,
            artwork: artwork,
            entity: entity,
            entitlement: entitlement
        )
    }
}

@Suite("Fixed current-session catalog refresh")
struct FixedCatalogRefreshTests {
    @Test("the fixed initial-page decoder admits only matching standard and app-only linear play capabilities")
    func decodesOnlyExplicitCurrentPlayCapabilities() {
        let result = FixedCatalogResponseDecoder.decode(
            NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json; charset=utf-8",
                body: fixturePage(items: [
                    item(id: "fixture-standard", connectivity: "ip-and-sat"),
                    item(id: "fixture-app-only", connectivity: "ip"),
                    item(id: "fixture-xtra", entityType: "channel-xtra", connectivity: "ip"),
                ])
            )
        )

        #expect(result.snapshot?.channels.map(\.id) == [
            LiveChannelID("fixture-app-only"),
            LiveChannelID("fixture-standard"),
        ])
        #expect(result.failure == nil)
    }

    @Test("missing, malformed, or mismatched capability evidence fails closed while Xtra remains excluded")
    func rejectsUnsupportedOrMalformedCandidates() {
        let unsupported = [
            item(id: "fixture-mismatch", playID: "fixture-other"),
            item(id: "fixture-missing-play", includePlay: false),
            item(id: "fixture-wrong-connectivity", connectivity: "sat"),
            item(id: "fixture-fraction", channelNumber: 7.5),
        ]

        for candidate in unsupported {
            let result = FixedCatalogResponseDecoder.decode(
                NativeTransportResponse(statusCode: 200, contentType: "application/json", body: fixturePage(items: [candidate]))
            )
            #expect(result.snapshot == nil)
            #expect(result.failure != nil)
        }

        let xtra = FixedCatalogResponseDecoder.decode(
            NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: fixturePage(items: [item(id: "fixture-xtra", entityType: "channel-xtra")])
            )
        )
        #expect(xtra.snapshot?.channels.isEmpty == true)
        #expect(xtra.failure == nil)
    }

    @Test("redirect, response controls, and absent initial collection fail closed")
    func preflightAndEnvelopeControlsFailClosed() {
        let invalidResponses = [
            NativeTransportResponse(statusCode: 200, contentType: "application/json", body: fixturePage(items: []), redirectLocation: "fixture-redirect"),
            NativeTransportResponse(statusCode: 302, contentType: "application/json", body: fixturePage(items: [])),
            NativeTransportResponse(statusCode: 200, contentType: "text/html", body: Data("fixture-html".utf8)),
            NativeTransportResponse(statusCode: 200, contentType: "application/json", body: Data(#"{\"fixture_marker\":\"missing-page\"}"#.utf8)),
        ]

        for response in invalidResponses {
            let result = FixedCatalogResponseDecoder.decode(response)
            #expect(result.snapshot == nil)
            #expect(result.failure != nil)
        }
    }

    @Test("catalog redirect delegates are isolated per synthetic request")
    func catalogRedirectDelegatesAreIsolated() {
        let redirected = PerRequestRedirectDelegate()
        let untouched = PerRequestRedirectDelegate()
        let url = URL(string: "https://fixture.invalid/redirect")!
        let task = URLSession.shared.dataTask(with: url)
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let decision = RedirectDecisionBox(URLRequest(url: url))

        redirected.urlSession(
            URLSession.shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: url),
            completionHandler: { decision.record($0) }
        )

        #expect(decision.value == nil)
        #expect(redirected.didObserveRedirect)
        #expect(!untouched.didObserveRedirect)
    }

    @Test("one explicit refresh makes one fixed catalog request and production composition selects it")
    func refreshesExactlyOnceThroughCurrentSession() async {
        let transport = RecordingCatalogTransport(response: NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: fixturePage(items: [item(id: "fixture-production")])
        ))
        let coordinator = await makeActiveCatalogSession()
        let client = SiriusXMClient(
            sessionCoordinator: coordinator,
            catalogTransport: transport
        )

        guard case let .snapshot(snapshot) = await client.catalog() else {
            Issue.record("Expected the production fixed catalog refresher")
            return
        }
        #expect(snapshot.channels.map(\.id) == [LiveChannelID("fixture-production")])
        #expect(await transport.requestCount == 1)
        #expect(await transport.receivedOnlyExactFixedRequest)
    }

    @Test("sign-out supersedes an in-flight catalog generation before it can publish")
    func signOutSupersedesCatalogRefresh() async {
        let transport = BlockingCatalogTransport()
        let coordinator = await makeActiveCatalogSession()
        let client = SiriusXMClient(sessionCoordinator: coordinator, catalogTransport: transport)

        let refresh = Task { await client.catalog() }
        await transport.waitUntilRequested()
        _ = await client.signOut()
        await transport.release(NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: fixturePage(items: [item(id: "fixture-obsolete")])
        ))

        #expect(await refresh.value == .failed(.notEntitled))
    }

    @Test("catalog snapshots and safe results retain no request or response material")
    func semanticResultsDoNotExposeMaterial() {
        let result = FixedCatalogResponseDecoder.decode(
            NativeTransportResponse(statusCode: 200, contentType: "application/json", body: fixturePage(items: [item(id: "fixture-private")]))
        )
        let description = String(reflecting: result)

        #expect(!description.contains("Authorization"))
        #expect(!description.contains("fixture_marker"))
        #expect(!description.contains("URLRequest"))
    }

    private func makeActiveCatalogSession() async -> SessionCoordinator {
        let coordinator = SessionCoordinator(
            credentialSource: CatalogCredentialSource(),
            authenticationVerifier: CatalogVerifier(),
            entitlementVerifier: CatalogVerifier(),
            credentialStore: CatalogCredentialStore(),
            clock: CatalogClock(),
            diagnostics: CatalogDiagnostics()
        )
        #expect(await coordinator.attemptSession() == .active)
        return coordinator
    }

    private func fixturePage(items: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "page": [
                "containers": [
                    ["sets": [["items": items]]],
                ],
            ],
        ])
    }

    private func item(
        id: String,
        entityType: String = "channel-linear",
        connectivity: String = "ip-and-sat",
        playID: String? = nil,
        includePlay: Bool = true,
        channelNumber: Any = 12
    ) -> [String: Any] {
        var actions: [String: Any] = [:]
        if includePlay {
            actions["play"] = [["entity": ["type": entityType, "id": playID ?? id]]]
        }
        return [
            "entity": [
                "type": entityType,
                "id": id,
                "texts": [
                    "title": ["default": "Fixture \(id)"],
                    "description": ["default": "Fixture description"],
                ],
            ],
            "decorations": [
                "connectivity": connectivity,
                "contentTypeLabel": "CHANNEL",
                "channelNumber": channelNumber,
                "genre": "Fixture",
            ],
            "actions": actions,
        ]
    }
}

private actor RecordingCatalogTransport: FixedCatalogTransporting {
    private let response: NativeTransportResponse
    private(set) var requestCount = 0
    private(set) var receivedOnlyExactFixedRequest = true

    init(response: NativeTransportResponse) {
        self.response = response
    }

    func catalog(using credential: AuthenticationCredential) async -> NativeTransportResponse {
        requestCount += 1
        receivedOnlyExactFixedRequest = receivedOnlyExactFixedRequest && FixedCatalogRequestFactory.isExact(credential: credential)
        return response
    }
}

private actor BlockingCatalogTransport: FixedCatalogTransporting {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<NativeTransportResponse, Never>?

    func catalog(using _: AuthenticationCredential) async -> NativeTransportResponse {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func waitUntilRequested() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release(_ response: NativeTransportResponse) {
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
    }
}

private final class RedirectDecisionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?

    init(_ value: URLRequest?) {
        stored = value
    }

    var value: URLRequest? {
        lock.withLock { stored }
    }

    func record(_ value: URLRequest?) {
        lock.withLock { stored = value }
    }
}

private actor CatalogCredentialSource: CredentialSource {
    func credential() async -> AuthenticationCredential? {
        AuthenticationCredential(volatileMaterial: Data("fixture-credential".utf8))
    }
}

private struct CatalogVerifier: NativeAuthenticationVerifying, NativeEntitlementVerifying {
    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        NativeTransportResponse(statusCode: 200, contentType: "application/json", body: SanitizedNativeResponseFixtures.profileV4Authenticated)
    }

    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        NativeTransportResponse(statusCode: 200, contentType: "application/json", body: SanitizedNativeResponseFixtures.subscriptionV1Active)
    }
}

private actor CatalogCredentialStore: CredentialStore {
    func save(_: AuthenticationCredential) async throws {}
    func erase() async throws {}
}

private struct CatalogClock: SessionClock {
    func now() -> Date { .distantPast }
}

private actor CatalogDiagnostics: SessionDiagnostics {
    func record(_: SessionDiagnosticEvent) async {}
}
