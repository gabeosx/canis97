import AVFoundation
import XCTest
@_spi(Playback) import SiriusXMClient
@testable import Canis97

@MainActor
final class SemanticListeningPresentationTests: XCTestCase {
    func testOnlyAnEntitledStateConstructsTheListeningModelWithTheInjectedFlow() async {
        let flow = ControlledCatalogFlow()

        XCTAssertNil(ListeningPresentationModel.makeIfEntitled(.signedOut, flow: flow))
        let entitled = try? XCTUnwrap(ListeningPresentationModel.makeIfEntitled(.entitled, flow: flow))

        XCTAssertNotNil(entitled)
        let calls = await flow.callCount()
        XCTAssertEqual(calls, 0)
    }

    func testRefreshIsSingleFlightAndPublishesTheSemanticSnapshot() async throws {
        let flow = ControlledCatalogFlow()
        let model = ListeningPresentationModel(flow: flow)

        let first = try XCTUnwrap(model.refresh())
        XCTAssertNil(model.refresh())
        await flow.waitForCall(1)
        await flow.complete(
            .snapshot(LiveCatalogSnapshot(
                channels: [LiveChannel(id: LiveChannelID("fixture-current"), name: "Current")],
                freshness: .fresh
            )),
            at: 0
        )
        await first.value

        let calls = await flow.callCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.state.snapshot?.channels.map(\.id), [LiveChannelID("fixture-current")])
        XCTAssertEqual(model.state.freshness, .fresh)
    }

    func testAnOlderRefreshCannotReplaceTheCurrentSnapshot() async throws {
        let flow = ControlledCatalogFlow()
        let model = ListeningPresentationModel(flow: flow)
        let older = try XCTUnwrap(model.refresh())
        await flow.waitForCall(1)

        model.reset()
        let current = try XCTUnwrap(model.refresh())
        await flow.waitForCall(2)
        await flow.complete(
            .snapshot(LiveCatalogSnapshot(
                channels: [LiveChannel(id: LiveChannelID("fixture-current"), name: "Current")],
                freshness: .fresh
            )),
            at: 1
        )
        await current.value
        await flow.complete(
            .snapshot(LiveCatalogSnapshot(
                channels: [LiveChannel(id: LiveChannelID("fixture-older"), name: "Older")],
                freshness: .fresh
            )),
            at: 0
        )
        await older.value

        XCTAssertEqual(model.state.snapshot?.channels.map(\.id), [LiveChannelID("fixture-current")])
    }

    func testSelectionStoresOnlyTheStableIdentityWithoutRefreshOrPlaybackWork() async {
        let flow = ControlledCatalogFlow()
        let model = ListeningPresentationModel(flow: flow)
        let selected = LiveChannelID("fixture-selection")

        model.select(selected)

        XCTAssertEqual(model.selectedChannelID, selected)
        let calls = await flow.callCount()
        XCTAssertEqual(calls, 0)
    }

    func testStaleCatalogRemainsBrowsableAndIsExplicitlyMarkedStale() async throws {
        let flow = ControlledCatalogFlow()
        let model = ListeningPresentationModel(flow: flow)
        let task = try XCTUnwrap(model.refresh())
        await flow.waitForCall(1)
        await flow.complete(
            .stale(
                snapshot: LiveCatalogSnapshot(
                    channels: [LiveChannel(id: LiveChannelID("fixture-stale"), name: "Stale")],
                    freshness: .stale
                ),
                failure: .unsupportedResponse
            ),
            at: 0
        )
        await task.value

        model.select(LiveChannelID("fixture-stale"))
        XCTAssertEqual(model.state.freshness, .stale)
        XCTAssertEqual(model.selectedChannelID, LiveChannelID("fixture-stale"))
    }
}

@MainActor
final class ListeningCompositionTests: XCTestCase {
    func testProductionCompositionConstructsAConcreteClientBackedPlaybackResolver() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("SiriusMac/Authentication/AuthenticationView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("SiriusXMPlaybackResolver(client: composedClient)"))
        XCTAssertFalse(source.contains("self.playbackCoordinator = PlaybackCoordinator()"))
    }

