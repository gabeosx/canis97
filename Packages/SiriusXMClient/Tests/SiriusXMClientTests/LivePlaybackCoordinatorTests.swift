import AVFoundation
import Testing
@_spi(Playback) @testable import SiriusXMClient

@Suite("Provider-neutral live playback contracts")
struct LivePlaybackCoordinatorTests {
    @Test("stream resolution keeps current authorization failures distinct")
    func resolutionHasClosedCurrentAuthorizationFailures() {
        #expect(
            LiveStreamResolutionAvailability.failed(.authenticationUnavailable)
                != .failed(.entitlementUnavailable)
        )
        #expect(
            LiveStreamResolutionAvailability.failed(.protectedControl)
                != .failed(.malformedResource)
        )
    }

    @Test("phase two contracts cannot create transport requests or provider-operation calls")
    func phaseTwoContractsRemainOfflineScaffolding() {
        for operation in SiriusXMRequestContract.liveListeningOperations {
            #expect(throws: SiriusXMRequestContractError.self) {
                try SiriusXMRequestContract.makeRequest(for: operation, authorization: "fixture-material")
            }
        }
    }

    @Test("tune publishes only after a fake resolver and player both confirm")
    func publishesConfirmedTuneState() async {
        let channel = LiveChannelID("fixture-command")
        let resolver = RecordingResolver(results: [.ready])
        let player = BlockingEventDriver()
        let coordinator = LivePlaybackContractCoordinator(resolver: resolver, player: player, recoveryBudget: 2)

        let tune = Task { await coordinator.tune(channel) }
        await player.waitUntilStartRequested()

        #expect(await coordinator.currentState == .awaitingLiveContract)
        await player.confirmStart(for: channel)
        #expect(await tune.value == .playing(channel))
        #expect(await coordinator.currentState == .playing(channel))
    }

    @Test("a newer command ignores an obsolete confirmed completion")
    func ignoresSupersededCompletion() async {
        let first = LiveChannelID("fixture-first")
        let second = LiveChannelID("fixture-second")
        let resolver = RecordingResolver(results: [.ready, .ready])
        let player = PerChannelBlockingEventDriver()
        let coordinator = LivePlaybackContractCoordinator(resolver: resolver, player: player, recoveryBudget: 1)

        let firstTune = Task { await coordinator.tune(first) }
        await player.waitUntilStartRequested(for: first)
        let secondTune = Task { await coordinator.tune(second) }
        await player.waitUntilStartRequested(for: second)

        await player.confirmStart(for: first)
        await player.confirmStart(for: second)

        _ = await firstTune.value
        #expect(await secondTune.value == .playing(second))
        #expect(await coordinator.currentState == .playing(second))
    }

    @Test("same-channel recovery uses its finite budget and retains the selected identity")
    func recoveryIsFiniteAndKeepsTheSelection() async {
        let channel = LiveChannelID("fixture-recovery")
        let resolver = RecordingResolver(results: [.ready, .failed(.networkUnavailable), .failed(.networkUnavailable), .failed(.networkUnavailable)])
        let player = RecordingEventDriver()
        let coordinator = LivePlaybackContractCoordinator(resolver: resolver, player: player, recoveryBudget: 3)

        _ = await coordinator.tune(channel)
        #expect(await coordinator.recover() == .unavailable(.recoveryExhausted))
        #expect(await resolver.callCount == 4)
        #expect(await coordinator.selectedChannelID == channel)
        #expect(await coordinator.currentState == .unavailable(.recoveryExhausted))
    }

    @Test("cancelled recovery stops before later budget attempts")
    func cancellationStopsRecovery() async {
        let channel = LiveChannelID("fixture-cancel")
        let resolver = BlockingResolver()
        let coordinator = LivePlaybackContractCoordinator(resolver: resolver, player: RecordingEventDriver(), recoveryBudget: 3)

        let tune = Task { await coordinator.tune(channel) }
        await resolver.waitUntilStarted()
        await resolver.release(.ready)
        _ = await tune.value

        let recovery = Task { await coordinator.recover() }
        await resolver.waitUntilStarted()
        recovery.cancel()
        await resolver.release(.failed(.networkUnavailable))

        #expect(await recovery.value == .unavailable(.cancelled))
        #expect(await resolver.callCount == 2)
    }

    @Test("fixed live resolution executes only tune, resource, and the required key step")
    func fixedResolutionHasExactOperationCeilings() async {
        let operations = RecordingFixedLiveOperations(keyRequirement: .required)
        let resolver = FixedLiveStreamResolver(operations: operations)

        let result = await resolver.resolveLiveStream(for: LiveChannelID("fixture-fixed-contract"))

        guard case .available = result else {
            Issue.record("Expected one opaque app handoff")
            return
        }
        #expect(await operations.tuneCount == 1)
        #expect(await operations.resourceCount == 1)
        #expect(await operations.keyCount == 1)
    }

    @Test("not-required key resolution never invokes the key operation")
    func notRequiredKeySkipsTheKeyOperation() async {
        let operations = RecordingFixedLiveOperations(keyRequirement: .notRequired)
        let resolver = FixedLiveStreamResolver(operations: operations)

        let result = await resolver.resolveLiveStream(for: LiveChannelID("fixture-no-key"))

        guard case .available = result else {
            Issue.record("Expected one opaque app handoff")
            return
        }
        #expect(await operations.tuneCount == 1)
        #expect(await operations.resourceCount == 1)
        #expect(await operations.keyCount == 0)
    }

    @Test("invalidating a resolving generation prevents its opaque handoff from escaping")
    func invalidationSupersedesAnInFlightResolution() async {
        let operations = BlockingFixedLiveOperations()
        let resolver = FixedLiveStreamResolver(operations: operations)

        let resolution = Task {
            await resolver.resolveLiveStream(for: LiveChannelID("fixture-invalidated"))
        }
        await operations.waitForTune()
        await resolver.invalidate()
        await operations.completeTune()

        #expect(await resolution.value == .failed(.superseded))
        #expect(await operations.resourceCount == 0)
        #expect(await operations.keyCount == 0)
    }

    @Test("an older tune cannot overwrite a newer operation context")
    func outOfOrderTuneKeepsResourceAndKeyBoundToNewerContext() async {
        let older = LiveChannelID("fixture-older")
        let newer = LiveChannelID("fixture-newer")
        let operations = OutOfOrderFixedLiveOperations(older: older, newer: newer)
        let resolver = FixedLiveStreamResolver(operations: operations)

        let first = Task { await resolver.resolveLiveStream(for: older) }
        await operations.waitUntilOlderTuneStarted()

        let second = await resolver.resolveLiveStream(for: newer)
        guard case .available = second else {
            Issue.record("Expected the newer resolution to produce its own opaque handoff")
            return
        }

        await operations.completeOlderTune()
        #expect(await first.value == .failed(.superseded))
        #expect(await operations.resourceContexts == ["fixture-newer"])
        #expect(await operations.keyContexts == ["fixture-newer"])
    }

    @Test("production composition uses the bounded selected-channel adapter")
    func productionCompositionUsesTheBoundedSelectedChannelAdapter() async {
        let transport = RecordingProductionLiveTransport()
        let client = SiriusXMClient(
            sessionCoordinator: makeActiveSession(),
            fixedLiveTransport: transport
        )

        #expect(await client.authenticate() == .authenticatedPendingEntitlement)
        let result = await client.resolveLiveStream(for: LiveChannelID("fixture-selected-channel"))

        guard case .available = result else {
            Issue.record("Expected the bounded production resolver to produce only an opaque handoff")
            return
        }
        #expect(await transport.operations == [.tune, .playbackKey])
    }

    @Test("production adapter keeps all unsupported operations unmaterializable")
    func productionAdapterKeepsUnsupportedOperationsUnmaterializable() {
        #expect(SiriusXMRequestContract.liveListeningOperations.allSatisfy { !$0.isTransportMaterializable })
    }

    @Test("live redirect delegates isolate a redirected task from a sibling failure")
    func liveRedirectDelegatesAreTaskLocal() {
        let redirected = PerRequestRedirectDelegate()
        let sibling = PerRequestRedirectDelegate()
        let url = URL(string: "https://fixture.invalid/redirect")!
        let task = URLSession.shared.dataTask(with: url)
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let decision = LiveRedirectDecisionBox(URLRequest(url: url))

        redirected.urlSession(
            URLSession.shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: url),
            completionHandler: { decision.record($0) }
        )

        #expect(decision.value == nil)
        #expect(redirected.didObserveRedirect)
        #expect(!sibling.didObserveRedirect)
    }
}

