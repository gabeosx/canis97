import AVFoundation
import SwiftData
import XCTest
@_spi(Playback) import SiriusXMClient
@testable import SiriusMac

@MainActor
final class WindowLifecyclePolicyTests: XCTestCase {
    func testCompactPolicyUsesFixedSizeAndDistinctAutosaveName() {
        let policy = WindowLifecyclePolicy(role: .compact)

        XCTAssertEqual(policy.defaultContentSize, CGSize(width: 400, height: 288))
        XCTAssertEqual(policy.minimumContentSize, CGSize(width: 400, height: 288))
        XCTAssertFalse(policy.isResizable)
        XCTAssertFalse(policy.allowsFullScreen)
        XCTAssertEqual(policy.frameAutosaveName, "SiriusMac.compact.frame")
    }

    func testLibraryPolicyIsResizableWithSeparateAutosaveName() {
        let policy = WindowLifecyclePolicy(role: .library)

        XCTAssertEqual(policy.defaultContentSize, CGSize(width: 980, height: 700))
        XCTAssertEqual(policy.minimumContentSize, CGSize(width: 760, height: 540))
        XCTAssertTrue(policy.isResizable)
        XCTAssertTrue(policy.allowsFullScreen)
        XCTAssertEqual(policy.frameAutosaveName, "SiriusMac.library.frame")
    }

    func testRestoresOnlyFramesIntersectingAnAvailableScreen() {
        let visibleFrame = CGRect(x: 100, y: 100, width: 400, height: 288)
        let offscreenFrame = CGRect(x: 9_000, y: 9_000, width: 400, height: 288)
        let screens = [CGRect(x: 0, y: 0, width: 1_440, height: 900)]

        XCTAssertEqual(
            WindowFrameRestoration.frameToApply(savedFrame: visibleFrame, screens: screens),
            visibleFrame
        )
        XCTAssertNil(WindowFrameRestoration.frameToApply(savedFrame: offscreenFrame, screens: screens))
    }

    func testCompactCloseRequestsTerminationOnlyOnceWhileLibraryCloseDoesNothing() {
        let terminator = WindowLifecycleTerminatorSpy()
        let compact = WindowLifecyclePolicy(role: .compact, terminator: terminator)
        let library = WindowLifecyclePolicy(role: .library, terminator: terminator)

        compact.windowWillClose()
        compact.windowWillClose()
        library.windowWillClose()

        XCTAssertEqual(terminator.terminationRequestCount, 1)
    }

    func testAlwaysOnTopDefaultsOffPersistsDesiredStateAndAffectsOnlyCompactPolicy() throws {
        let container = try makePreferenceContainer()
        let store = LibraryStore(modelContainer: container)
        let compact = WindowLifecyclePolicy(role: .compact)
        let library = WindowLifecyclePolicy(role: .library)

        XCTAssertFalse(store.alwaysOnTop)
        XCTAssertEqual(compact.windowLevel(alwaysOnTop: store.alwaysOnTop), .normal)

        store.setAlwaysOnTop(true)
        store.setAlwaysOnTop(true)

        XCTAssertTrue(store.alwaysOnTop)
        XCTAssertEqual(compact.windowLevel(alwaysOnTop: store.alwaysOnTop), .floating)
        XCTAssertEqual(library.windowLevel(alwaysOnTop: store.alwaysOnTop), .normal)
        XCTAssertTrue(LibraryStore(modelContainer: container).alwaysOnTop)
    }

