import XCTest
@testable import SiriusMac
import SiriusXMClient

@MainActor
final class ListeningCompositionTests: XCTestCase {
    func testSelectedInventedChannelUsesTheSingleInjectedCoordinator() async {
        let driver = RecordingPlaybackDriver()
        let coordinator = PlaybackCoordinator(
            authorization: AlwaysAuthorizedPlaybackAuthorization(),
            driver: driver
        )
        let model = ListeningPresentationModel(playbackCoordinator: coordinator)
        let channel = LiveChannelID("fixture-channel-alpha")

        model.select(channel)
        await model.playSelectedChannel()

        let tunedChannelIDs = await driver.recordedChannelIDs()
        XCTAssertTrue(model.playbackCoordinator === coordinator)
        XCTAssertEqual(tunedChannelIDs, [channel])
        XCTAssertEqual(coordinator.state, .playing(channel))
    }

    func testStaleCatalogCanBeBrowsedButCannotAuthorizePlayback() async {
        let driver = RecordingPlaybackDriver()
        let coordinator = PlaybackCoordinator(
            authorization: UnavailablePlaybackAuthorization(),
            driver: driver
        )
        let model = ListeningPresentationModel(playbackCoordinator: coordinator)
        let channel = LiveChannelID("fixture-channel-stale")

        model.present(
            LiveCatalogSnapshot(
                channels: [LiveChannel(id: channel, title: "Fixture Stale")],
                freshness: .stale
            )
        )
        model.select(channel)
        await model.playSelectedChannel()

        let tuneCallCount = await driver.recordedTuneCallCount()
        XCTAssertEqual(model.catalog.freshness, .stale)
        XCTAssertEqual(tuneCallCount, 0)
        XCTAssertEqual(coordinator.state, .unavailable(.authorizationUnavailable))
    }

    func testConfirmedCommandsIgnoreSupersededCompletion() async {
        let driver = BlockingPlaybackDriver()
        let coordinator = PlaybackCoordinator(
            authorization: AlwaysAuthorizedPlaybackAuthorization(),
            driver: driver
        )
        let first = LiveChannelID("fixture-channel-first")
        let second = LiveChannelID("fixture-channel-second")

        let firstTune = Task { await coordinator.tune(first) }
        await driver.waitForTune(of: first)
        let secondTune = Task { await coordinator.tune(second) }
        await driver.waitForTune(of: second)

        await driver.confirmTune(of: first)
        await driver.confirmTune(of: second)
        _ = await firstTune.value
        _ = await secondTune.value

        XCTAssertEqual(coordinator.state, .playing(second))
    }

    func testDefaultCompositionAwaitsCompatibilityEvidenceWithoutWork() {
        let model = ListeningPresentationModel()

        XCTAssertEqual(model.playbackCoordinator.state, .awaitingLiveContract)
        XCTAssertEqual(model.catalog, .unavailable)
    }

    func testLiveContractObservationSinkAcceptsOnlyClosedSemanticEvidence() {
        let sink = LiveContractObservationSink()
        let observation = LiveContractObservation(
            capability: .catalogRefresh,
            disposition: .supported,
            requestContract: LiveRequestContract(
                purpose: .catalogObservation,
                method: .get,
                authorizedHostPolicy: .firstPartyAuthenticated,
                pathTemplate: .catalog
            ),
            semanticShapes: [
                LiveSemanticShape(alias: .catalogEntity, valueType: .object, cardinality: .many),
            ],
            protection: nil,
            avFoundationBehavior: .notObserved
        )

        XCTAssertTrue(sink.begin())
        XCTAssertTrue(sink.record(observation))
        XCTAssertEqual(sink.observations, [observation])
        XCTAssertEqual(sink.state, .active)
    }