private enum FixtureKeyRequirement: Sendable {
    case required
    case notRequired
}

private actor RecordingFixedLiveOperations: FixedLiveStreamOperating {
    let keyRequirement: FixtureKeyRequirement
    private(set) var tuneCount = 0
    private(set) var resourceCount = 0
    private(set) var keyCount = 0

    init(keyRequirement: FixtureKeyRequirement) {
        self.keyRequirement = keyRequirement
    }

    func authorizeTune(for _: LiveChannelID) async -> FixedLiveTuneAuthorization {
        tuneCount += 1
        return .authorized(FixtureLiveOperationContext())
    }

    func resolveResource(in _: any FixedLiveOperationContext) async -> FixedLiveResourceResolution {
        resourceCount += 1
        return .resolved(FixtureAppleMediaHandoff(), keyRequirement: keyRequirement == .required ? .required : .notRequired)
    }

    func authorizePlaybackKey(for _: any FixedLiveOperationContext) async -> LiveStreamResolutionFailure? {
        keyCount += 1
        return nil
    }
}

private actor BlockingFixedLiveOperations: FixedLiveStreamOperating {
    private var tuneContinuation: CheckedContinuation<FixedLiveTuneAuthorization, Never>?
    private var tuneWaiter: CheckedContinuation<Void, Never>?
    private var started = false
    private(set) var resourceCount = 0
    private(set) var keyCount = 0

    func authorizeTune(for _: LiveChannelID) async -> FixedLiveTuneAuthorization {
        started = true
        tuneWaiter?.resume()
        tuneWaiter = nil
        return await withCheckedContinuation { tuneContinuation = $0 }
    }

    func resolveResource(in _: any FixedLiveOperationContext) async -> FixedLiveResourceResolution {
        resourceCount += 1
        return .failed(.resourceUnavailable)
    }

    func authorizePlaybackKey(for _: any FixedLiveOperationContext) async -> LiveStreamResolutionFailure? {
        keyCount += 1
        return .unsupportedProtection
    }

    func waitForTune() async {
        guard !started else { return }
        await withCheckedContinuation { tuneWaiter = $0 }
    }

    func completeTune() {
        tuneContinuation?.resume(returning: .authorized(FixtureLiveOperationContext()))
        tuneContinuation = nil
    }
}

