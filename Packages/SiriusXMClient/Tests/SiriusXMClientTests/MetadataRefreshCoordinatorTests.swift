import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Provider-neutral metadata refresh contracts")
struct MetadataRefreshCoordinatorTests {
    @Test("observed lookaround first cut maps its name and artistName into semantic metadata")
    func observedLookaroundFirstCutMapsProgramAndArtist() throws {
        let channel = LiveChannelID("fixture-channel")
        let payload = try observedLookaroundPayload(cut: [
            "name": "  Synthetic Program  ",
            "artistName": "  Synthetic Artist  ",
            "validFrom": "2026-08-19T00:00:00Z",
            "image": ["url": "/image.jpeg", "width": 450, "height": 450],
        ])
        let result = LiveListeningAdapter.decodeMetadata(NativeTransportResponse(statusCode: 200, contentType: "application/json", body: payload), channelID: channel)
        guard case let .current(snapshot) = result else { Issue.record("expected current metadata"); return }
        #expect(snapshot.channelID == channel)
        #expect(snapshot.program?.title == "Synthetic Program")
        #expect(snapshot.program?.artist == "Synthetic Artist")
        #expect(snapshot.program?.artwork?.description == "ChannelArtworkReference(redacted)")
    }

    @Test("observed fractional-second lookaround timestamps map into current metadata")
    func observedFractionalSecondLookaroundTimestampMapsProgram() throws {
        let channel = LiveChannelID("fixture-channel")
        let payload = try observedLookaroundPayload(cut: [
            "name": "Synthetic Program",
            "artistName": "Synthetic Artist",
            "validFrom": "2026-08-19T00:00:00.123Z",
        ])

        let result = LiveListeningAdapter.decodeMetadata(
            NativeTransportResponse(statusCode: 200, contentType: "application/json", body: payload),
            channelID: channel
        )

        guard case let .current(snapshot) = result else {
            Issue.record("expected current metadata")
            return
        }
        #expect(snapshot.channelID == channel)
        #expect(snapshot.program?.title == "Synthetic Program")
        #expect(snapshot.program?.artist == "Synthetic Artist")
    }

    @Test("schema evidence records only allow-listed paths, kinds, and bounded counts")
    func schemaEvidenceIsValueFreeAcrossCatalogLookaroundAndTune() throws {
        let catalogItem: [String: Any] = [
            "entity": ["texts": ["title": ["default": "fixture catalog title"]]],
            "metadata": ["live": ["items": [["name": "fixture current program"]]]]
        ]
        let catalogSet: [String: Any] = ["items": [catalogItem]]
        let catalogContainer: [String: Any] = ["sets": [catalogSet]]
        let catalog = try JSONSerialization.data(withJSONObject: [
            "page": ["containers": [catalogContainer]]
        ])
        let lookaround = try JSONSerialization.data(withJSONObject: [
            "channels": ["fixture-channel": [
                "cuts": [[
                    "name": "fixture title",
                    "artistName": "fixture artist",
                    "validFrom": "2026-08-19T00:00:00Z"
                ]],
                "shows": []
            ]],
            "delta": ""
        ])
        let tune = try JSONSerialization.data(withJSONObject: [
            "streams": [[:]],
            "metadata": ["live": [
                "items": [["title": "fixture tune title", "artist": "fixture tune artist"]],
                "episodes": []
            ]]
        ])

        let catalogEvidence = CompatibilitySchemaDiagnostics.catalogEvidence(body: catalog)
        let lookaroundEvidence = CompatibilitySchemaDiagnostics.lookaroundEvidence(
            body: lookaround,
            selectedChannelID: LiveChannelID("fixture-channel")
        )
        let tuneEvidence = CompatibilitySchemaDiagnostics.tuneEvidence(body: tune)

        #expect(catalogEvidence == "stage=catalog root=object page=object page.containers=one item-count=one entity.texts.title.default=string-nonempty metadata=object metadata.live=object metadata.live.items=one cuts=absent")
        #expect(lookaroundEvidence == "stage=lookaround root=object channels=object selected-channel=object selected.cuts=one selected.cuts[0].name=string-nonempty selected.cuts[0].title=absent selected.cuts[0].artistName=string-nonempty selected.cuts[0].artist=absent selected.cuts[0].validFrom=string-nonempty selected.cuts[0].validFrom.parse=default-ISO8601 delta=string-empty selected.shows=empty")
        #expect(tuneEvidence == "stage=tune root=object streams=one metadata=object metadata.live=object metadata.live.items=one metadata.live.items[0].name=absent metadata.live.items[0].title=string-nonempty metadata.live.items[0].artistName=absent metadata.live.items[0].artist=string-nonempty metadata.live.episodes=empty")
        #expect(![catalogEvidence, lookaroundEvidence, tuneEvidence].joined().contains("fixture"))
    }

