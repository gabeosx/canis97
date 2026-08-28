import AVFoundation
import SwiftData
import XCTest
@_spi(Playback) import SiriusXMClient
@testable import Canis97

@MainActor
final class WindowLifecyclePolicyTests: XCTestCase {
    func testPrimarySceneTracksCurrentContentSizeAcrossAuthenticationAndCompactStates() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "SiriusMac/SiriusMacApp.swift"),
            encoding: .utf8
        )
        let primaryScene = try XCTUnwrap(
            source.components(
                separatedBy: "Window(\"\\(ProductIdentity.displayName) Library\", id: ProductIdentity.SceneID.library)"
            ).first
        )

        XCTAssertTrue(primaryScene.contains(".windowResizability(.contentSize)"))
        XCTAssertFalse(primaryScene.contains(".windowResizability(.contentMinSize)"))
    }

    func testCompactPolicyUsesFixedSizeAndDistinctAutosaveName() {
        let policy = WindowLifecyclePolicy(role: .compact)

        XCTAssertEqual(policy.defaultContentSize, CGSize(width: 400, height: 288))
        XCTAssertEqual(policy.minimumContentSize, CGSize(width: 400, height: 288))
        XCTAssertFalse(policy.isResizable)
        XCTAssertFalse(policy.allowsFullScreen)
        XCTAssertTrue(policy.usesCompactChrome)
        XCTAssertEqual(policy.frameAutosaveName, ProductIdentity.FrameAutosaveName.compact)
        XCTAssertEqual(policy.legacyFrameAutosaveName, ProductIdentity.Legacy.compactFrameAutosaveName)
    }

    func testAuthenticationPolicyRestoresAUsableResizablePrimaryWindow() {
        let policy = WindowLifecyclePolicy(role: .authentication)

        XCTAssertEqual(policy.defaultContentSize, CGSize(width: 760, height: 760))
        XCTAssertEqual(policy.minimumContentSize, CGSize(width: 760, height: 760))
        XCTAssertTrue(policy.isResizable)
        XCTAssertTrue(policy.allowsFullScreen)
        XCTAssertFalse(policy.usesCompactChrome)
        XCTAssertEqual(policy.frameAutosaveName, ProductIdentity.FrameAutosaveName.authentication)
        XCTAssertEqual(
            policy.legacyFrameAutosaveName,
            ProductIdentity.Legacy.authenticationFrameAutosaveName
        )
    }

    func testAuthenticationAttachmentReversesCompactWindowRestrictionsAfterSignOut() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 288),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        CompactWindowController(role: .authentication, restoresPersistedFrame: false)
            .attach(to: window, alwaysOnTop: false)

        XCTAssertEqual(window.contentView?.frame.size, NSSize(width: 760, height: 760))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenNone))
    }

    func testCompactAttachmentRetainsSavedOriginButResetsOversizedSavedContentSize() {
        let key = "NSWindow Frame \(ProductIdentity.compactFrameAutosaveName)"
        let previousValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let savedFrame = NSRect(x: 120, y: 96, width: 760, height: 620)
        UserDefaults.standard.set(NSStringFromRect(savedFrame), forKey: key)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = CompactWindowController(role: .compact)

        controller.attach(to: window, alwaysOnTop: false)

        XCTAssertEqual(window.contentView?.frame.size, NSSize(width: 400, height: 288))
        XCTAssertEqual(window.frame.origin, savedFrame.origin)
    }

    func testCompactAttachmentRemovesTitleBarGeometry() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 288),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = CompactWindowController(role: .compact, restoresPersistedFrame: false)

        controller.attach(to: window, alwaysOnTop: false)

        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertFalse(window.titlebarAppearsTransparent)
    }

    func testAuthenticationAttachmentRestoresStandardChromeAfterCompactPlayback() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 288),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let compactController = CompactWindowController(role: .compact, restoresPersistedFrame: false)
        let authenticationController = CompactWindowController(role: .authentication, restoresPersistedFrame: false)
        compactController.attach(to: window, alwaysOnTop: false)

        authenticationController.attach(to: window, alwaysOnTop: false)

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .visible)
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.standardWindowButton(.closeButton)?.isHidden == false)
        XCTAssertTrue(window.standardWindowButton(.miniaturizeButton)?.isHidden == false)
        XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isHidden == false)
    }

    func testCompactAttachmentCanIgnoreProductionFramePersistence() {
        let key = "NSWindow Frame \(ProductIdentity.compactFrameAutosaveName)"
        let previousValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let savedFrame = NSRect(x: 120, y: 96, width: 760, height: 620)
        UserDefaults.standard.set(NSStringFromRect(savedFrame), forKey: key)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        CompactWindowController(role: .compact, restoresPersistedFrame: false)
            .attach(to: window, alwaysOnTop: false)

        XCTAssertEqual(window.contentView?.frame.size, NSSize(width: 400, height: 288))
        XCTAssertNotEqual(window.frame.origin, savedFrame.origin)
    }

    func testNativeDoubleActionBridgeForwardsAndRestoresTheTableSingleAction() {
        let tableView = NSTableView()
        let attachmentView = NSView()
        tableView.addSubview(attachmentView)
        let target = NativeTableActionSpy()
        tableView.target = target
        tableView.action = #selector(NativeTableActionSpy.handleSingleAction(_:))
        let coordinator = NativeListDoubleActionBridge.Coordinator(onDoubleAction: { _ in })

        coordinator.install(from: attachmentView)
        guard let installedAction = tableView.action else {
            return XCTFail("Expected the bridge to preserve a single-action route")
        }
        NSApp.sendAction(installedAction, to: tableView.target, from: tableView)

        XCTAssertEqual(target.singleActionCount, 1)
        coordinator.uninstall()
        XCTAssertTrue(tableView.target === target)
        XCTAssertEqual(tableView.action, #selector(NativeTableActionSpy.handleSingleAction(_:)))
    }

    func testLibraryPolicyIsResizableWithSeparateAutosaveName() {
        let policy = WindowLifecyclePolicy(role: .library)

        XCTAssertEqual(policy.defaultContentSize, CGSize(width: 980, height: 700))
        XCTAssertEqual(policy.minimumContentSize, CGSize(width: 760, height: 540))
        XCTAssertTrue(policy.isResizable)
        XCTAssertTrue(policy.allowsFullScreen)
        XCTAssertEqual(policy.frameAutosaveName, ProductIdentity.FrameAutosaveName.library)
        XCTAssertEqual(policy.legacyFrameAutosaveName, ProductIdentity.Legacy.libraryFrameAutosaveName)
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

    func testFrameMigrationPreservesOnlyAVisibleLegacyCompactOrigin() {
        let screens = [CGRect(x: 0, y: 0, width: 1_440, height: 900)]
        let visibleLegacy = NSStringFromRect(NSRect(x: 120, y: 96, width: 760, height: 620))
        let migrated = WindowFrameMigration.migratedFrameString(
            currentValue: nil,
            legacyValue: visibleLegacy,
            role: .compact,
            screens: screens
        )

        XCTAssertEqual(NSRectFromString(try! XCTUnwrap(migrated)).origin, CGPoint(x: 120, y: 96))
        XCTAssertEqual(NSRectFromString(try! XCTUnwrap(migrated)).size, CGSize(width: 400, height: 288))
        XCTAssertNil(WindowFrameMigration.migratedFrameString(
            currentValue: nil,
            legacyValue: NSStringFromRect(NSRect(x: 9_000, y: 9_000, width: 760, height: 620)),
            role: .compact,
            screens: screens
        ))
        XCTAssertNil(WindowFrameMigration.migratedFrameString(
            currentValue: "already-current",
            legacyValue: visibleLegacy,
            role: .compact,
            screens: screens
        ))
    }

    func testPrimaryWindowCloseRequestsTerminationOnlyOnceWhileLibraryCloseDoesNothing() {
        let terminator = WindowLifecycleTerminatorSpy()
        let authentication = WindowLifecyclePolicy(role: .authentication, terminator: terminator)
        let compact = WindowLifecyclePolicy(role: .compact, terminator: terminator)
        let library = WindowLifecyclePolicy(role: .library, terminator: terminator)

        authentication.windowWillClose()
        authentication.windowWillClose()
        compact.windowWillClose()
        compact.windowWillClose()
        library.windowWillClose()

        XCTAssertEqual(terminator.terminationRequestCount, 2)
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
            FavoriteSongRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

}

@MainActor
private final class NativeTableActionSpy: NSObject {
    private(set) var singleActionCount = 0

    @objc func handleSingleAction(_ sender: NSTableView) {
        singleActionCount += 1
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
    func testCompactWindowControllerKeepsFiniteAppearancePolicyAtTheBridge() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("SiriusMac/Windows/CompactWindowController.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("CompactWindowPositionRecord"))
        XCTAssertTrue(source.contains("CompactWindowGeometry"))
        XCTAssertTrue(source.contains("restoreNativeAppearance"))
    }
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

    func testRepeatedCancellationOfOldRequestCannotStopNewPendingTune() async throws {
        let runtime = SessionPlaybackRuntime()
        let resolver = ControlledSessionPlaybackResolver()
        let catalog = ControlledSessionCatalog()
        let first = LiveChannelID("fixture-repeated-cancel-first")
        let current = LiveChannelID("fixture-repeated-cancel-current")
        let next = LiveChannelID("fixture-repeated-cancel-next")
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

        let initialTune = try XCTUnwrap(controller.tune(channelID: current, originIDs: originIDs))
        await resolver.waitForResolution(of: current)
        await resolver.complete(current, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 1)
        runtime.confirmReady()
        runtime.confirmPlaying()
        await initialTune.value

        let firstReplacement = try XCTUnwrap(controller.next())
        await resolver.waitForResolution(of: next)
        firstReplacement.cancel()
        let secondReplacement = try XCTUnwrap(controller.previous())
        await resolver.waitForResolution(of: current, count: 2)

        // This handle already cancelled its own request. A repeated call must
        // not invalidate the newer request that is currently pending.
        firstReplacement.cancel()
        XCTAssertTrue(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.playbackCoordinator.selectedChannelID, current)
        XCTAssertEqual(controller.playbackQueue?.currentID, current)

        await resolver.complete(current, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 2)
        runtime.confirmReady()
        runtime.confirmPlaying()
        await secondReplacement.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.playbackState == .playing(current) { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(current))
        XCTAssertFalse(controller.listeningModel.isTunePending)
    }

    func testLateCancellationOfCompletedRequestCannotStopNewPendingTune() async throws {
        let runtime = SessionPlaybackRuntime()
        let resolver = ControlledSessionPlaybackResolver()
        let catalog = ControlledSessionCatalog()
        let first = LiveChannelID("fixture-late-cancel-first")
        let current = LiveChannelID("fixture-late-cancel-current")
        let next = LiveChannelID("fixture-late-cancel-next")
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

        let initialTune = try XCTUnwrap(controller.tune(channelID: current, originIDs: originIDs))
        await resolver.waitForResolution(of: current)
        await resolver.complete(current, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 1)
        runtime.confirmReady()
        runtime.confirmPlaying()
        await initialTune.value

        let completedReplacement = try XCTUnwrap(controller.next())
        await resolver.waitForResolution(of: next)
        await resolver.complete(next, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 2)
        runtime.confirmReady()
        runtime.confirmPlaying()
        await completedReplacement.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.playbackState == .playing(next) { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(next))

        let newerReplacement = try XCTUnwrap(controller.previous())
        await resolver.waitForResolution(of: current, count: 2)

        // This is the first cancel call for an already completed request. Its
        // old identity must not reach the pending newer coordinator request.
        completedReplacement.cancel()
        XCTAssertTrue(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.listeningModel.playbackState, .awaitingLiveContract)
        XCTAssertEqual(controller.playbackQueue?.currentID, current)

        await resolver.complete(current, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 3)
        runtime.confirmReady()
        runtime.confirmPlaying()
        await newerReplacement.value
        for _ in 0 ..< 10 {
            if controller.listeningModel.playbackState == .playing(current) { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(current))
        XCTAssertFalse(controller.listeningModel.isTunePending)
    }

    func testStopSynchronouslyRevokesATuneHeldBeforeCoordinatorEntry() async throws {
        let runtime = SessionPlaybackRuntime()
        let resolver = ControlledSessionPlaybackResolver()
        let dispatchGate = TuneDispatchGate()
        let coordinator = PlaybackCoordinator(resolver: resolver, runtime: runtime)
        let model = ListeningPresentationModel(
            flow: SessionClient(),
            playbackCoordinator: coordinator,
            beforeCoordinatorTune: { await dispatchGate.wait() }
        )
        let channel = LiveChannelID("fixture-stop-before-coordinator-entry")

        let tune = try XCTUnwrap(model.tune(channel))
        await dispatchGate.waitForWorker()
        XCTAssertTrue(model.isTunePending)

        // There is deliberately no yield between Stop and releasing the
        // accepted worker. Stop must revoke the request before its first
        // resolver/install/play-capable coordinator call.
        let stop = try XCTUnwrap(model.stopPlayback())
        XCTAssertFalse(model.isTunePending)
        XCTAssertEqual(model.playbackState, .stopped)
        await stop.value

        await dispatchGate.release()
        await tune.value

        let resolverCallCount = await resolver.calls(for: channel)
        XCTAssertEqual(resolverCallCount, 0)
        XCTAssertEqual(runtime.observationCount, 0)
        XCTAssertEqual(runtime.installCount, 0)
        XCTAssertEqual(runtime.playRequestCount, 0)
        XCTAssertNil(coordinator.selectedChannelID)
        XCTAssertEqual(coordinator.state, .stopped)
    }

    func testQueuedOldSameChannelPlayingObservationCannotConfirmReplacementTune() async throws {
        let runtime = SessionPlaybackRuntime()
        let resolver = ControlledSessionPlaybackResolver()
        let channel = LiveChannelID("fixture-generation-same-channel")
        let controller = makeController(
            runtime: runtime,
            resolver: resolver,
            client: SessionClient(),
            authenticationModel: AuthenticationPresentationModel(flow: EntitledSessionAuthenticationFlow())
        )

        let initialTune = try XCTUnwrap(controller.tune(channelID: channel, originIDs: [channel]))
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation()
        runtime.confirmReady()
        runtime.confirmPlaying()
        await initialTune.value
        for _ in 0 ..< 10 where controller.listeningModel.playbackState != .playing(channel) {
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(channel))

        // This schedules the old generation's model observation. Retuning in
        // the same actor turn must not let that observation confirm the new A.
        runtime.confirmPlaying(observation: 1)
        let replacement = try XCTUnwrap(controller.tune(channelID: channel, originIDs: [channel]))
        XCTAssertTrue(controller.listeningModel.isTunePending)
        await resolver.waitForResolution(of: channel, count: 2)
        await Task.yield()
        XCTAssertTrue(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.listeningModel.playbackState, .awaitingLiveContract)

        await resolver.complete(channel, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 2)
        runtime.confirmReady(observation: 2)
        runtime.confirmPlaying(observation: 2)
        await replacement.value
        for _ in 0 ..< 10 where controller.listeningModel.playbackState != .playing(channel) {
            await Task.yield()
        }
        XCTAssertFalse(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.listeningModel.playbackState, .playing(channel))
    }

    func testTerminalObservationIsAppliedBeforeANewerTuneCanClaimTheModel() async throws {
        let runtime = SessionPlaybackRuntime()
        let resolver = ControlledSessionPlaybackResolver()
        let first = LiveChannelID("fixture-generation-first")
        let replacement = LiveChannelID("fixture-generation-replacement")
        let controller = makeController(
            runtime: runtime,
            resolver: resolver,
            client: SessionClient(),
            authenticationModel: AuthenticationPresentationModel(flow: EntitledSessionAuthenticationFlow())
        )

        let initialTune = try XCTUnwrap(controller.tune(channelID: first, originIDs: [first, replacement]))
        await resolver.waitForResolution(of: first)
        await resolver.complete(first, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation()
        runtime.confirmReady()
        runtime.confirmPlaying()
        await initialTune.value
        for _ in 0 ..< 10 where controller.listeningModel.confirmedChannelID != first {
            await Task.yield()
        }
        XCTAssertEqual(controller.listeningModel.confirmedChannelID, first)

        // Model and coordinator share the main actor, so the terminal
        // publication is applied before another tune can claim the model.
        runtime.confirmFailure(.networkUnavailable, observation: 1)
        XCTAssertNil(controller.listeningModel.confirmedChannelID)
        XCTAssertEqual(controller.listeningModel.playbackState, .unavailable(.networkUnavailable))

        let newerTune = try XCTUnwrap(controller.tune(channelID: replacement, originIDs: [first, replacement]))
        XCTAssertTrue(controller.listeningModel.isTunePending)
        await resolver.waitForResolution(of: replacement)
        await Task.yield()

        XCTAssertTrue(controller.listeningModel.isTunePending)
        XCTAssertNil(controller.listeningModel.confirmedChannelID)
        XCTAssertEqual(controller.listeningModel.playbackState, .awaitingLiveContract)

        newerTune.cancel()
    }

    func testReplacementItemFailureClearsPendingAndAllowsLaterNavigation() async throws {
        let runtime = SessionPlaybackRuntime()
        let resolver = ControlledSessionPlaybackResolver()
        let catalog = ControlledSessionCatalog()
        let first = LiveChannelID("fixture-item-failure-first")
        let current = LiveChannelID("fixture-item-failure-current")
        let next = LiveChannelID("fixture-item-failure-next")
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
        for _ in 0 ..< 10 where controller.listeningModel.state.snapshot == nil {
            await Task.yield()
        }

        let initialTune = try XCTUnwrap(controller.tune(channelID: current, originIDs: originIDs))
        await resolver.waitForResolution(of: current)
        await resolver.complete(current, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation()
        runtime.confirmReady()
        runtime.confirmPlaying()
        await initialTune.value
        for _ in 0 ..< 10 where controller.listeningModel.playbackState != .playing(current) {
            await Task.yield()
        }
        for _ in 0 ..< 10 where !controller.commandAvailability.next {
            await Task.yield()
        }
        XCTAssertTrue(controller.commandAvailability.next)

        let replacementTune = try XCTUnwrap(controller.next())
        await resolver.waitForResolution(of: next)
        await resolver.complete(next, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 2)
        runtime.confirmReady(observation: 2)
        runtime.confirmFailure(.decoderUnavailable, observation: 2)
        await replacementTune.value
        for _ in 0 ..< 10 where controller.listeningModel.isTunePending {
            await Task.yield()
        }

        XCTAssertFalse(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.listeningModel.playbackState, .unavailable(.decoderUnavailable))
        XCTAssertNotNil(controller.previous())
    }

    func testSameChannelRetuneItemFailureClearsPendingAndAllowsLaterNavigation() async throws {
        let runtime = SessionPlaybackRuntime()
        let resolver = ControlledSessionPlaybackResolver()
        let channel = LiveChannelID("fixture-item-failure-same-channel")
        let controller = makeController(
            runtime: runtime,
            resolver: resolver,
            client: SessionClient(),
            authenticationModel: AuthenticationPresentationModel(flow: EntitledSessionAuthenticationFlow())
        )

        let initialTune = try XCTUnwrap(controller.tune(channelID: channel, originIDs: [channel]))
        await resolver.waitForResolution(of: channel)
        await resolver.complete(channel, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation()
        runtime.confirmReady()
        runtime.confirmPlaying()
        await initialTune.value
        for _ in 0 ..< 10 where controller.listeningModel.playbackState != .playing(channel) {
            await Task.yield()
        }

        let retune = try XCTUnwrap(controller.tune(channelID: channel, originIDs: [channel]))
        await resolver.waitForResolution(of: channel, count: 2)
        await resolver.complete(channel, with: .available(SessionMediaHandoff()))
        await runtime.waitForObservation(count: 2)
        runtime.confirmReady(observation: 2)
        runtime.confirmFailure(.networkUnavailable, observation: 2)
        await retune.value
        for _ in 0 ..< 10 where controller.listeningModel.isTunePending {
            await Task.yield()
        }

        XCTAssertFalse(controller.listeningModel.isTunePending)
        XCTAssertEqual(controller.listeningModel.playbackState, .unavailable(.networkUnavailable))
        XCTAssertNotNil(controller.tune(channelID: channel, originIDs: [channel]))
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

    func testLibraryWindowClosesOnSignOutAndReopensForTheNextReadySession() {
        let controller = makeController()

        XCTAssertEqual(controller.libraryWindowDirective(authenticationIsReady: true), .open)
        XCTAssertEqual(controller.libraryWindowDirective(authenticationIsReady: true), .none)
        XCTAssertEqual(controller.libraryWindowDirective(authenticationIsReady: false), .close)
        XCTAssertFalse(controller.hasRequestedLibraryOpen)
        XCTAssertEqual(controller.libraryWindowDirective(authenticationIsReady: true), .open)
        XCTAssertTrue(controller.hasRequestedLibraryOpen)
    }

    func testUnitTestHostDoesNotConstructTheProductionSessionController() {
        XCTAssertNil(Canis97App.makeSessionController(environment: [
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
            FavoriteSongRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return LibraryStore(modelContainer: container, now: { Date(timeIntervalSince1970: 1) })
    }
}

final class FavoriteCurrentSongActionStateTests: XCTestCase {
    func testEligibleStateOwnsItsSavedAndRemovalPresentation() {
        XCTAssertEqual(FavoriteCurrentSongActionState.enabled(isFavorite: false).title, "Favorite Current Song")
        XCTAssertEqual(FavoriteCurrentSongActionState.enabled(isFavorite: true).title, "Remove Current Song from Favorite Songs")
        XCTAssertEqual(FavoriteCurrentSongActionState.enabled(isFavorite: false).accessibilityValue, "Not saved to Favorite Songs")
        XCTAssertEqual(FavoriteCurrentSongActionState.enabled(isFavorite: true).accessibilityValue, "Saved to Favorite Songs")
        XCTAssertTrue(FavoriteCurrentSongActionState.enabled(isFavorite: false).isEnabled)
    }

    func testEveryIneligibleReasonHasClosedAccessibleCopy() {
        let reasons: [(FavoriteCurrentSongDisabledReason, String)] = [
            (.tunePending, "Wait for the current channel to finish tuning"),
            (.noConfirmedPlayback, "Play a confirmed channel before saving its current song"),
            (.confirmedChannelUnavailable, "The confirmed channel is unavailable"),
            (.metadataForAnotherChannel, "Current song metadata belongs to another channel"),
            (.metadataNotCurrent, "Current song metadata is not current"),
            (.missingTitle, "Current song title is unavailable"),
            (.missingArtist, "Current song artist is unavailable"),
        ]

        for (reason, expectedHint) in reasons {
            let state = FavoriteCurrentSongActionState.disabled(reason)
            XCTAssertFalse(state.isEnabled)
            XCTAssertEqual(state.title, "Favorite Current Song")
            XCTAssertEqual(state.accessibilityHint, expectedHint)
        }
    }

    func testSongMutationRouteStaysOutsideListeningAndSystemMediaAuthority() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "SiriusMac/App/ListeningSessionController.swift"),
            encoding: .utf8
        )
        let route = try XCTUnwrap(source.components(separatedBy: "func setSongFavorite").dropFirst().first)
            .components(separatedBy: "func startSystemMediaControls").first ?? ""

        XCTAssertFalse(route.contains("tune("))
        XCTAssertFalse(route.contains("playbackQueue"))
        XCTAssertFalse(route.contains("nowPlayingPublisher"))
        XCTAssertFalse(route.contains("authenticationModel"))
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

    func calls(for channelID: LiveChannelID) -> Int {
        calls[channelID] ?? 0
    }
}

private actor TuneDispatchGate {
    private var workerHasArrived = false
    private var workerWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        workerHasArrived = true
        workerWaiters.forEach { $0.resume() }
        workerWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitForWorker() async {
        guard !workerHasArrived else { return }
        await withCheckedContinuation { workerWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
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
    private struct ObservationCallbacks {
        let ready: @MainActor @Sendable () -> Void
        let playing: @MainActor @Sendable () -> Void
        let paused: @MainActor @Sendable () -> Void
        let failure: @MainActor @Sendable (LiveListeningFailure) -> Void
    }

    private var observations: [ObservationCallbacks] = []
    private var observationWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var observationCount = 0
    private(set) var installCount = 0
    private(set) var playRequestCount = 0

    func observe(
        _: AVPlayerItem,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) -> any PlaybackItemObserving {
        observations.append(.init(
            ready: onReady,
            playing: onPlaying,
            paused: onPaused,
            failure: onFailure
        ))
        observationCount += 1
        observationWaiters.removeValue(forKey: observationCount)?.resume()
        return SessionPlaybackObservation()
    }

    func install(_: AVPlayerItem) { installCount += 1 }
    func requestPlay() { playRequestCount += 1 }
    func requestPause() {}
    func clearCurrentItem() {}

    func waitForObservation(count: Int = 1) async {
        guard observationCount < count else { return }
        await withCheckedContinuation { observationWaiters[count] = $0 }
    }

    func confirmReady(observation: Int? = nil) {
        callback(at: observation)?.ready()
    }

    func confirmPlaying(observation: Int? = nil) {
        callback(at: observation)?.playing()
    }

    func confirmPaused(observation: Int? = nil) {
        callback(at: observation)?.paused()
    }

    func confirmFailure(_ failure: LiveListeningFailure, observation: Int? = nil) {
        callback(at: observation)?.failure(failure)
    }

    private func callback(at observation: Int?) -> ObservationCallbacks? {
        let index = (observation ?? observationCount) - 1
        guard observations.indices.contains(index) else { return nil }
        return observations[index]
    }
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
