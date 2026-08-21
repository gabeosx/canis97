import AVFoundation
import XCTest
@_spi(Playback) import SiriusXMClient
@testable import SiriusMac

@MainActor
final class ListeningSessionControllerTests: XCTestCase {
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
        client: (any ClientAuthenticationFlow & ListeningFlow)? = nil,
        authenticationModel: AuthenticationPresentationModel? = nil
    ) -> ListeningSessionController {
        let coordinator = PlaybackCoordinator(
            resolver: SessionPlaybackResolver(),
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
            authenticationModel: authenticationModel
        )
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
    private var observationWaiter: CheckedContinuation<Void, Never>?

    func observe(
        _: AVPlayerItem,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused _: @escaping @MainActor @Sendable () -> Void,
        onFailure _: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) -> any PlaybackItemObserving {
        ready = onReady
        playing = onPlaying
        observationWaiter?.resume()
        observationWaiter = nil
        return SessionPlaybackObservation()
    }

    func install(_: AVPlayerItem) {}
    func requestPlay() {}
    func requestPause() {}
    func clearCurrentItem() {}

    func waitForObservation() async {
        guard ready == nil else { return }
        await withCheckedContinuation { observationWaiter = $0 }
    }

    func confirmReady() { ready?() }
    func confirmPlaying() { playing?() }
}

@MainActor
private final class SessionPlaybackObservation: PlaybackItemObserving {
    func cancel() {}
}
