import AVFoundation
import XCTest
@_spi(Playback) import SiriusXMClient
@testable import SiriusMac

@MainActor
final class ListeningSessionControllerTests: XCTestCase {
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
        runtime: SessionPlaybackRuntime = SessionPlaybackRuntime()
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
            client: SessionClient(),
            playbackCoordinator: coordinator
        )
        return ListeningSessionController(composition: composition)
    }
}

private actor SessionClient: ClientAuthenticationFlow, ListeningFlow {
    func authenticate() async -> AuthenticationOutcome { .unsupported }
    func entitlementAvailability() async -> EntitlementAvailability { .unavailable }
    func signOut() async -> SignOutOutcome { .signedOut }
    func catalog() async -> CatalogAvailability { .unavailable }
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