    @Test("empty first-cut collection is unavailable and malformed input fails closed")
    func emptyAndMalformedMetadataFailClosed() throws {
        let channel = LiveChannelID("fixture-channel")
        let empty = try JSONSerialization.data(withJSONObject: ["channels": ["fixture-channel": ["cuts": []]], "delta": ""])
        #expect(LiveListeningAdapter.decodeMetadata(NativeTransportResponse(statusCode: 200, contentType: "application/json", body: empty), channelID: channel) == .unavailable)
        #expect(LiveListeningAdapter.decodeMetadata(NativeTransportResponse(statusCode: 200, contentType: "application/json", body: Data("{}".utf8)), channelID: channel) == .failed(.unsupportedResponse))
    }

    @Test("lookaround rejects missing, empty, wrong-type, and malformed required metadata fields")
    func observedLookaroundContractFailsClosedForInvalidRequiredFields() throws {
        let channel = LiveChannelID("fixture-channel")
        let base: [String: Any] = [
            "name": "Synthetic Program",
            "artistName": "Synthetic Artist",
            "validFrom": "2026-08-19T00:00:00Z",
        ]
        let invalidCuts: [[String: Any]] = [
            ["artistName": base["artistName"]!, "validFrom": base["validFrom"]!],
            ["name": "", "artistName": base["artistName"]!, "validFrom": base["validFrom"]!],
            ["name": "   ", "artistName": base["artistName"]!, "validFrom": base["validFrom"]!],
            ["name": 7, "artistName": base["artistName"]!, "validFrom": base["validFrom"]!],
            ["name": base["name"]!, "validFrom": base["validFrom"]!],
            ["name": base["name"]!, "artistName": "", "validFrom": base["validFrom"]!],
            ["name": base["name"]!, "artistName": ["not": "a string"], "validFrom": base["validFrom"]!],
            ["name": base["name"]!, "artistName": base["artistName"]!, "validFrom": "not-a-date"],
        ]

        for cut in invalidCuts {
            let payload = try observedLookaroundPayload(cut: cut)
            let response = NativeTransportResponse(statusCode: 200, contentType: "application/json", body: payload)
            #expect(LiveListeningAdapter.decodeMetadata(response, channelID: channel) == .failed(.unsupportedResponse))
        }
    }

    @Test("artwork-only metadata remains independent from text presentation")
    func artworkOnlyMetadataKeepsChannelTextFallback() async {
        let channel = LiveChannelID("fixture-artwork-only")
        let artwork = fixtureArtwork
        let refresher = RecordingMetadataRefresher(results: [.current(text: nil, artwork: artwork)])
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: FixedMetadataClock())

        _ = await coordinator.select(channel)
        let state = await coordinator.refresh()