    func testLiveContractObservationSinkClosesAndRejectsLaterObservations() {
        let cancelled = LiveContractObservationSink()
        XCTAssertTrue(cancelled.begin())
        XCTAssertFalse(cancelled.begin())
        cancelled.cancel()
        XCTAssertEqual(cancelled.state, .closed(.cancelled))
        XCTAssertFalse(cancelled.record(supportedCatalogObservation()))

        let signedOut = LiveContractObservationSink()
        XCTAssertTrue(signedOut.begin())
        signedOut.signOut()
        XCTAssertEqual(signedOut.state, .closed(.signedOut))
        XCTAssertFalse(signedOut.record(supportedCatalogObservation()))

        let terminal = LiveContractObservationSink()
        XCTAssertTrue(terminal.begin())
        XCTAssertTrue(terminal.record(
            LiveContractObservation(
                capability: .tuneAuthorization,
                disposition: .unsupported,
                requestContract: nil,
                semanticShapes: [],
                protection: .rateLimited,
                avFoundationBehavior: .notObserved
            )
        ))
        XCTAssertEqual(terminal.state, .closed(.terminalObservation))
        XCTAssertFalse(terminal.record(supportedCatalogObservation()))
    }

    func testClosedLiveObservationAdapterRequiresEntitlementAndClosesWithoutCredential() async {
        let adapter = ClosedLiveObservationAdapter()

        XCTAssertEqual(adapter.begin(entitlement: .unavailable), .entitlementRequired)
        XCTAssertEqual(adapter.state, .idle)

        XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)
        let result = await adapter.runCatalog()
        XCTAssertEqual(result, .terminal(.authorizationLost))