    private func makePreferenceContainer() throws -> ModelContainer {
        try ModelContainer(
            for: FavoriteRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

}

@MainActor
private final class WindowLifecycleTerminatorSpy: ApplicationTerminating {
    private(set) var terminationRequestCount = 0

    func requestTermination() {
        terminationRequestCount += 1
    }
}

@MainActor
final class ListeningSessionControllerTests: XCTestCase {
    func testCommandAvailabilityRequiresConfirmedPlaybackAndPreservesPendingCancellation() {
        func availability(
            _ playbackState: LivePlaybackState,
            confirmedChannelID: LiveChannelID? = nil,
            hasCancellablePlayback: Bool = false,
            queueAvailability: QueueDirectionAvailability = .both,
            isTunePending: Bool = false
        ) -> ListeningCommandAvailability {
            ListeningCommandAvailability(
                playbackState: playbackState,
                confirmedChannelID: confirmedChannelID,
                hasCancellablePlayback: hasCancellablePlayback,
                queueAvailability: queueAvailability,
                isTunePending: isTunePending
            )
        }

        let channel = LiveChannelID("fixture-command-availability")

        XCTAssertEqual(availability(.idle), .init(
            playbackState: .idle,
            confirmedChannelID: nil,
            hasCancellablePlayback: false,
            queueAvailability: .none
        ))
        XCTAssertFalse(availability(.idle).playPause)
        XCTAssertFalse(availability(.idle).stop)
        XCTAssertFalse(availability(.awaitingLiveContract, hasCancellablePlayback: true).playPause)
        XCTAssertTrue(availability(.awaitingLiveContract, hasCancellablePlayback: true).stop)
        XCTAssertFalse(availability(.playing(channel), confirmedChannelID: nil).pause)

        let playing = availability(.playing(channel), confirmedChannelID: channel, hasCancellablePlayback: true)
        XCTAssertTrue(playing.pause)
        XCTAssertTrue(playing.playPause)
        XCTAssertTrue(playing.previous)
        XCTAssertTrue(playing.next)
        XCTAssertTrue(playing.stop)

        let pending = availability(
            .playing(channel),
            confirmedChannelID: channel,
            hasCancellablePlayback: true,
            isTunePending: true
        )
        XCTAssertFalse(pending.pause)
        XCTAssertFalse(pending.resumeLive)
        XCTAssertTrue(pending.stop)
        XCTAssertFalse(pending.previous)
        XCTAssertFalse(pending.next)

        let paused = availability(.paused, confirmedChannelID: channel, hasCancellablePlayback: true, queueAvailability: .next)
        XCTAssertTrue(paused.resumeLive)
        XCTAssertTrue(paused.playPause)
        XCTAssertTrue(paused.stop)
        XCTAssertFalse(paused.previous)
        XCTAssertTrue(paused.next)

        let stopped = availability(.stopped)
        XCTAssertFalse(stopped.pause)
        XCTAssertFalse(stopped.resumeLive)
        XCTAssertFalse(stopped.stop)
        XCTAssertFalse(stopped.previous)
        XCTAssertFalse(stopped.next)

        let unavailable = availability(.unavailable(.networkUnavailable), hasCancellablePlayback: true)
        XCTAssertFalse(unavailable.playPause)
        XCTAssertTrue(unavailable.stop)
        XCTAssertFalse(unavailable.previous)
        XCTAssertFalse(unavailable.next)
    }

    func testControllerCommandAvailabilityIsInertBeforeAnySelection() {
        let controller = makeController()

        XCTAssertEqual(
            controller.commandAvailability,
            ListeningCommandAvailability(
                playbackState: .idle,
                confirmedChannelID: nil,
                hasCancellablePlayback: false,
                queueAvailability: .none
            )
        )
    }

    func testReadySessionAutomaticallyLoadsCatalogOnceWithoutRacingManualRecovery() async throws {
        let catalog = ControlledSessionCatalog()
        let controller = makeController(
            client: catalog,
            authenticationModel: AuthenticationPresentationModel(flow: EntitledSessionAuthenticationFlow())
        )

        let signIn = try XCTUnwrap(controller.authenticationModel.signIn())
        await catalog.waitForCatalogRequests(count: 1)

        controller.loadCatalogWhenReady()
        controller.loadCatalogWhenReady()
        XCTAssertNil(controller.listeningModel.refresh())
        let requestCount = await catalog.catalogRequestCount()
        XCTAssertEqual(requestCount, 1)

        await catalog.completeCatalog(with: .snapshot(LiveCatalogSnapshot(
            channels: [LiveChannel(id: LiveChannelID("fixture-ready"), name: "Ready Channel")],
            freshness: .fresh
        )))
        await signIn.value

        for _ in 0 ..< 10 {
            if controller.listeningModel.state.snapshot != nil { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.state.snapshot?.channels.map(\.name), ["Ready Channel"])
    }

    func testControllerRetainsOneCompositionAndCoordinatorAcrossSurfaceHandles() {
        let controller = makeController()

        XCTAssertTrue(controller.composition.playbackCoordinator === controller.playbackCoordinator)
        XCTAssertEqual(controller.compactSurface.coordinatorIdentity, ObjectIdentifier(controller.playbackCoordinator))
        XCTAssertEqual(controller.librarySurface.coordinatorIdentity, ObjectIdentifier(controller.playbackCoordinator))
    }

    func testLibraryTuneRendersOnlyConfirmedPlaybackOnBothSurfaces() async {
        let runtime = SessionPlaybackRuntime()
        let controller = makeController(runtime: runtime)
        let channel = LiveChannelID("fixture-session-confirmation")

        let tune = try! XCTUnwrap(controller.tuneFromLibrary(channel))
        await runtime.waitForObservation()

        XCTAssertNotEqual(controller.librarySurface.playbackState, .playing(channel))
        XCTAssertNotEqual(controller.compactSurface.playbackState, .playing(channel))

        runtime.confirmReady()
        XCTAssertNotEqual(controller.librarySurface.playbackState, .playing(channel))
        runtime.confirmPlaying()
        await tune.value

        for _ in 0 ..< 10 {
            guard controller.librarySurface.activeChannelID == channel,
                  controller.compactSurface.activeChannelID == channel
            else {
                await Task.yield()
                continue
            }
            return
        }
        XCTFail("Both surfaces must render the same confirmed channel")
    }

    func testControllerRecordsARecentOnlyAfterNewConfirmedPlayback() async throws {
        let runtime = SessionPlaybackRuntime()
        let catalog = ControlledSessionCatalog()
        let store = try makeLibraryStore()
        let channel = LiveChannelID("fixture-confirmed-recent")
        let controller = makeController(
            runtime: runtime,
            client: catalog,
            authenticationModel: AuthenticationPresentationModel(flow: EntitledSessionAuthenticationFlow()),
            libraryStore: store
        )

        let signIn = try XCTUnwrap(controller.authenticationModel.signIn())
        await catalog.waitForCatalogRequests(count: 1)
        await catalog.completeCatalog(with: .snapshot(LiveCatalogSnapshot(
            channels: [LiveChannel(id: channel, name: "Confirmed Recent", displayNumber: 99, category: "Test")],
            freshness: .fresh
        )))
        await signIn.value

        for _ in 0 ..< 10 {
            if controller.listeningModel.state.snapshot != nil { break }
            await Task.yield()
        }
        let tune = try XCTUnwrap(controller.tuneFromLibrary(channel))
        await runtime.waitForObservation()
        XCTAssertTrue(store.recents.isEmpty)

        runtime.confirmReady()
        XCTAssertTrue(store.recents.isEmpty)
        runtime.confirmPlaying()
        await tune.value

        for _ in 0 ..< 10 {
            if store.recents.map(\.id) == [channel] { return }
            await Task.yield()
        }
        XCTFail("Only the confirmed playback transition should create a recent")
    }

    func testCompactSurfaceRendersConfirmedProgramTitleAndArtist() async throws {
        let runtime = SessionPlaybackRuntime()
        let channel = LiveChannelID("fixture-current-program")
        let client = ControlledSessionMetadataClient()
        let controller = makeController(runtime: runtime, client: client)

        let tune = try XCTUnwrap(controller.tuneFromLibrary(channel))
        await runtime.waitForObservation()
        runtime.confirmReady()
        runtime.confirmPlaying()
        await tune.value
        await client.waitForMetadataRequests(count: 1)

        XCTAssertEqual(controller.compactSurface.metadataPrimaryText, "Loading current program…")
        XCTAssertFalse(controller.compactSurface.usesMetadataFallback)

        await client.completeMetadata(with: .current(MetadataSnapshot(
            channelID: channel,
            program: LiveProgramMetadata(title: "Synthetic Program", artist: "Synthetic Artist")
        )))

        for _ in 0 ..< 10 {
            if controller.compactSurface.metadataPrimaryText == "Synthetic Program" { break }
            await Task.yield()
        }

        XCTAssertEqual(controller.compactSurface.metadataPrimaryText, "Synthetic Program")
        XCTAssertEqual(controller.compactSurface.metadataSecondaryText, "Synthetic Artist")
        XCTAssertFalse(controller.compactSurface.usesMetadataFallback)
        XCTAssertFalse(controller.compactSurface.metadataPrimaryText?.contains(channel.rawValue) ?? false)
    }

    func testPendingReplacementDisablesSystemMediaCommandsAndRejectsStaleHandlers() async throws {
        let runtime = SessionPlaybackRuntime()
        let catalog = ControlledSessionCatalog()
        let commandCenter = SessionRemoteCommandCenter()
        let nowPlaying = SessionNowPlayingPublisher()
        let first = LiveChannelID("fixture-system-first")
        let current = LiveChannelID("fixture-system-current")
        let replacement = LiveChannelID("fixture-system-replacement")
        let originIDs = [first, current, replacement]
        let controller = makeController(
            runtime: runtime,
            client: catalog,
            authenticationModel: AuthenticationPresentationModel(flow: EntitledSessionAuthenticationFlow()),
            remoteCommandCenter: commandCenter,
            nowPlayingPublisher: nowPlaying
        )

        let signIn = try XCTUnwrap(controller.authenticationModel.signIn())
        await catalog.waitForCatalogRequests(count: 1)
        await catalog.completeCatalog(with: .snapshot(LiveCatalogSnapshot(
            channels: originIDs.map { LiveChannel(id: $0, name: "Channel \($0.rawValue)") },
            freshness: .fresh
        )))
        await signIn.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.state.snapshot != nil { break }
            await Task.yield()
        }

        controller.startSystemMediaControls()
        let firstTune = try XCTUnwrap(controller.tune(channelID: current, originIDs: originIDs))
        await runtime.waitForObservation(count: 1)
        runtime.confirmReady()
        runtime.confirmPlaying()
        await firstTune.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.playbackState == .playing(current) {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(current))
        controller.startSystemMediaControls()
        XCTAssertTrue(commandCenter.isEnabled(.playPause))
        XCTAssertTrue(commandCenter.isEnabled(.previous))
        XCTAssertTrue(commandCenter.isEnabled(.next))
        let confirmedNowPlaying = try XCTUnwrap(nowPlaying.lastPublished)

        let replacementTune = try XCTUnwrap(controller.tune(channelID: replacement, originIDs: originIDs))
        await runtime.waitForObservation(count: 2)
        await replacementTune.value
        for _ in 0 ..< 10 {
            if !commandCenter.isEnabled(.playPause),
               !commandCenter.isEnabled(.previous),
               !commandCenter.isEnabled(.next) {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(controller.listeningModel.playbackState, .awaitingLiveContract)
        XCTAssertFalse(commandCenter.isEnabled(.playPause))
        XCTAssertFalse(commandCenter.isEnabled(.previous))
        XCTAssertFalse(commandCenter.isEnabled(.next))
        XCTAssertEqual(nowPlaying.lastPublished, confirmedNowPlaying)

        XCTAssertEqual(commandCenter.sendIgnoringEnabled(.playPause), .commandFailed)
        XCTAssertEqual(commandCenter.sendIgnoringEnabled(.previous), .commandFailed)
        XCTAssertEqual(commandCenter.sendIgnoringEnabled(.next), .commandFailed)
        await Task.yield()
        XCTAssertEqual(runtime.observationCount, 2)
    }

    func testImmediateRemoteNavigationAcceptsOnlyOneTuneAndPreservesQueuePosition() async throws {
        let runtime = SessionPlaybackRuntime()
        let catalog = ControlledSessionCatalog()
        let commandCenter = SessionRemoteCommandCenter()
        let first = LiveChannelID("fixture-navigation-first")
        let current = LiveChannelID("fixture-navigation-current")
        let next = LiveChannelID("fixture-navigation-next")
        let originIDs = [first, current, next]
        let controller = makeController(
            runtime: runtime,
            client: catalog,
            authenticationModel: AuthenticationPresentationModel(flow: EntitledSessionAuthenticationFlow()),
            remoteCommandCenter: commandCenter
        )

        let signIn = try XCTUnwrap(controller.authenticationModel.signIn())
        await catalog.waitForCatalogRequests(count: 1)
        await catalog.completeCatalog(with: .snapshot(LiveCatalogSnapshot(
            channels: originIDs.map { LiveChannel(id: $0, name: "Channel \($0.rawValue)") },
            freshness: .fresh
        )))
        await signIn.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.state.snapshot != nil { break }
            await Task.yield()
        }

        controller.startSystemMediaControls()
        let initialTune = try XCTUnwrap(controller.tune(channelID: current, originIDs: originIDs))
        await runtime.waitForObservation(count: 1)
        runtime.confirmReady()
        runtime.confirmPlaying()
        await initialTune.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.playbackState == .playing(current) { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(current))

        // Do not yield between these events: the second must see the
        // synchronously-published pending state, before the tune task starts.
        XCTAssertEqual(commandCenter.sendIgnoringEnabled(.next), .success)
        XCTAssertEqual(commandCenter.sendIgnoringEnabled(.next), .commandFailed)
        XCTAssertTrue(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.playbackQueue?.currentID, next)
        await runtime.waitForObservation(count: 2)
        XCTAssertEqual(runtime.observationCount, 2)

        runtime.confirmReady()
        runtime.confirmPlaying()
        for _ in 0 ..< 10 {
            if controller.listeningModel.playbackState == .playing(next) { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(next))
        XCTAssertFalse(controller.listeningModel.isTunePending)

        // Exercise the opposite direction through the same no-yield path.
        XCTAssertEqual(commandCenter.sendIgnoringEnabled(.previous), .success)
        XCTAssertEqual(commandCenter.sendIgnoringEnabled(.previous), .commandFailed)
        XCTAssertTrue(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.playbackQueue?.currentID, current)
        await runtime.waitForObservation(count: 3)
        XCTAssertEqual(runtime.observationCount, 3)
    }

    func testCancellingReplacementTuneSynchronouslyAllowsLaterNavigation() async throws {
        let runtime = SessionPlaybackRuntime()
        let resolver = ControlledSessionPlaybackResolver()
        let catalog = ControlledSessionCatalog()
        let first = LiveChannelID("fixture-cancel-first")
        let current = LiveChannelID("fixture-cancel-current")
        let next = LiveChannelID("fixture-cancel-next")
        let originIDs = [first, current, next]
        let controller = makeController(
            runtime: runtime,
            resolver: resolver,
            client: catalog,
            authenticationModel: AuthenticationPresentationModel(flow: EntitledSessionAuthenticationFlow())
        )

        let signIn = try XCTUnwrap(controller.authenticationModel.signIn())
        await catalog.waitForCatalogRequests(count: 1)
        await catalog.completeCatalog(with: .snapshot(LiveCatalogSnapshot(
            channels: originIDs.map { LiveChannel(id: $0, name: "Channel \($0.rawValue)") },
            freshness: .fresh
        )))
        await signIn.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.state.snapshot != nil { break }
            await Task.yield()
        }

        let initialTune = try XCTUnwrap(controller.tune(channelID: current, originIDs: originIDs))
        await resolver.waitForResolution(of: current)
        await resolver.complete(current, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 1)
        runtime.confirmReady()
        runtime.confirmPlaying()
        await initialTune.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.playbackState == .playing(current) { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(current))

        let cancelledReplacement = try XCTUnwrap(controller.next())
        await resolver.waitForResolution(of: next)
        XCTAssertTrue(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.playbackQueue?.currentID, next)

        // Cancellation and its follow-up navigation happen in the same main
        // actor turn. There is deliberately no Task.yield() between them.
        cancelledReplacement.cancel()
        XCTAssertFalse(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.listeningModel.playbackState, .stopped)

        let laterNavigation = try XCTUnwrap(controller.previous())
        XCTAssertEqual(controller.playbackQueue?.currentID, current)
        await resolver.waitForResolution(of: current, count: 2)
        await resolver.complete(current, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 2)
        runtime.confirmReady()
        runtime.confirmPlaying()
        await laterNavigation.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.playbackState == .playing(current) { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(current))

        // The first resolver deliberately ignores cancellation. Completing it
        // after a later navigation must not replace the newly confirmed item.
        await resolver.complete(next, with: .available(SessionMediaHandoff()))
        await cancelledReplacement.value
        await Task.yield()
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(current))
        XCTAssertEqual(runtime.observationCount, 2)
    }

    func testRepeatedLibraryOpenRequestsReuseTheSingletonRoute() {
        let controller = makeController()
        let originalCoordinator = controller.librarySurface.coordinatorIdentity

        XCTAssertTrue(controller.requestLibraryOpen())
        XCTAssertFalse(controller.requestLibraryOpen())
        XCTAssertFalse(controller.requestLibraryOpen())
        XCTAssertTrue(controller.composition.playbackCoordinator === controller.playbackCoordinator)
        XCTAssertEqual(controller.librarySurface.coordinatorIdentity, originalCoordinator)
    }

    func testUnitTestHostDoesNotConstructTheProductionSessionController() {
        XCTAssertNil(SiriusMacApp.makeSessionController(environment: [
            "XCTestConfigurationFilePath": "/tmp/host.xctestconfiguration",
        ]))
    }

    private func makeController(
        runtime: SessionPlaybackRuntime = SessionPlaybackRuntime(),
        resolver: (any PlaybackResolving)? = nil,
        client: (any ClientAuthenticationFlow & ListeningFlow)? = nil,
        authenticationModel: AuthenticationPresentationModel? = nil,
        libraryStore: LibraryStore? = nil,
        remoteCommandCenter: any RemoteCommandCenterControlling = SystemRemoteCommandCenterAdapter(),
        nowPlayingPublisher: any NowPlayingInfoPublishing = SystemNowPlayingInfoAdapter()
    ) -> ListeningSessionController {
        let coordinator = PlaybackCoordinator(
            resolver: resolver ?? SessionPlaybackResolver(),
            runtime: runtime
        )
        let composition = AuthenticationComposition(
            bridge: WebAuthenticationBridge(),
            keychain: KeychainCredentialStore(
                service: "com.siriusmac.tests.\(UUID().uuidString)",
                account: "listening-session-controller"
            ),
            client: client ?? SessionClient(),
            playbackCoordinator: coordinator
        )
        return ListeningSessionController(
            composition: composition,
            authenticationModel: authenticationModel,
            libraryStore: libraryStore,
            remoteCommandCenter: remoteCommandCenter,
            nowPlayingPublisher: nowPlayingPublisher
        )
    }

    private func makeLibraryStore() throws -> LibraryStore {
        let container = try ModelContainer(
            for: FavoriteRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return LibraryStore(modelContainer: container, now: { Date(timeIntervalSince1970: 1) })
    }
}

private actor SessionClient: ClientAuthenticationFlow, ListeningFlow {
    func authenticate() async -> AuthenticationOutcome { .unsupported }
    func entitlementAvailability() async -> EntitlementAvailability { .unavailable }
    func signOut() async -> SignOutOutcome { .signedOut }
    func catalog() async -> CatalogAvailability { .unavailable }
}

private actor ControlledSessionCatalog: ClientAuthenticationFlow, ListeningFlow {
    private var catalogRequests = 0
    private var catalogWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingCatalog: CheckedContinuation<CatalogAvailability, Never>?

    func authenticate() async -> AuthenticationOutcome { .authenticatedPendingEntitlement }
    func entitlementAvailability() async -> EntitlementAvailability { .entitled }
    func signOut() async -> SignOutOutcome { .signedOut }

    func catalog() async -> CatalogAvailability {
        catalogRequests += 1
        catalogWaiters.forEach { $0.resume() }
        catalogWaiters.removeAll()
        return await withCheckedContinuation { pendingCatalog = $0 }
    }

    func catalogRequestCount() -> Int { catalogRequests }

    func waitForCatalogRequests(count: Int) async {
        if catalogRequests >= count { return }
        await withCheckedContinuation { catalogWaiters.append($0) }
    }

    func completeCatalog(with availability: CatalogAvailability) {
        pendingCatalog?.resume(returning: availability)
        pendingCatalog = nil
    }
}

private struct EntitledSessionAuthenticationFlow: AuthenticationPresentationFlow {
    func beginWebViewSignIn() async -> AuthenticationPresentationState { .entitled }

    func prepareForExplicitSignIn(
        onAuthenticationVerification _: @MainActor @escaping @Sendable () -> Void,
        onEntitlementVerification _: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        .entitled
    }

    func useLoggedInSession(
        onEntitlementVerification _: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        .entitled
    }

    func signOut() async -> SignOutOutcome { .signedOut }
}

private actor ControlledSessionMetadataClient: ClientAuthenticationFlow, ListeningFlow, MetadataFlow {
    private var metadataRequests = 0
    private var metadataWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingMetadata: CheckedContinuation<MetadataAvailability, Never>?

    func authenticate() async -> AuthenticationOutcome { .unsupported }
    func entitlementAvailability() async -> EntitlementAvailability { .unavailable }
    func signOut() async -> SignOutOutcome { .signedOut }
    func catalog() async -> CatalogAvailability { .unavailable }

    func metadata(for _: LiveChannelID) async -> MetadataAvailability {
        metadataRequests += 1
        metadataWaiters.forEach { $0.resume() }
        metadataWaiters.removeAll()
        return await withCheckedContinuation { pendingMetadata = $0 }
    }

    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }

    func waitForMetadataRequests(count: Int) async {
        if metadataRequests >= count { return }
        await withCheckedContinuation { metadataWaiters.append($0) }
    }

    func completeMetadata(with result: MetadataAvailability) {
        pendingMetadata?.resume(returning: result)
        pendingMetadata = nil
    }
}

private struct SessionPlaybackResolver: PlaybackResolving {
    func resolve(for _: LiveChannelID) async -> PlaybackResourceResolution {
        .available(SessionMediaHandoff())
    }
}

private actor ControlledSessionPlaybackResolver: PlaybackResolving {
    private var calls: [LiveChannelID: Int] = [:]
    private var continuations: [LiveChannelID: [CheckedContinuation<PlaybackResourceResolution, Never>]] = [:]
    private var waiters: [LiveChannelID: [Int: CheckedContinuation<Void, Never>]] = [:]

    func resolve(for channelID: LiveChannelID) async -> PlaybackResourceResolution {
        let count = (calls[channelID] ?? 0) + 1
        calls[channelID] = count
        waiters[channelID]?[count]?.resume()
        waiters[channelID]?[count] = nil
        return await withCheckedContinuation { continuation in
            continuations[channelID, default: []].append(continuation)
        }
    }

    func waitForResolution(of channelID: LiveChannelID, count: Int = 1) async {
        guard (calls[channelID] ?? 0) < count else { return }
        await withCheckedContinuation { waiter in
            waiters[channelID, default: [:]][count] = waiter
        }
    }

    func complete(_ channelID: LiveChannelID, with result: PlaybackResourceResolution) {
        guard var pending = continuations[channelID], !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        continuations[channelID] = pending
        continuation.resume(returning: result)
    }
}

private final class SessionMediaHandoff: SiriusXMAppleMediaHandoff, @unchecked Sendable {
    @MainActor
    func makePlayerItem() -> AVPlayerItem? {
        AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
    }
}

@MainActor
private final class SessionPlaybackRuntime: PlaybackPlayerRuntime {
    private var ready: (@MainActor @Sendable () -> Void)?
    private var playing: (@MainActor @Sendable () -> Void)?
    private var observationWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var observationCount = 0

    func observe(
        _: AVPlayerItem,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused _: @escaping @MainActor @Sendable () -> Void,
        onFailure _: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) -> any PlaybackItemObserving {
        ready = onReady
        playing = onPlaying
        observationCount += 1
        observationWaiters.removeValue(forKey: observationCount)?.resume()
        return SessionPlaybackObservation()
    }

    func install(_: AVPlayerItem) {}
    func requestPlay() {}
    func requestPause() {}
    func clearCurrentItem() {}

    func waitForObservation(count: Int = 1) async {
        guard observationCount < count else { return }
        await withCheckedContinuation { observationWaiters[count] = $0 }
    }

    func confirmReady() { ready?() }
    func confirmPlaying() { playing?() }
}

@MainActor
private final class SessionPlaybackObservation: PlaybackItemObserving {
    func cancel() {}
}

@MainActor
private final class SessionRemoteCommandCenter: RemoteCommandCenterControlling {
    private final class Token: RemoteCommandTarget, Hashable {
        nonisolated static func == (lhs: Token, rhs: Token) -> Bool { lhs === rhs }
        nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    }

    private var handlers: [SystemRemoteCommand: [Token: () -> SystemRemoteCommandStatus]] = [:]
    private var enabled: [SystemRemoteCommand: Bool] = [:]

    func setEnabled(_ isEnabled: Bool, for command: SystemRemoteCommand) {
        enabled[command] = isEnabled
    }

    func addTarget(
        for command: SystemRemoteCommand,
        handler: @escaping () -> SystemRemoteCommandStatus
    ) -> any RemoteCommandTarget {
        let token = Token()
        handlers[command, default: [:]][token] = handler
        return token
    }

    func removeTarget(_: any RemoteCommandTarget, for _: SystemRemoteCommand) {}

    func isEnabled(_ command: SystemRemoteCommand) -> Bool { enabled[command] ?? true }

    func sendIgnoringEnabled(_ command: SystemRemoteCommand) -> SystemRemoteCommandStatus {
        handlers[command]?.values.first?() ?? .commandFailed
    }
}

@MainActor
private final class SessionNowPlayingPublisher: NowPlayingInfoPublishing {
    private(set) var lastPublished: SystemNowPlayingInfo?

    func publish(_ info: SystemNowPlayingInfo?) {
        lastPublished = info
    }
}