    func testProductionCompositionExplicitlyOwnsSystemRecoveryObservers() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "SiriusMac/Authentication/AuthenticationView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("networkObserver: SystemNetworkPathObserver()"))
        XCTAssertTrue(source.contains("workspaceObserver: SystemWorkspacePowerObserver()"))
    }

    func testLatePlaybackConfirmationPropagatesFromCoordinatorToPresentationModel() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let model = ListeningPresentationModel(
            flow: ControlledCatalogFlow(),
            playbackCoordinator: coordinator
        )
        let channel = LiveChannelID("fixture-observed-presentation")
        model.select(channel)

        let tune = try! XCTUnwrap(model.tuneSelectedChannel())
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        await runtime.waitForObservation()
        runtime.confirmReady()
        runtime.confirmPlaying()
        await tune.value

        for _ in 0 ..< 10 {
            if model.playbackState == .playing(channel) { return }
            await Task.yield()
        }
        XCTFail("The presentation model did not observe the confirmed playing callback")
    }

    func testPauseSupersedesAnInFlightTuneBeforeItCanInstallOrPlay() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime(autoConfirm: true)
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-pause-supersedes")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel)

        await coordinator.pause()
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        _ = await tune.value

        XCTAssertEqual(runtime.installCount, 0)
        XCTAssertNotEqual(coordinator.state, .playing(channel))
    }

    func testTuneInstallsAnObservedItemBeforeReadinessAndWaitsForConfirmedPlayback() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-confirmed-playback")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        await runtime.waitForObservation()

        XCTAssertEqual(runtime.events(), [.observed, .installed])
        XCTAssertEqual(coordinator.state, .idle)

        runtime.confirmReady()
        XCTAssertEqual(runtime.events(), [.observed, .installed, .playRequested])
        XCTAssertEqual(coordinator.state, .idle)

        runtime.confirmPlaying()
        _ = await tune.value

        XCTAssertEqual(coordinator.state, .playing(channel))
        XCTAssertEqual(runtime.playerCount, 1)
    }

    func testResumeReresolvesTheSelectedIdentityAtTheLiveEdgeAndStopIsIdempotent() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime(autoConfirm: true)
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-live-edge")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel, count: 1)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        _ = await tune.value

        await coordinator.pause()
        XCTAssertEqual(coordinator.state, .paused)

        let resume = Task { await coordinator.resumeLiveEdge() }
        await resolver.waitForResolution(of: channel, count: 2)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        _ = await resume.value

        let resolutionCount = await resolver.calls(for: channel)
        XCTAssertEqual(resolutionCount, 2)
        XCTAssertEqual(runtime.playerCount, 1)
        XCTAssertEqual(runtime.installCount, 2)
        XCTAssertEqual(coordinator.state, .playing(channel))

        let clearsBeforeStop = runtime.clearCount
        await coordinator.stop()
        await coordinator.stop()

        XCTAssertEqual(runtime.clearCount, clearsBeforeStop + 1)
        XCTAssertEqual(coordinator.state, .stopped)
        XCTAssertNil(coordinator.selectedChannelID)
    }

    func testPauseDoesNotResumeAcrossAConnectivityTransition() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime(autoConfirm: true)
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-paused-network")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        _ = await tune.value
        await coordinator.pause()

        let callsBeforeSignals = await resolver.calls(for: channel)
        let installsBeforeSignals = runtime.installCount
        let eventsBeforeSignals = runtime.events()
        coordinator.handleRecoverySignal(.networkBecameUnavailable)
        coordinator.handleRecoverySignal(.networkBecameAvailable)
        for _ in 0 ..< 5 { await Task.yield() }

        let callsAfterSignals = await resolver.calls(for: channel)
        XCTAssertEqual(callsAfterSignals, callsBeforeSignals)
        XCTAssertEqual(runtime.installCount, installsBeforeSignals)
        XCTAssertEqual(runtime.events(), eventsBeforeSignals)
        XCTAssertEqual(coordinator.state, .paused)
    }

    func testPauseDoesNotResumeAcrossSleepAndWake() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime(autoConfirm: true)
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let channel = LiveChannelID("fixture-paused-sleep")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        _ = await tune.value
        await coordinator.pause()

        let callsBeforeSignals = await resolver.calls(for: channel)
        let installsBeforeSignals = runtime.installCount
        let eventsBeforeSignals = runtime.events()
        coordinator.handleRecoverySignal(.willSleep)
        coordinator.handleRecoverySignal(.didWake)
        for _ in 0 ..< 5 { await Task.yield() }

        let callsAfterSignals = await resolver.calls(for: channel)
        XCTAssertEqual(callsAfterSignals, callsBeforeSignals)
        XCTAssertEqual(runtime.installCount, installsBeforeSignals)
        XCTAssertEqual(runtime.events(), eventsBeforeSignals)
        XCTAssertEqual(coordinator.state, .paused)
    }

    func testChannelSwitchSupersedesAStaleResolutionAndFailureIsClosed() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime(autoConfirm: true)
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let first = LiveChannelID("fixture-first")
        let second = LiveChannelID("fixture-second")

        let firstTune = Task { await coordinator.tune(first) }
        await resolver.waitForResolution(of: first)
        let secondTune = Task { await coordinator.tune(second) }
        await resolver.waitForResolution(of: second)
        await resolver.complete(first, with: .available(FixtureMediaHandoff()))
        await resolver.complete(second, with: .failed(.networkUnavailable))
        _ = await firstTune.value
        _ = await secondTune.value

        XCTAssertEqual(runtime.installCount, 0)
        XCTAssertEqual(coordinator.selectedChannelID, second)
        XCTAssertEqual(coordinator.state, .unavailable(.networkUnavailable))
    }

    func testRecoveryCoalescesSignalsAndUsesOneBoundedSameChannelBudget() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime(autoConfirm: true)
        let sleeper = ControlledRecoverySleeper()
        let policy = PlaybackRecoveryPolicy(
            maximumReResolutions: 2,
            stallGrace: 8,
            backoffs: [1, 3]
        )
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            runtime: runtime,
            recoveryPolicy: policy,
            sleeper: sleeper
        )
        let channel = LiveChannelID("fixture-bounded-recovery")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel, count: 1)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        _ = await tune.value

        coordinator.handleRecoverySignal(.stalled)
        coordinator.handleRecoverySignal(.stalled)
        coordinator.handleRecoverySignal(.networkBecameAvailable)
        await sleeper.waitForDelay(8)
        await sleeper.completeNext()
        await sleeper.waitForDelay(1)
        await sleeper.completeNext()
        await resolver.waitForResolution(of: channel, count: 2)
        await resolver.complete(channel, with: .failed(.networkUnavailable))
        await sleeper.waitForDelay(3)
        await sleeper.completeNext()
        await resolver.waitForResolution(of: channel, count: 3)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))

        for _ in 0 ..< 10 {
            if coordinator.state == .playing(channel) { break }
            await Task.yield()
        }
        let recoveryCalls = await resolver.calls(for: channel)
        XCTAssertEqual(recoveryCalls, 3)
        XCTAssertEqual(coordinator.selectedChannelID, channel)
        XCTAssertEqual(coordinator.state, .playing(channel))
    }

    func testOfflineAndStopCancelRecoveryBeforeAnyProviderCall() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime(autoConfirm: true)
        let sleeper = ControlledRecoverySleeper()
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            runtime: runtime,
            recoveryPolicy: PlaybackRecoveryPolicy(maximumReResolutions: 2, stallGrace: 8, backoffs: [1, 3]),
            sleeper: sleeper
        )
        let channel = LiveChannelID("fixture-offline-recovery")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel, count: 1)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        _ = await tune.value

        coordinator.handleRecoverySignal(.networkBecameUnavailable)
        coordinator.handleRecoverySignal(.stalled)
        await Task.yield()
        let offlineCalls = await resolver.calls(for: channel)
        XCTAssertEqual(offlineCalls, 1)

        coordinator.handleRecoverySignal(.networkBecameAvailable)
        coordinator.handleRecoverySignal(.stalled)
        // A pending offline incident resumes on reconnect without another stall
        // grace period, so its first scheduled delay is the bounded retry
        // backoff. Stopping there proves no resolver call can escape teardown.
        await sleeper.waitForDelay(1)
        await coordinator.stop()
        await sleeper.completeNext()
        for _ in 0 ..< 5 { await Task.yield() }
        let stoppedCalls = await resolver.calls(for: channel)
        XCTAssertEqual(stoppedCalls, 1)
        XCTAssertEqual(coordinator.state, .stopped)
        XCTAssertNil(coordinator.selectedChannelID)
    }

    func testPauseSupersedesAnActiveRecoveryBeforeItCanInstallOrPlay() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime(autoConfirm: true)
        let sleeper = ControlledRecoverySleeper()
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            runtime: runtime,
            recoveryPolicy: PlaybackRecoveryPolicy(maximumReResolutions: 2, stallGrace: 8, backoffs: [1, 3]),
            sleeper: sleeper
        )
        let channel = LiveChannelID("fixture-pause-recovery")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel, count: 1)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        _ = await tune.value
        let installsBeforePause = runtime.installCount

        coordinator.handleRecoverySignal(.stalled)
        await sleeper.waitForDelay(8)
        await sleeper.completeNext()
        await sleeper.waitForDelay(1)
        await sleeper.completeNext()
        await resolver.waitForResolution(of: channel, count: 2)

        await coordinator.pause()
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        for _ in 0 ..< 10 { await Task.yield() }

        XCTAssertEqual(runtime.installCount, installsBeforePause)
        XCTAssertNotEqual(coordinator.state, .playing(channel))
    }

    func testFirstReconnectStartsOnePendingSameChannelRecoveryWithoutAnotherSignal() async {
        let resolver = ControlledPlaybackResolver()
        let runtime = RecordingPlaybackRuntime(autoConfirm: true)
        let sleeper = ControlledRecoverySleeper()
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            runtime: runtime,
            recoveryPolicy: PlaybackRecoveryPolicy(maximumReResolutions: 2, stallGrace: 8, backoffs: [1, 3]),
            sleeper: sleeper
        )
        let channel = LiveChannelID("fixture-reconnect-recovery")

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitForResolution(of: channel, count: 1)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        _ = await tune.value

        coordinator.handleRecoverySignal(.networkBecameUnavailable)
        coordinator.handleRecoverySignal(.networkBecameAvailable)
        coordinator.handleRecoverySignal(.networkBecameAvailable)
        await sleeper.waitForDelay(1)
        await sleeper.completeNext()
        await resolver.waitForResolution(of: channel, count: 2)
        await resolver.complete(channel, with: .available(FixtureMediaHandoff()))
        for _ in 0 ..< 10 {
            if coordinator.state == .playing(channel) { break }
            await Task.yield()
        }

        let calls = await resolver.calls(for: channel)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(coordinator.selectedChannelID, channel)
        XCTAssertEqual(coordinator.state, .playing(channel))
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
                credential: try! renewableTestCredential(accessToken: "synthetic-credential")
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
            credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
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
            credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
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
            credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
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
                credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
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
            credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
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
            credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
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
                credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
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
                credential: try! renewableTestCredential(accessToken: "synthetic-credential")
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
        XCTAssertEqual(source["trackResumeSupported"] as? Bool, false)
        let clock = try XCTUnwrap(request.value(forHTTPHeaderField: "x-sxm-clock"))
        XCTAssertNotNil(clock.range(of: #"^\[\d+,\d+\]$"#, options: .regularExpression))
    }

    func testTuneContractRejectsMutatedBrowserProvenBodyAndClockThenAcceptsTheOriginal() throws {
        let request = try XCTUnwrap(
            ClosedTuneRequestContract.makeRequest(
                credential: try! renewableTestCredential(accessToken: "synthetic-credential")
            )
        )
        let originalBody = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: originalBody) as? [String: Any])
        let sources = try XCTUnwrap(object["sources"] as? [[String: Any]])
        var source = try XCTUnwrap(sources.first)

        var mutated = request
        source["trackResumeSupported"] = true
        mutated.httpBody = try JSONSerialization.data(withJSONObject: ["sources": [source]])
        XCTAssertFalse(ClosedTuneRequestContract.isExact(mutated))

        mutated.httpBody = originalBody
        XCTAssertTrue(ClosedTuneRequestContract.isExact(mutated))

        mutated.setValue("not-a-logical-clock", forHTTPHeaderField: "x-sxm-clock")
        XCTAssertFalse(ClosedTuneRequestContract.isExact(mutated))

        mutated = request
        mutated.httpBody = try JSONSerialization.data(withJSONObject: ["sources": []])
        XCTAssertFalse(ClosedTuneRequestContract.isExact(mutated))

        mutated.httpBody = originalBody
        XCTAssertTrue(ClosedTuneRequestContract.isExact(mutated))
    }

    func testTuneTransportCancelsEveryRedirect() {
        XCTAssertEqual(ClosedTuneTransport.redirectDecision, .cancel)
    }

    func testTuneRunNeedsAResourceAllowlistDecisionWithoutExposingTheResource() async {
        let adapter = ClosedTuneObservationAdapter(
            credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
            transport: RecordingTuneTransport(
                result: .response(
                    statusCode: 200,
                    contentType: "application/json",
                    body: Data(
                        #"{"source":{"id":"194adbca-34d6-cb94-b153-3488ee563308","type":"channel-linear","streams":[{"urls":[{"url":"https://unapproved.example.invalid/stream.m3u8","encryptionKeyId":"synthetic-key","isPrimary":true,"name":"synthetic","validUntil":"synthetic"}],"metadata":{"live":{}},"mtc":{}}]}}"#.utf8
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
            credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
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
                credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
                transport: RecordingTuneTransport(result: response)
            )
            XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)
            let result = await adapter.runTune()
            XCTAssertEqual(result, .terminal(protection))
            XCTAssertEqual(adapter.observations.map(\.protection), [protection])
            XCTAssertEqual(adapter.state, .closed(.terminalObservation))
        }
    }

    func testTuneRunClassifiesKnownClientStatusAtomsWithoutAssumingHumanVerification() async {
        let cases: [(Int, ClosedTuneFailure)] = [
            (400, .http400),
            (404, .http404),
            (409, .http409),
            (422, .http422),
        ]

        for (statusCode, failure) in cases {
            let adapter = ClosedTuneObservationAdapter(
                credentialLoader: { .available(try! renewableTestCredential(accessToken: "synthetic-credential")) },
                transport: RecordingTuneTransport(
                    result: .response(
                        statusCode: statusCode,
                        contentType: "application/json",
                        body: Data(#"{"untrusted":"challenge"}"#.utf8)
                    )
                )
            )

            XCTAssertEqual(adapter.begin(entitlement: .entitled), .started)
            let result = await adapter.runTune()

            XCTAssertEqual(result, .classifiedTerminal(.unknownContract, failure))
            XCTAssertEqual(adapter.observations.map(\.protection), [.unknownContract])
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

private final class FixtureMediaHandoff: SiriusXMAppleMediaHandoff, @unchecked Sendable {
    @MainActor
    func makePlayerItem() -> AVPlayerItem? {
        AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
    }
}

@MainActor
private final class RecordingPlaybackRuntime: PlaybackPlayerRuntime {
    enum Event: Equatable {
        case observed
        case installed
        case playRequested
        case pauseRequested
    }

    private let autoConfirm: Bool
    private var ready: (@MainActor @Sendable () -> Void)?
    private var playing: (@MainActor @Sendable () -> Void)?
    private var paused: (@MainActor @Sendable () -> Void)?
    private var failure: (@MainActor @Sendable (LiveListeningFailure) -> Void)?
    private var observationWaiter: CheckedContinuation<Void, Never>?
    private var hasInstalledItem = false
    private var recordedEvents: [Event] = []

    private(set) var playerCount = 1
    private(set) var installCount = 0
    private(set) var clearCount = 0

    init(autoConfirm: Bool = false) {
        self.autoConfirm = autoConfirm
    }

    func observe(
        _: AVPlayerItem,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) -> any PlaybackItemObserving {
        ready = onReady
        playing = onPlaying
        paused = onPaused
        failure = onFailure
        recordedEvents.append(.observed)
        observationWaiter?.resume()
        observationWaiter = nil
        if autoConfirm {
            onReady()
        }
        return TestItemObservation()
    }

    func install(_: AVPlayerItem) {
        hasInstalledItem = true
        installCount += 1
        recordedEvents.append(.installed)
        if autoConfirm { ready?() }
    }

    func requestPlay() {
        recordedEvents.append(.playRequested)
        if autoConfirm { playing?() }
    }

    func requestPause() {
        recordedEvents.append(.pauseRequested)
        if autoConfirm { paused?() }
    }

    func clearCurrentItem() {
        guard hasInstalledItem else { return }
        hasInstalledItem = false
        clearCount += 1
    }

    func waitForObservation() async {
        guard ready == nil else { return }
        await withCheckedContinuation { observationWaiter = $0 }
    }

    func confirmReady() {
        ready?()
    }

    func confirmPlaying() {
        playing?()
    }

    func events() -> [Event] {
        recordedEvents
    }
}

@MainActor
private final class TestItemObservation: PlaybackItemObserving {
    func cancel() {}
}

private actor ControlledRecoverySleeper: PlaybackRecoverySleeping {
    private var delays: [TimeInterval] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var waiters: [TimeInterval: CheckedContinuation<Void, Never>] = [:]

    func sleep(for seconds: TimeInterval) async {
        delays.append(seconds)
        waiters.removeValue(forKey: seconds)?.resume()
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitForDelay(_ seconds: TimeInterval) async {
        guard delays.contains(seconds) else {
            await withCheckedContinuation { waiters[seconds] = $0 }
            return
        }
    }

    func completeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

private actor ControlledPlaybackResolver: PlaybackResolving {
    private var counts: [LiveChannelID: Int] = [:]
    private var continuations: [LiveChannelID: [CheckedContinuation<PlaybackResourceResolution, Never>]] = [:]
    private var waiters: [LiveChannelID: [Int: CheckedContinuation<Void, Never>]] = [:]

    func resolve(for channelID: LiveChannelID) async -> PlaybackResourceResolution {
        let count = (counts[channelID] ?? 0) + 1
        counts[channelID] = count
        waiters[channelID]?[count]?.resume()
        waiters[channelID]?[count] = nil
        return await withCheckedContinuation { continuation in
            continuations[channelID, default: []].append(continuation)
        }
    }

    func waitForResolution(of channelID: LiveChannelID, count: Int = 1) async {
        guard (counts[channelID] ?? 0) < count else { return }
        await withCheckedContinuation { continuation in
            waiters[channelID, default: [:]][count] = continuation
        }
    }

    func complete(_ channelID: LiveChannelID, with result: PlaybackResourceResolution) {
        guard var values = continuations[channelID], !values.isEmpty else { return }
        let continuation = values.removeFirst()
        continuations[channelID] = values
        continuation.resume(returning: result)
    }

    func calls(for channelID: LiveChannelID) -> Int {
        counts[channelID] ?? 0
    }
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

private actor ControlledCatalogFlow: ListeningFlow {
    private var calls = 0
    private var continuations: [CheckedContinuation<CatalogAvailability, Never>] = []
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func catalog() async -> CatalogAvailability {
        calls += 1
        waiters.removeValue(forKey: calls)?.resume()
        return await withCheckedContinuation { continuations.append($0) }
    }

    func callCount() -> Int { calls }

    func waitForCall(_ expected: Int) async {
        guard calls < expected else { return }
        await withCheckedContinuation { waiters[expected] = $0 }
    }

    func complete(_ result: CatalogAvailability, at index: Int) {
        continuations.remove(at: index).resume(returning: result)
    }
}