        #expect(state.text == .channelFallback(channel))
        #expect(state.artwork == .current(artwork))
    }

    @Test("metadata uses channel identity as a fallback and text/artwork become current independently")
    func currentMetadataUsesIndependentRepresentations() async {
        let channel = LiveChannelID("fixture-metadata")
        let clock = FixedMetadataClock(now: Date(timeIntervalSince1970: 42))
        let refresher = RecordingMetadataRefresher(results: [.current(text: "Fixture title", artwork: nil)])
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: clock)

        #expect(await coordinator.select(channel).text == .channelFallback(channel))
        let state = await coordinator.refresh()

        #expect(state.text == .current("Fixture title"))
        #expect(state.artwork == .unavailable)
        #expect(state.refreshedAt == Date(timeIntervalSince1970: 42))
    }

    @Test("unavailable refreshes transition last known metadata through stale to unavailable")
    func unavailableMetadataDoesNotLookCurrentForever() async {
        let channel = LiveChannelID("fixture-stale")
        let artwork = fixtureArtwork
        let refresher = RecordingMetadataRefresher(results: [
            .current(text: "Fixture title", artwork: artwork),
            .unavailable,
            .unavailable,
        ])
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: FixedMetadataClock())

        _ = await coordinator.select(channel)
        _ = await coordinator.refresh()
        let stale = await coordinator.refresh()
        let unavailable = await coordinator.refresh()

        #expect(stale.text == .stale("Fixture title"))
        #expect(stale.artwork == .stale(artwork))
        #expect(unavailable.text == .unavailable)
        #expect(unavailable.artwork == .unavailable)
    }

    @Test("a superseded metadata completion cannot overwrite the newly selected channel")
    func ignoresStaleChannelCompletion() async {
        let first = LiveChannelID("fixture-old")
        let second = LiveChannelID("fixture-new")
        let refresher = BlockingMetadataRefresher()
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: FixedMetadataClock())

        _ = await coordinator.select(first)
        let refresh = Task { await coordinator.refresh() }
        await refresher.waitUntilStarted()
        _ = await coordinator.select(second)
        await refresher.release(.current(text: "Old title", artwork: fixtureArtwork))
        _ = await refresh.value

        #expect(await coordinator.currentState.channelID == second)
        #expect(await coordinator.currentState.text == .channelFallback(second))
    }

    @Test("metadata refresh has no audio collaborator or audio mutation surface")
    func metadataStaysOutsideAudioControl() async {
        let channel = LiveChannelID("fixture-isolated")
        let refresher = RecordingMetadataRefresher(results: [.current(text: nil, artwork: fixtureArtwork)])
        let coordinator = MetadataRefreshCoordinator(refresher: refresher, clock: FixedMetadataClock())

        _ = await coordinator.select(channel)
        _ = await coordinator.refresh()

        #expect(await refresher.requestedChannelIDs == [channel])
        #expect(await coordinator.currentState.channelID == channel)
    }

    @Test("metadata redirect delegates are isolated per synthetic request")
    func metadataRedirectDelegatesAreIsolated() {
        let redirected = PerRequestRedirectDelegate()
        let untouched = PerRequestRedirectDelegate()
        let url = URL(string: "https://fixture.invalid/redirect")!
        let task = URLSession.shared.dataTask(with: url)
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let decision = MetadataRedirectDecisionBox(URLRequest(url: url))

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

    @Test("client sign-out invalidates outstanding metadata work before cleanup can complete")
    func signOutInvalidatesMetadataFetcher() async {
        let fetcher = InvalidationRecordingMetadataFetcher()
        let client = SiriusXMClient(metadataFetcher: fetcher)

        #expect(await client.signOut() == .alreadySignedOut)
        #expect(await fetcher.invalidationCount == 1)
    }

    @Test("sign-out rejects late artwork bytes from the current session fetcher")
    func signOutRejectsLateArtwork() async {
        let session = metadataSessionCoordinator()
        let transport = BlockingMetadataTransport()
        let fetcher = CurrentSessionMetadataFetcher(sessionCoordinator: session, transport: transport)
        let client = SiriusXMClient(sessionCoordinator: session, metadataFetcher: fetcher)
        let reference = ChannelArtworkReference(relativeReference: "/fixture.jpeg")

        let artwork = Task { await fetcher.artwork(for: reference) }
        await transport.waitUntilArtworkRequested()
        #expect(await client.signOut() == .signedOut)
        await transport.releaseArtwork(
            NativeTransportResponse(statusCode: 200, contentType: "image/jpeg", body: fixtureArtwork.bytes)
        )

        #expect(await artwork.value == .unavailable)
    }

    @Test("metadata transport uses a closed, finite ephemeral configuration")
    func metadataTransportConfigurationIsBounded() {
        let configuration = FixedMetadataURLSessionTransport.makeConfiguration()

        #expect(configuration.timeoutIntervalForRequest == 15)
        #expect(configuration.timeoutIntervalForResource == 15)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }
}

private let fixtureArtwork = ArtworkData(bytes: Data([0xFF, 0xD8, 0xFF, 0xD9]), mediaType: .jpeg)

private func observedLookaroundPayload(cut: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "channels": ["fixture-channel": [
            "cuts": [cut],
            "shows": [],
        ]],
        "delta": "",
    ])
}