private struct FixtureLiveOperationContext: FixedLiveOperationContext {}

private actor OutOfOrderFixedLiveOperations: FixedLiveStreamOperating {
    private let older: LiveChannelID
    private let newer: LiveChannelID
    private var olderTuneContinuation: CheckedContinuation<FixedLiveTuneAuthorization, Never>?
    private var olderTuneWaiter: CheckedContinuation<Void, Never>?
    private var olderTuneStarted = false
    private(set) var resourceContexts: [String] = []
    private(set) var keyContexts: [String] = []

    init(older: LiveChannelID, newer: LiveChannelID) {
        self.older = older
        self.newer = newer
    }

    func authorizeTune(for channelID: LiveChannelID) async -> FixedLiveTuneAuthorization {
        if channelID == older {
            olderTuneStarted = true
            olderTuneWaiter?.resume()
            olderTuneWaiter = nil
            return await withCheckedContinuation { olderTuneContinuation = $0 }
        }
        return .authorized(FixtureChannelOperationContext(channelID: newer))
    }

    func resolveResource(in context: any FixedLiveOperationContext) async -> FixedLiveResourceResolution {
        guard let context = context as? FixtureChannelOperationContext else {
            return .failed(.resourceUnavailable)
        }
        resourceContexts.append(context.channelID.rawValue)
        return .resolved(FixtureAppleMediaHandoff(), keyRequirement: .required)
    }

    func authorizePlaybackKey(for context: any FixedLiveOperationContext) async -> LiveStreamResolutionFailure? {
        guard let context = context as? FixtureChannelOperationContext else {
            return .resourceUnavailable
        }
        keyContexts.append(context.channelID.rawValue)
        return nil
    }

    func waitUntilOlderTuneStarted() async {
        if olderTuneStarted { return }
        await withCheckedContinuation { olderTuneWaiter = $0 }
    }

    func completeOlderTune() {
        olderTuneContinuation?.resume(returning: .authorized(FixtureChannelOperationContext(channelID: older)))
        olderTuneContinuation = nil
    }
}

private struct FixtureChannelOperationContext: FixedLiveOperationContext {
    let channelID: LiveChannelID
}

private struct FixtureAppleMediaHandoff: SiriusXMAppleMediaHandoff {
    @MainActor func makePlayerItem() -> AVPlayerItem? { nil }
}

private final class LiveRedirectDecisionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?

    init(_ value: URLRequest?) { stored = value }

    var value: URLRequest? { lock.withLock { stored } }

    func record(_ value: URLRequest?) {
        lock.withLock { stored = value }
    }
}

private enum ProductionOperation: Sendable, Equatable {
    case tune
    case playbackKey
}