        XCTAssertEqual(adapter.observations, [
            LiveContractObservation(
                capability: .catalogRefresh,
                disposition: .unsupported,
                requestContract: nil,
                semanticShapes: [],
                protection: .authorizationLost,
                avFoundationBehavior: .notObserved
            ),
        ])
        XCTAssertEqual(adapter.state, .closed(.terminalObservation))
        XCTAssertEqual(adapter.begin(entitlement: .entitled), .alreadyConsumed)
    }

    func testCatalogContractAllowsOnlyTheCurrentBrowserPageRequest() throws {
        let request = try XCTUnwrap(
            ClosedCatalogRequestContract.makeRequest(
                credential: AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))
            )
        )

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.edge-gateway.siriusxm.com")
        XCTAssertEqual(request.url?.path, "/browse/v1/pages/curated-grouping/403ab6a5-d3c9-4c2a-a722-a94a6a5fd056")
        XCTAssertNil(request.url?.query)
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testCatalogTransportCancelsEveryRedirect() {
        XCTAssertEqual(ClosedCatalogTransport.redirectDecision, .cancel)
    }

    func testCatalogRunCollapsesOnlySanitizedChannelSemantics() async {
        let transport = RecordingCatalogTransport(
            result: .response(
                statusCode: 200,
                contentType: "application/json",
                body: Data(#"{"channels":[{"id":"safe-channel-1","type":"channel-linear","name":"Safe Channel","category":"Music","isFavorite":true,"isAvailable":true}]}"#.utf8)
            )
        )
        let adapter = ClosedLiveObservationAdapter(
            credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
            transport: transport
        )

        XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)
        let result = await adapter.runCatalog()

        XCTAssertEqual(result, .channels([
            ClosedCatalogChannel(
                id: "safe-channel-1",
                displayName: "Safe Channel",
                category: "Music",
                isFavorite: true,
                isAvailable: true
            ),
        ]))
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(adapter.observations.count, 1)
        XCTAssertEqual(adapter.observations[0].requestContract?.pathTemplate, .catalog)
        XCTAssertEqual(adapter.state, .active)
    }

    func testCatalogRunAcceptsBoundedFirstPartyPageEnvelopeWithNestedTitle() async {
        let padding = String(repeating: "x", count: 1_048_576)
        let body = Data(
            """
            {"page":{"containers":[{"sets":[{"items":[{"entity":{"id":"safe-channel-1","type":"channel-linear","texts":{"title":{"default":"Safe Channel"}}}}]}]}],"padding":"\(padding)"}}
            """.utf8
        )
        let transport = RecordingCatalogTransport(
            result: .response(statusCode: 200, contentType: "application/json", body: body)
        )
        let adapter = ClosedLiveObservationAdapter(
            credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
            transport: transport
        )

        XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)

        let result = await adapter.runCatalog()

        XCTAssertEqual(
            result,
            .channels([
                ClosedCatalogChannel(
                    id: "safe-channel-1",
                    displayName: "Safe Channel",
                    category: nil,
                    isFavorite: nil,
                    isAvailable: nil
                ),
            ])
        )
    }

    func testCatalogRunStillRejectsPageDocumentsAboveTheBoundedMaximum() async {
        let padding = String(repeating: "x", count: 8 * 1_024 * 1_024)
        let body = Data(
            """
            {"page":{"containers":[{"sets":[{"items":[{"entity":{"id":"safe-channel-1","type":"channel-linear"}}]}]}],"padding":"\(padding)"}}
            """.utf8
        )
        let transport = RecordingCatalogTransport(
            result: .response(statusCode: 200, contentType: "application/json", body: body)
        )
        let adapter = ClosedLiveObservationAdapter(
            credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
            transport: transport
        )

        XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)

        let result = await adapter.runCatalog()

        XCTAssertEqual(result, .classifiedTerminal(.malformedContract, .documentTooLarge))
    }

    func testCatalogRunClassifiesMalformedResponsesWithoutRetainingProviderData() async {
        let cases: [(ClosedCatalogTransportResult, ClosedCatalogFailure)] = [
            (.response(statusCode: 200, contentType: "text/plain", body: Data()), .nonJSONContent),
            (.response(statusCode: 200, contentType: "application/json", body: Data("not-json".utf8)), .invalidJSON),
            (.response(statusCode: 200, contentType: "application/json", body: Data("\"scalar\"".utf8)), .unsupportedRoot),
            (.response(statusCode: 200, contentType: "application/json", body: Data(#"{}"#.utf8)), .noAdmissibleChannel),
            (
                .response(
                    statusCode: 200,
                    contentType: "application/json",
                    body: Data(#"{"channels":[{"id":"invalid id","type":"channel-linear"}]}"#.utf8)
                ),
                .noValidChannelIdentity
            ),
        ]

        for (transportResult, failure) in cases {
            let adapter = ClosedLiveObservationAdapter(
                credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
                transport: RecordingCatalogTransport(result: transportResult)
            )

            XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)
            let result = await adapter.runCatalog()

            XCTAssertEqual(result, .classifiedTerminal(.malformedContract, failure))
            XCTAssertEqual(adapter.observations.map(\.protection), [.malformedContract])
            XCTAssertEqual(adapter.state, .closed(.terminalObservation))
        }
    }

    func testCatalogRunClassifiesAnAdmissibleChannelBeyondTheBoundedNestingLimit() async throws {
        var nested: [String: Any] = ["id": "safe-channel-1", "type": "channel-linear"]
        for _ in 0 ... 12 {
            nested = ["container": nested]
        }
        let body = try JSONSerialization.data(withJSONObject: nested)
        let adapter = ClosedLiveObservationAdapter(
            credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
            transport: RecordingCatalogTransport(
                result: .response(statusCode: 200, contentType: "application/json", body: body)
            )
        )

        XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)

        let result = await adapter.runCatalog()
        XCTAssertEqual(
            result,
            .classifiedTerminal(.malformedContract, .candidateBeyondNestingLimit)
        )
    }

    func testCatalogRunClassifiesNonChannelDataBeyondTheBoundedNestingLimit() async throws {
        var nested: [String: Any] = ["kind": "unrecognized"]
        for _ in 0 ... 12 {
            nested = ["container": nested]
        }
        let body = try JSONSerialization.data(withJSONObject: nested)
        let adapter = ClosedLiveObservationAdapter(
            credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
            transport: RecordingCatalogTransport(
                result: .response(statusCode: 200, contentType: "application/json", body: body)
            )
        )

        XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)

        let result = await adapter.runCatalog()
        XCTAssertEqual(
            result,
            .classifiedTerminal(.malformedContract, .nestingLimit)
        )
    }

    func testCatalogRunDoesNotRequestWhenCredentialIsMissingOrInvalid() async {
        for availability in [ClosedCatalogCredentialAvailability.missing, .invalid] {
            let transport = RecordingCatalogTransport(result: .transportFailure)
            let adapter = ClosedLiveObservationAdapter(
                credentialLoader: { availability },
                transport: transport
            )

            XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)
            let result = await adapter.runCatalog()
            let requestCount = await transport.requestCount()
            XCTAssertEqual(result, .terminal(.authorizationLost))
            XCTAssertEqual(requestCount, 0)
            XCTAssertEqual(adapter.state, .closed(.terminalObservation))
        }
    }

    func testCatalogRunCollapsesRedirectAndProtectedStatusBeforeDecoding() async {
        for (transportResult, protection) in [
            (ClosedCatalogTransportResult.redirect, LiveProtectionClass.unknownHostOrRedirect),
            (.response(statusCode: 403, contentType: "text/plain", body: Data()), .forbidden),
        ] {
            let adapter = ClosedLiveObservationAdapter(
                credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
                transport: RecordingCatalogTransport(result: transportResult)
            )

            XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)
            let result = await adapter.runCatalog()

            XCTAssertEqual(result, .terminal(protection))
            XCTAssertEqual(adapter.observations.map(\.protection), [protection])
            XCTAssertEqual(adapter.state, .closed(.terminalObservation))
        }
    }

    func testTuneContractUsesOnlyTheApprovedSelectedChannelAndExactRequestSemantics() throws {
        let request = try XCTUnwrap(
            ClosedTuneRequestContract.makeRequest(
                credential: AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))
            )
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sources = try XCTUnwrap(object["sources"] as? [[String: Any]])
        let source = try XCTUnwrap(sources.first)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.edge-gateway.siriusxm.com")
        XCTAssertEqual(request.url?.path, "/playback/play/v1/tuneSource")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(source["id"] as? String, ClosedTuneSelection.approved.id)
        XCTAssertEqual(source["type"] as? String, "channel-linear")
        XCTAssertEqual(source["hlsVersion"] as? String, "V3")
        XCTAssertEqual(source["manifestVariant"] as? String, "WEB")
        XCTAssertEqual(source["mtcVersion"] as? String, "V2")
    }

    func testTuneTransportCancelsEveryRedirect() {
        XCTAssertEqual(ClosedTuneTransport.redirectDecision, .cancel)
    }

    func testTuneRunNeedsAResourceAllowlistDecisionWithoutExposingTheResource() async {
        let adapter = ClosedTuneObservationAdapter(
            credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
            transport: RecordingTuneTransport(
                result: .response(
                    statusCode: 200,
                    contentType: "application/json",
                    body: Data(
                        #"{"source":{"id":"194adbca-34d6-cb94-b153-3488ee563308","type":"channel-linear","streams":[{"url":"https://unapproved.example.invalid/stream.m3u8"}]}}"#.utf8
                    )
                )
            )
        )

        XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)
        let result = await adapter.runTune()

        XCTAssertEqual(result, .resourceAllowlistDecisionRequired)
        XCTAssertEqual(adapter.observations.count, 1)
        XCTAssertEqual(adapter.observations[0].capability, .tuneAuthorization)
        XCTAssertEqual(adapter.observations[0].requestContract?.method, .post)
        XCTAssertEqual(adapter.observations[0].semanticShapes, [
            LiveSemanticShape(alias: .selectedChannel, valueType: .string, cardinality: .one),
            LiveSemanticShape(alias: .authorizedResource, valueType: .string, cardinality: .one),
        ])
    }

    func testTuneRunClosesOnCancellationAndProtectedOrUnknownResponses() async {
        let cancelledTransport = RecordingTuneTransport(result: .transportFailure)
        let cancelled = ClosedTuneObservationAdapter(
            credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
            transport: cancelledTransport
        )
        XCTAssertEqual(cancelled.begin(entitlement: .entitled), .started)
        cancelled.cancel()
        let cancelledResult = await cancelled.runTune()
        let cancelledRequestCount = await cancelledTransport.requestCount()
        XCTAssertEqual(cancelledResult, .cancelled)
        XCTAssertEqual(cancelledRequestCount, 0)

        for (response, protection) in [
            (ClosedTuneTransportResult.redirect, LiveProtectionClass.unknownHostOrRedirect),
            (.response(statusCode: 403, contentType: "text/plain", body: Data()), .forbidden),
            (.response(statusCode: 429, contentType: "text/plain", body: Data()), .rateLimited),
            (.response(statusCode: 200, contentType: "application/json", body: Data(#"{}"#.utf8)), .malformedContract),
        ] {
            let adapter = ClosedTuneObservationAdapter(
                credentialLoader: { .available(AuthenticationCredential(volatileMaterial: Data("synthetic-credential".utf8))) },
                transport: RecordingTuneTransport(result: response)
            )
            XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)
            let result = await adapter.runTune()
            XCTAssertEqual(result, .terminal(protection))
            XCTAssertEqual(adapter.observations.map(\.protection), [protection])
            XCTAssertEqual(adapter.state, .closed(.terminalObservation))
        }
    }

    private func supportedCatalogObservation() -> LiveContractObservation {
        LiveContractObservation(
            capability: .catalogRefresh,
            disposition: .supported,
            requestContract: LiveRequestContract(
                purpose: .catalogObservation,
                method: .get,
                authorizedHostPolicy: .firstPartyAuthenticated,
                pathTemplate: .catalog
            ),
            semanticShapes: [
                LiveSemanticShape(alias: .catalogEntity, valueType: .object, cardinality: .many),
            ],
            protection: nil,
            avFoundationBehavior: .notObserved
        )
    }
}

private actor RecordingPlaybackDriver: LivePlaybackDriving {
    private(set) var tunedChannelIDs: [LiveChannelID] = []

    func recordedChannelIDs() -> [LiveChannelID] { tunedChannelIDs }

    func recordedTuneCallCount() -> Int { tunedChannelIDs.count }

    func tune(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult {
        tunedChannelIDs.append(channelID)
        return .confirmed(.playing(channelID))
    }

    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }
}

private actor RecordingCatalogTransport: ClosedCatalogRequestPerforming {
    private let result: ClosedCatalogTransportResult
    private var count = 0

    init(result: ClosedCatalogTransportResult) {
        self.result = result
    }

    func send(_: URLRequest) async -> ClosedCatalogTransportResult {
        count += 1
        return result
    }

    func requestCount() -> Int { count }
}

private actor RecordingTuneTransport: ClosedTuneRequestPerforming {
    private let result: ClosedTuneTransportResult
    private var count = 0

    init(result: ClosedTuneTransportResult) {
        self.result = result
    }

    func send(_: URLRequest) async -> ClosedTuneTransportResult {
        count += 1
        return result
    }

    func requestCount() -> Int { count }
}

private struct AlwaysAuthorizedPlaybackAuthorization: LivePlaybackAuthorizing {
    func authorizePlayback(for _: LiveChannelID) async -> LivePlaybackAuthorization {
        .authorized
    }
}

private struct UnavailablePlaybackAuthorization: LivePlaybackAuthorizing {
    func authorizePlayback(for _: LiveChannelID) async -> LivePlaybackAuthorization {
        .unavailable
    }
}

private actor BlockingPlaybackDriver: LivePlaybackDriving {
    private var continuations: [LiveChannelID: CheckedContinuation<LivePlaybackDriverResult, Never>] = [:]
    private var waiters: [LiveChannelID: CheckedContinuation<Void, Never>] = [:]
    private var started: Set<LiveChannelID> = []

    func tune(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult {
        started.insert(channelID)
        waiters.removeValue(forKey: channelID)?.resume()
        return await withCheckedContinuation { continuations[channelID] = $0 }
    }

    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }

    func waitForTune(of channelID: LiveChannelID) async {
        guard !started.contains(channelID) else { return }
        await withCheckedContinuation { waiters[channelID] = $0 }
    }

    func confirmTune(of channelID: LiveChannelID) {
        continuations.removeValue(forKey: channelID)?.resume(returning: .confirmed(.playing(channelID)))
    }
}