private actor InvalidationRecordingMetadataFetcher: LiveMetadataFetching {
    private(set) var invalidationCount = 0

    func metadata(for _: LiveChannelID) async -> MetadataAvailability { .unavailable }
    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }
    func invalidate() async { invalidationCount += 1 }
}

private func metadataSessionCoordinator() -> SessionCoordinator {
    SessionCoordinator(
        credentialSource: MetadataCredentialSource(),
        authenticationVerifier: MetadataVerifier(),
        entitlementVerifier: MetadataVerifier(),
        credentialStore: MetadataCredentialStore(),
        residueCleaner: MetadataResidueCleaner(),
        clock: MetadataSessionClock(),
        diagnostics: MetadataDiagnostics()
    )
}

private actor BlockingMetadataTransport: FixedMetadataTransporting {
    private var artworkRequested = false
    private var artworkStartWaiter: CheckedContinuation<Void, Never>?
    private var artworkResponseWaiter: CheckedContinuation<NativeTransportResponse, Never>?

    func lookaround(using _: AuthenticationCredential) async -> NativeTransportResponse {
        NativeTransportResponse(statusCode: 0, contentType: nil, body: Data(), transportFailed: true)
    }

    func artwork(for _: ChannelArtworkReference) async -> NativeTransportResponse {
        artworkRequested = true
        artworkStartWaiter?.resume()
        artworkStartWaiter = nil
        return await withCheckedContinuation { artworkResponseWaiter = $0 }
    }

    func waitUntilArtworkRequested() async {
        guard !artworkRequested else { return }
        await withCheckedContinuation { artworkStartWaiter = $0 }
    }

    func releaseArtwork(_ response: NativeTransportResponse) {
        artworkResponseWaiter?.resume(returning: response)
        artworkResponseWaiter = nil
    }
}

private actor MetadataCredentialSource: CredentialSource {
    func credential() async -> AuthenticationCredential? {
        AuthenticationCredential(volatileMaterial: Data("fixture-credential".utf8))
    }
}

private actor MetadataVerifier: NativeAuthenticationVerifying, NativeEntitlementVerifying {
    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        NativeTransportResponse(statusCode: 200, contentType: "application/json", body: SanitizedNativeResponseFixtures.profileV4Authenticated)
    }

    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        NativeTransportResponse(statusCode: 200, contentType: "application/json", body: SanitizedNativeResponseFixtures.subscriptionV1Active)
    }
}

private actor MetadataCredentialStore: CredentialStore {
    func save(_: AuthenticationCredential) async throws {}
    func erase() async throws {}
}

private actor MetadataResidueCleaner: AuthenticationResidueCleaner {
    func removeAuthenticationResidue() async -> AuthenticationResidueCleanupOutcome { .removed }
}

private struct MetadataSessionClock: SessionClock {
    func now() -> Date { Date(timeIntervalSince1970: 1) }
}

private actor MetadataDiagnostics: SessionDiagnostics {
    func record(_: SessionDiagnosticEvent) async {}
}

private final class MetadataRedirectDecisionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?

    init(_ value: URLRequest?) { stored = value }

    var value: URLRequest? { lock.withLock { stored } }

    func record(_ value: URLRequest?) {
        lock.withLock { stored = value }
    }
}

private struct FixedMetadataClock: LiveMetadataClock {
    let instant: Date

    init(now: Date = Date(timeIntervalSince1970: 1)) { instant = now }
    func now() -> Date { instant }
}

private actor RecordingMetadataRefresher: LiveMetadataRefreshing {
    private var results: [LiveMetadataRefreshResult]
    private(set) var requestedChannelIDs: [LiveChannelID] = []

    init(results: [LiveMetadataRefreshResult]) { self.results = results }

    func refresh(for channelID: LiveChannelID) async -> LiveMetadataRefreshResult {
        requestedChannelIDs.append(channelID)
        return results.removeFirst()
    }
}

private actor BlockingMetadataRefresher: LiveMetadataRefreshing {
    private var continuation: CheckedContinuation<LiveMetadataRefreshResult, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var started = false

    func refresh(for _: LiveChannelID) async -> LiveMetadataRefreshResult {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release(_ result: LiveMetadataRefreshResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