private actor RecordingProductionLiveTransport: FixedLiveTransporting {
    private(set) var operations: [ProductionOperation] = []

    func tune(
        for channelID: LiveChannelID,
        using _: AuthenticationCredential
    ) async -> NativeTransportResponse {
        operations.append(.tune)
        return response(
            #"{"source":{"id":"\#(channelID.rawValue)","type":"channel-linear","streams":[{"urls":[{"url":"https://live-akc-prod-device.streaming.siriusxm.com/fixture","encryptionKeyId":"fixture-key"}]}]}}"#
        )
    }

    func playbackKey(
        for _: FixedLivePlaybackKeyID,
        using _: AuthenticationCredential
    ) async -> NativeTransportResponse {
        operations.append(.playbackKey)
        return response(#"{"keyId":"fixture-key","key":"fixture-key-material"}"#)
    }

    private func response(_ body: String) -> NativeTransportResponse {
        NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(body.utf8)
        )
    }
}

private func makeActiveSession() -> SessionCoordinator {
    SessionCoordinator(
        credentialSource: ProductionCredentialSource(),
        authenticationVerifier: ProductionAuthenticationVerifier(),
        entitlementVerifier: ProductionEntitlementVerifier(),
        credentialStore: ProductionCredentialStore(),
        clock: ProductionClock(),
        diagnostics: ProductionDiagnostics()
    )
}

private actor ProductionCredentialSource: CredentialSource {
    func credential() async -> AuthenticationCredential? {
        AuthenticationCredential(volatileMaterial: Data("fixture-credential".utf8))
    }
}

private actor ProductionAuthenticationVerifier: NativeAuthenticationVerifying {
    func verifyAuthentication(using _: AuthenticationCredential) async -> NativeTransportResponse {
        NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"fixture":"authenticated"}"#.utf8)
        )
    }
}

private actor ProductionEntitlementVerifier: NativeEntitlementVerifying {
    func verifyEntitlement(using _: AuthenticationCredential) async -> NativeTransportResponse {
        NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"items":[{"state":"active"}]}"#.utf8)
        )
    }
}

private actor ProductionCredentialStore: CredentialStore {
    func save(_: AuthenticationCredential) async throws {}
    func erase() async throws {}
}

private struct ProductionClock: SessionClock {
    func now() -> Date { .distantPast }
}

private actor ProductionDiagnostics: SessionDiagnostics {
    func record(_: SessionDiagnosticEvent) async {}
}

private actor RecordingResolver: LivePlaybackResolving {
    private var results: [LivePlaybackResolution]
    private(set) var callCount = 0

    init(results: [LivePlaybackResolution]) { self.results = results }

    func resolve(_: LiveChannelID) async -> LivePlaybackResolution {
        callCount += 1
        return results.removeFirst()
    }
}

private actor BlockingResolver: LivePlaybackResolving {
    private var continuation: CheckedContinuation<LivePlaybackResolution, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var started = false
    private(set) var callCount = 0

    func resolve(_: LiveChannelID) async -> LivePlaybackResolution {
        callCount += 1
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release(_ result: LivePlaybackResolution) {
        started = false
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor RecordingEventDriver: LivePlaybackEventDriving {
    func start(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult { .confirmed(.playing(channelID)) }
    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }
}

private actor BlockingEventDriver: LivePlaybackEventDriving {
    private var startContinuation: CheckedContinuation<LivePlaybackDriverResult, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var started = false

    func start(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { startContinuation = $0 }
    }

    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }

    func waitUntilStartRequested() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func confirmStart(for channelID: LiveChannelID) {
        startContinuation?.resume(returning: .confirmed(.playing(channelID)))
        startContinuation = nil
    }
}

private actor PerChannelBlockingEventDriver: LivePlaybackEventDriving {
    private var continuations: [LiveChannelID: CheckedContinuation<LivePlaybackDriverResult, Never>] = [:]
    private var waiters: [LiveChannelID: CheckedContinuation<Void, Never>] = [:]
    private var started: Set<LiveChannelID> = []

    func start(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult {
        started.insert(channelID)
        waiters.removeValue(forKey: channelID)?.resume()
        return await withCheckedContinuation { continuations[channelID] = $0 }
    }

    func pause() async -> LivePlaybackDriverResult { .confirmed(.paused) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .confirmed(.playing(nil)) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }

    func waitUntilStartRequested(for channelID: LiveChannelID) async {
        guard !started.contains(channelID) else { return }
        await withCheckedContinuation { waiters[channelID] = $0 }
    }

    func confirmStart(for channelID: LiveChannelID) {
        continuations.removeValue(forKey: channelID)?.resume(returning: .confirmed(.playing(channelID)))
    }
}
