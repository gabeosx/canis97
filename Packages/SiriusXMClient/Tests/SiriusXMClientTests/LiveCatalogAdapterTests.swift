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
        #expect(SiriusXMRequestContract.isOpaqueMediaDeliveryHost("live-secondary.streaming.siriusxm.com"))
        #expect(!SiriusXMRequestContract.isOpaqueMediaDeliveryHost("lookaround-cache-prod.streaming.siriusxm.com"))
        #expect(!SiriusXMRequestContract.isOpaqueMediaDeliveryHost("live-secondary.streaming.siriusxm.com.attacker.invalid"))
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

    @Test("production tune request serializes one source directly")
    func productionTuneRequestUsesCurrentDirectSourceBody() throws {
        let credential = try browserCredential(
            accessToken: "fixture-credential",
            accessExpiresAt: Date(timeIntervalSince1970: 10_800)
        )
        let request = try #require(
            FixedLiveRequestFactory.tune(
                for: LiveChannelID("fixture-channel"),
                using: credential
            )
        )
        let body = try #require(request.httpBody)
        let source = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        #expect(Set(source.keys) == [
            "id",
            "type",
            "hlsVersion",
            "manifestVariant",
            "mtcVersion",
            "trackResumeSupported",
        ])
        #expect(source["id"] as? String == "fixture-channel")
        #expect(source["type"] as? String == "channel-linear")
        #expect(source["hlsVersion"] as? String == "V3")
        #expect(source["manifestVariant"] as? String == "WEB")
        #expect(source["mtcVersion"] as? String == "V2")
        #expect(source["trackResumeSupported"] as? Bool == false)
        #expect(source["sources"] == nil)
        #expect(request.value(forHTTPHeaderField: "x-sxm-clock")?.range(
            of: #"^\[\d+,\d+\]$"#,
            options: .regularExpression
        ) != nil)
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

        #expect(catalog.channels.map(\.id) == [LiveChannelID("fixture-bravo"), LiveChannelID("fixture-echo")])
        #expect(catalog.channels.map(\.category) == ["News", "Music"])
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

    @Test("channel number name category and opaque identity establish tuner order")
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
            LiveChannelID("fixture-news"),
            LiveChannelID("fixture-a"),
            LiveChannelID("fixture-b"),
            LiveChannelID("fixture-z"),
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
    @Test("the observed Channels page and continuation requests remain exact and authenticated")
    func channelBrowseRequestsAreExact() throws {
        let credential = try browserCredential(
            accessToken: "fixture-credential",
            accessExpiresAt: Date(timeIntervalSince1970: 10_800)
        )
        let initial = try #require(FixedCatalogRequestFactory.makeInitialRequest(
            using: credential,
            clock: "[0,0]"
        ))
        let cursor = FixedCatalogPageCursor(
            containerID: "3JoBfOCIwo6FmTpzM1S2H7",
            setID: "5mqCLZ21qAwnufKT8puUiM",
            nextOffset: 30,
            totalCount: 713
        )
        let continuation = try #require(FixedCatalogRequestFactory.makePageRequest(
            using: credential,
            cursor: cursor,
            clock: "[0,1]"
        ))

        #expect(initial.url?.scheme == "https")
        #expect(initial.url?.host == "api.edge-gateway.siriusxm.com")
        #expect(initial.url?.path == "/browse/v1/pages/curated-grouping/403ab6a5-d3c9-4c2a-a722-a94a6a5fd056")
        #expect(initial.httpMethod == "GET")
        #expect(initial.httpBody == nil)
        #expect(initial.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(initial.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-credential")
        #expect(initial.value(forHTTPHeaderField: "x-sxm-clock") == "[0,0]")
        #expect(catalogQuery(initial)?["locale"] as? String == "en-US")
        let initialPagination = ((catalogQuery(initial)?["pagination"] as? [String: Any])?["offset"] as? [String: Any])
        #expect(initialPagination?["setItemsLimit"] as? Int == 30)

        #expect(continuation.url?.path == "/browse/v1/pages/curated-grouping/403ab6a5-d3c9-4c2a-a722-a94a6a5fd056/containers/3JoBfOCIwo6FmTpzM1S2H7")
        #expect(continuation.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-credential")
        #expect(continuation.value(forHTTPHeaderField: "x-sxm-clock") == "[0,1]")
        let sets = catalogQuery(continuation)?["sets"] as? [String: Any]
        let set = sets?["5mqCLZ21qAwnufKT8puUiM"] as? [String: Any]
        let pagination = (set?["pagination"] as? [String: Any])?["offset"] as? [String: Any]
        #expect(pagination?["setItemsLimit"] as? Int == 50)
        #expect(pagination?["setItemsOffset"] as? Int == 30)
        #expect(((set?["sort"] as? [String: Any])?["sortId"] as? String) == "CHANNEL_NUMBER_ASC")
    }

    @Test("the retired public package-metadata response cannot masquerade as a channel feed")
    func rejectsPublicPackageMetadataAsCatalog() {
        let sanitizedPackageMetadata = try! JSONSerialization.data(withJSONObject: [
            "packageTitle": "Fixture package",
            "radioType": "Fixture radio type",
            "packageDisplayName": "Fixture display name",
            "packageCallCenterDescription": "Fixture call-center description",
            "packageLongDescription": "Fixture long description",
            "exclusiveBadge": [
                "ariaLabel": "Fixture badge",
                "backgroundColor": "fixture-color",
                "content": "Fixture content",
                "icon": "fixture-icon",
            ],
        ])

        let result = FixedCatalogResponseDecoder.decode(NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: sanitizedPackageMetadata
        ))

        #expect(result.snapshot == nil)
        #expect(result.failure == .collectionUnavailable)
    }

    @Test("a complete observed page decodes linear channels and fixed media artwork")
    func decodesCompleteObservedPage() throws {
        let result = FixedCatalogResponseDecoder.decode(NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json; charset=utf-8",
            body: fixtureInitialPage(items: [
                item(id: "194adbca-34d6-cb94-b153-3488ee563308", channelNumber: 2),
                item(id: "123f7d39-c99f-2f01-7900-0d4b8b010cb7", connectivity: "ip", channelNumber: 700),
                item(id: "0754b635-72e9-497c-82d7-241bc1ecb922", entityType: "channel-xtra", channelNumber: 701),
                item(id: "a7581300-7f69-4d31-8c5c-1bcc8e73d133", unentitled: true, channelNumber: 702),
            ], totalCount: 4)
        ))

        #expect(result.snapshot?.channels.map(\.displayNumber) == [2, 700])
        #expect(result.snapshot?.channels.allSatisfy { $0.artwork != nil } == true)
        #expect(result.failure == nil)
        let reference = try #require(result.snapshot?.channels.first?.artwork)
        let request = try #require(FixedMetadataURLSessionTransport.artworkRequest(for: reference))
        #expect(request.url?.host == "imgsrv-sxm-prod-device.streaming.siriusxm.com")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("an initial 30-item page exposes a bounded continuation instead of publishing a partial lineup")
    func initialPageRequiresPagination() throws {
        let items = (0 ..< 30).map { index in
            item(id: fixtureChannelID(index), channelNumber: index + 1)
        }
        let response = NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: fixtureInitialPage(items: items, totalCount: 80)
        )
        let segment = FixedCatalogResponseDecoder.decodeInitial(response)
        let cursor = try #require(segment.segment?.cursor)

        #expect(segment.segment?.candidates.count == 30)
        #expect(cursor.nextOffset == 30)
        #expect(cursor.totalCount == 80)
        #expect(FixedCatalogResponseDecoder.decode(response).failure == .partialLineup)
    }

    @Test("continuation pages must preserve the observed set, offset, and total")
    func continuationEnvelopeIsStrict() throws {
        let cursor = FixedCatalogPageCursor(
            containerID: "3JoBfOCIwo6FmTpzM1S2H7",
            setID: "5mqCLZ21qAwnufKT8puUiM",
            nextOffset: 30,
            totalCount: 32
        )
        let valid = FixedCatalogResponseDecoder.decodeContinuation(
            NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: fixtureContainerPage(items: [
                    item(id: fixtureChannelID(30), channelNumber: 31),
                    item(id: fixtureChannelID(31), channelNumber: 32),
                ], offset: 30, totalCount: 32)
            ),
            expected: cursor
        )
        #expect(valid.segment?.candidates.count == 2)
        #expect(valid.segment?.cursor == nil)

        let changedTotal = FixedCatalogResponseDecoder.decodeContinuation(
            NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: fixtureContainerPage(
                    items: [item(id: fixtureChannelID(30), channelNumber: 31)],
                    offset: 30,
                    totalCount: 33
                )
            ),
            expected: cursor
        )
        #expect(changedTotal.segment == nil)
        #expect(changedTotal.failure == .paginationUnavailable)
    }

    @Test("catalog response size and total count remain bounded")
    func rejectsCatalogResourceBoundaryViolations() {
        let oversized = FixedCatalogResponseDecoder.decode(
            NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: Data(repeating: 0x20, count: 8 * 1_024 * 1_024 + 1)
            )
        )

        let excessive = FixedCatalogResponseDecoder.decode(
            NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: fixtureInitialPage(
                    items: [item(id: fixtureChannelID(0))],
                    totalCount: 2_001
                )
            )
        )

        #expect(oversized.snapshot == nil)
        #expect(oversized.failure == .collectionUnavailable)
        #expect(excessive.snapshot == nil)
        #expect(excessive.failure == .collectionUnavailable)
    }

    @Test("missing, malformed, or mismatched capability evidence fails closed while Xtra remains excluded")
    func rejectsUnsupportedOrMalformedCandidates() {
        let unsupported = [
            item(id: fixtureChannelID(0), playID: fixtureChannelID(1)),
            item(id: fixtureChannelID(0), includePlay: false),
            item(id: fixtureChannelID(0), connectivity: "sat"),
            item(id: fixtureChannelID(0), channelNumber: 7.5),
        ]

        for candidate in unsupported {
            let result = FixedCatalogResponseDecoder.decode(
                NativeTransportResponse(
                    statusCode: 200,
                    contentType: "application/json",
                    body: fixtureInitialPage(items: [candidate], totalCount: 1)
                )
            )
            #expect(result.snapshot == nil)
            #expect(result.failure != nil)
        }

        let xtra = FixedCatalogResponseDecoder.decode(
            NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: fixtureInitialPage(
                    items: [item(id: "fixture-xtra", entityType: "channel-xtra")],
                    totalCount: 1
                )
            )
        )
        #expect(xtra.snapshot?.channels.isEmpty == true)
        #expect(xtra.failure == nil)
    }

    @Test("redirect, response controls, and absent initial collection fail closed")
    func preflightAndEnvelopeControlsFailClosed() {
        let invalidResponses = [
            NativeTransportResponse(statusCode: 200, contentType: "application/json", body: fixtureInitialPage(items: [item(id: fixtureChannelID(0))], totalCount: 1), redirectLocation: "fixture-redirect"),
            NativeTransportResponse(statusCode: 302, contentType: "application/json", body: fixtureInitialPage(items: [item(id: fixtureChannelID(0))], totalCount: 1)),
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

    @Test("one explicit refresh follows bounded pagination and publishes only the complete lineup")
    func refreshesEveryObservedPageThroughCurrentSession() async {
        let firstItems = (0 ..< 30).map { index in
            item(id: fixtureChannelID(index), channelNumber: index + 1)
        }
        let finalItems = (30 ..< 32).map { index in
            item(id: fixtureChannelID(index), channelNumber: index + 1)
        }
        let transport = RecordingCatalogTransport(
            initialResponse: NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: fixtureInitialPage(items: firstItems, totalCount: 32)
            ),
            pageResponses: [30: NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: fixtureContainerPage(items: finalItems, offset: 30, totalCount: 32)
            )]
        )
        let coordinator = await makeActiveCatalogSession()
        let client = SiriusXMClient(
            sessionCoordinator: coordinator,
            catalogTransport: transport
        )

        guard case let .snapshot(snapshot) = await client.catalog() else {
            Issue.record("Expected the production fixed catalog refresher")
            return
        }
        #expect(snapshot.channels.count == 32)
        #expect(snapshot.channels.first?.displayNumber == 1)
        #expect(snapshot.channels.last?.displayNumber == 32)
        #expect(await transport.requestCount == 2)
        #expect(await transport.requestedOffsets == [30])
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
            body: fixtureInitialPage(
                items: [item(id: fixtureChannelID(0))],
                totalCount: 1
            )
        ))

        #expect(await refresh.value == .failed(.cancelled))
    }

    @Test("a prior session catalog completion cannot seed a later session's stale snapshot")
    func reauthenticatedSessionRejectsPriorCatalogCompletion() async {
        let refresher = BlockingThenFailingCatalogRefresher()
        let coordinator = await makeActiveCatalogSession()
        let client = SiriusXMClient(sessionCoordinator: coordinator, catalogRefresher: refresher)

        let firstRefresh = Task { await client.catalog() }
        await refresher.waitUntilRequested()

        #expect(await client.signOut() == .signedOut)
        #expect(await client.authenticate() == .authenticatedPendingEntitlement)
        #expect(await client.entitlement() == .entitled)

        await refresher.release(LiveCatalogSnapshotResult(
            snapshot: LiveCatalogSnapshot(
                channels: [LiveChannel(id: LiveChannelID("fixture-prior-session"))],
                freshness: .fresh
            ),
            failure: nil
        ))

        #expect(await firstRefresh.value == .failed(.cancelled))
        #expect(await client.catalog() == .failed(.unavailable))
    }

    @Test("catalog snapshots and safe results retain no request or response material")
    func semanticResultsDoNotExposeMaterial() {
        let result = FixedCatalogResponseDecoder.decode(
            NativeTransportResponse(
                statusCode: 200,
                contentType: "application/json",
                body: fixtureInitialPage(
                    items: [item(id: "194adbca-34d6-cb94-b153-3488ee563308", channelNumber: 2)],
                    totalCount: 1
                )
            )
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

    private func fixtureInitialPage(
        items: [[String: Any]],
        totalCount: Int,
        containerID: String = "3JoBfOCIwo6FmTpzM1S2H7",
        setID: String = "5mqCLZ21qAwnufKT8puUiM"
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "page": [
                "id": FixedCatalogRequestFactory.pageID,
                "containers": [
                    [
                        "id": containerID,
                        "sets": [[
                            "id": setID,
                            "items": items,
                            "pagination": ["offset": [
                                "size": totalCount,
                                "limit": FixedCatalogRequestFactory.initialItemLimit,
                                "offset": 0,
                            ]],
                        ]],
                    ],
                ],
            ],
        ])
    }

    private func fixtureContainerPage(
        items: [[String: Any]],
        offset: Int,
        totalCount: Int,
        containerID: String = "3JoBfOCIwo6FmTpzM1S2H7",
        setID: String = "5mqCLZ21qAwnufKT8puUiM"
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "container": [
                "id": containerID,
                "sets": [[
                    "id": setID,
                    "items": items,
                    "pagination": ["offset": [
                        "size": totalCount,
                        "limit": FixedCatalogRequestFactory.continuationItemLimit,
                        "offset": offset,
                    ]],
                ]],
            ],
        ])
    }

    private func item(
        id: String,
        entityType: String = "channel-linear",
        connectivity: String = "ip-and-sat",
        playID: String? = nil,
        includePlay: Bool = true,
        unentitled: Bool = false,
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
                "images": [
                    "tile": [
                        "aspect_1x1": [
                            "preferred": [
                                "url": "https://imgsrv-sxm-prod-device.streaming.siriusxm.com/fixture-image-key",
                            ],
                        ],
                    ],
                ],
            ],
            "decorations": [
                "connectivity": connectivity,
                "contentTypeLabel": "CHANNEL",
                "channelNumber": channelNumber,
                "genre": "Fixture",
                "unentitled": unentitled,
            ],
            "actions": actions,
        ]
    }

    private func fixtureChannelID(_ index: Int) -> String {
        String(format: "00000000-0000-4000-8000-%012d", index)
    }

    private func catalogQuery(_ request: URLRequest) -> [String: Any]? {
        guard let url = request.url,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value,
              value.hasPrefix("1.")
        else { return nil }
        var encoded = String(value.dropFirst(2))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private actor RecordingCatalogTransport: FixedCatalogTransporting {
    private let initialResponse: NativeTransportResponse
    private let pageResponses: [Int: NativeTransportResponse]
    private(set) var requestCount = 0
    private(set) var requestedOffsets: [Int] = []

    init(initialResponse: NativeTransportResponse, pageResponses: [Int: NativeTransportResponse]) {
        self.initialResponse = initialResponse
        self.pageResponses = pageResponses
    }

    func initialCatalog(using _: AuthenticationCredential) async -> NativeTransportResponse {
        requestCount += 1
        return initialResponse
    }

    func catalogPage(
        using _: AuthenticationCredential,
        cursor: FixedCatalogPageCursor
    ) async -> NativeTransportResponse {
        requestCount += 1
        requestedOffsets.append(cursor.nextOffset)
        return pageResponses[cursor.nextOffset] ?? NativeTransportResponse(
            statusCode: 0,
            contentType: nil,
            body: Data(),
            transportFailed: true
        )
    }
}

private actor BlockingCatalogTransport: FixedCatalogTransporting {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<NativeTransportResponse, Never>?

    func initialCatalog(using _: AuthenticationCredential) async -> NativeTransportResponse {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func catalogPage(
        using _: AuthenticationCredential,
        cursor _: FixedCatalogPageCursor
    ) async -> NativeTransportResponse {
        NativeTransportResponse(statusCode: 0, contentType: nil, body: Data(), transportFailed: true)
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

private actor BlockingThenFailingCatalogRefresher: CatalogRefreshing {
    private var refreshCount = 0
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<LiveCatalogSnapshotResult, Never>?

    func refresh() async -> LiveCatalogSnapshotResult {
        refreshCount += 1
        guard refreshCount == 1 else {
            return LiveCatalogSnapshotResult(snapshot: nil, failure: .unavailable)
        }
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func waitUntilRequested() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release(_ result: LiveCatalogSnapshotResult) {
        responseWaiter?.resume(returning: result)
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
        try? browserCredential(
            accessToken: "fixture-credential",
            accessExpiresAt: Date(timeIntervalSince1970: 10_800)
        )
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
