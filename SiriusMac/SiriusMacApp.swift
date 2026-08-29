import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SiriusXMClient

@main
struct Canis97App: App {
    private let sessionController: ListeningSessionController?
    private let appearanceController: SkinAppearanceController
    private let skinImportCoordinator: SkinImportCoordinator
    private let updateChecker: UpdateChecker
    private let terminationObserver: ApplicationTerminationObserver?
#if DEBUG
    private let offlineReviewHarness: OfflineReviewHarness?
#endif

    init() {
        let environment = ProcessInfo.processInfo.environment
        updateChecker = UpdateChecker()
#if DEBUG
        if OfflineReviewLaunchMode.isOfflineReviewMode(environment: environment) {
            let offlineAppearanceController = SkinAppearanceController(
                catalog: .phaseOne,
                selectionStore: nil
            )
            appearanceController = offlineAppearanceController
            skinImportCoordinator = SkinImportCoordinator(
                importer: SkinPackageImporter(),
                appearanceController: offlineAppearanceController
            )
            offlineReviewHarness = OfflineReviewHarness.makeIfRequested(environment: environment)
            sessionController = nil
            terminationObserver = nil
            return
        }
        offlineReviewHarness = nil
#endif
        let allowsDurableAppearance = !OfflineReviewLaunchMode.isUnitTestHost(environment: environment)
            && !OfflineReviewLaunchMode.isOfflineReviewRequested(environment: environment)
        let managedStore = ManagedSkinStore()
        let importer = SkinPackageImporter(store: managedStore)
        let appearanceController = SkinAppearanceController(
            catalog: SkinAppearanceCatalog.phaseOne.inserting(contentsOf: importer.loadManagedAppearances()),
            selectionStore: allowsDurableAppearance ? SkinSelectionStore() : nil,
            removeImportedPackage: { reference in
                try managedStore.removeImportedSkin(reference)
            }
        )
        self.appearanceController = appearanceController
        skinImportCoordinator = SkinImportCoordinator(
            importer: importer,
            appearanceController: appearanceController
        )
        if allowsDurableAppearance {
            Task { await appearanceController.restorePersistedSelection() }
        }
        sessionController = Self.makeSessionController()
        sessionController?.startSystemMediaControls()
        terminationObserver = sessionController.map { controller in
            ApplicationTerminationObserver { controller.shutdown() }
        }
    }

    @MainActor
    static func makeSessionController(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ListeningSessionController? {
        guard !OfflineReviewLaunchMode.isUnitTestHost(environment: environment),
              !OfflineReviewLaunchMode.isOfflineReviewRequested(environment: environment)
        else { return nil }
        return ListeningSessionController()
    }

    var body: some Scene {
        WindowGroup(ProductIdentity.displayName, id: ProductIdentity.SceneID.compact) {
            compactSceneContent
                .softwareUpdatePresentation(checker: updateChecker)
        }
        .defaultSize(width: 760, height: 760)
        // The primary scene changes from a resizable authentication surface to
        // a fixed 400 x 288 player. Tracking the complete content size lets the
        // window shed the authentication frame instead of leaving the compact
        // player surrounded by unused window background after restoration.
        .windowResizability(.contentSize)
        .commands {
            ListeningCommands(
                controller: sessionController,
                appearanceController: appearanceController,
                updateChecker: updateChecker
            )
        }

        Window("\(ProductIdentity.displayName) Library", id: ProductIdentity.SceneID.library) {
            librarySceneContent
        }
        .defaultSize(width: 980, height: 700)
        .windowResizability(.contentMinSize)

        Settings {
            SkinManagementView(
                appearanceController: appearanceController,
                skinImportCoordinator: skinImportCoordinator
            )
        }

        Window("About \(ProductIdentity.displayName)", id: ProductSceneID.about) {
            AboutProductView()
        }
        .defaultSize(width: 520, height: 420)
        .windowResizability(.contentSize)

        Window("Compatibility & Support", id: ProductSceneID.support) {
            CompatibilitySupportView(controller: sessionController)
        }
        .defaultSize(width: 760, height: 650)
        .windowResizability(.contentMinSize)

        Window("Audio Output", id: ProductSceneID.audioOutput) {
            if let player = sessionController?.playbackCoordinator.audioRoutingPlayer {
                AudioOutputSelector(player: player)
            } else {
                ContentUnavailableView(
                    "Audio Output Unavailable",
                    systemImage: "speaker.slash",
                    description: Text("Start a listening session before choosing an output.")
                )
                .frame(width: 320, height: 220)
            }
        }
        .defaultSize(width: 320, height: 360)
        .windowResizability(.contentSize)
    }

    @ViewBuilder
    private var compactSceneContent: some View {
#if DEBUG
        if let offlineReviewHarness {
            OfflineReviewCompactRoot(harness: offlineReviewHarness)
        } else if OfflineReviewLaunchMode.isOfflineReviewMode() {
            OfflineReviewUnavailableView()
        } else if let sessionController {
            CompactAuthenticationRoot(
                controller: sessionController,
                appearanceController: appearanceController
            )
        } else {
            Color.clear
                .frame(minWidth: 760, minHeight: 760)
                .accessibilityHidden(true)
        }
#else
        if let sessionController {
            CompactAuthenticationRoot(
                controller: sessionController,
                appearanceController: appearanceController
            )
        } else {
            Color.clear
                .frame(minWidth: 760, minHeight: 760)
                .accessibilityHidden(true)
        }
#endif
    }

    @ViewBuilder
    private var librarySceneContent: some View {
#if DEBUG
        if let offlineReviewHarness {
            OfflineReviewLibraryRoot(harness: offlineReviewHarness)
        } else if OfflineReviewLaunchMode.isOfflineReviewMode() {
            OfflineReviewUnavailableView()
        } else if let sessionController {
            LibraryRoot(controller: sessionController)
        } else {
            Color.clear
                .frame(minWidth: 760, minHeight: 540)
                .accessibilityHidden(true)
        }
#else
        if let sessionController {
            LibraryRoot(controller: sessionController)
        } else {
            Color.clear
                .frame(minWidth: 760, minHeight: 540)
                .accessibilityHidden(true)
        }
#endif
    }
}

private struct CompactAuthenticationRoot: View {
    let controller: ListeningSessionController
    let appearanceController: SkinAppearanceController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if controller.authenticationModel.isReady {
                CompactListeningSlice(
                    controller: controller,
                    appearanceController: appearanceController
                )
            } else {
                AuthenticationView(controller: controller)
                    .frame(minWidth: 760, minHeight: 760)
            }
        }
        .onChange(of: controller.authenticationModel.isReady, initial: true) { _, isReady in
            switch controller.libraryWindowDirective(authenticationIsReady: isReady) {
            case .open:
                openWindow(id: ProductIdentity.SceneID.library)
            case .close:
                dismissWindow(id: ProductIdentity.SceneID.library)
            case .none:
                break
            }
        }
    }
}

private struct CompactListeningSlice: View {
    let controller: ListeningSessionController
    let appearanceController: SkinAppearanceController
    @Environment(\.openWindow) private var openWindow
    @State private var lastConfirmedPresentation: CompactPlayerPresentation?

    var body: some View {
        let current = presentation
        CompactPlayerView(
            presentation: current.retainingConfirmedContent(from: lastConfirmedPresentation),
            appearance: appearanceController.selectedAppearance,
            favoriteSongActionState: controller.favoriteCurrentSongActionState,
            onAction: perform,
            isAlwaysOnTop: controller.libraryStore.alwaysOnTop,
            onAlwaysOnTopChanged: controller.libraryStore.setAlwaysOnTop,
            onAppearanceRecovery: {
                Task { await appearanceController.restoreNativeAppearance() }
            },
            audioRoutingPlayer: controller.playbackCoordinator.audioRoutingPlayer
        )
        .background(
            WindowAttachmentView(
                role: .compact,
                alwaysOnTop: controller.libraryStore.alwaysOnTop,
                appearance: appearanceController.selectedAppearance,
                restoreNativeAppearance: {
                    Task { await appearanceController.restoreNativeAppearance() }
                }
            )
        )
        .onChange(of: current, initial: true) { _, next in
            guard next.channelIdentity != nil else { return }
            lastConfirmedPresentation = next
        }
        .task(id: confirmedChannelArtworkReference) {
            await controller.listeningModel.artworkStore.load(confirmedChannelArtworkReference)
        }
    }

    private var confirmedChannel: LiveChannel? {
        let model = controller.listeningModel
        return model.confirmedChannelID.flatMap { id in
            model.state.snapshot?.channels.first(where: { $0.id == id })
        }
    }

    private var confirmedChannelArtworkReference: ChannelArtworkReference? {
        confirmedChannel?.artwork
    }

    private var presentation: CompactPlayerPresentation {
        let model = controller.listeningModel
        let channel = confirmedChannel
        return CompactPlayerPresentation.project(
            channel: channel,
            metadata: model.metadataPresentation.state,
            channelArtwork: model.artworkStore.artwork(for: channel?.artwork),
            primaryMetadata: controller.compactSurface.metadataPrimaryText,
            secondaryMetadata: controller.compactSurface.metadataSecondaryText,
            playback: model.playbackState,
            isFavorite: channel.map { controller.libraryStore.isFavorite($0.id) } ?? false,
            queueAvailability: controller.listeningModel.isTunePending ? .none : controller.queueAvailability
        )
    }

    private func perform(_ action: CompactPlayerAction) {
        switch action {
        case .previous:
            _ = controller.previous()
        case .playPause:
            _ = controller.toggleConfirmedPlayback()
        case .next:
            _ = controller.next()
        case .toggleFavorite:
            guard let channel = controller.listeningModel.confirmedChannelID.flatMap({ id in
                controller.listeningModel.state.snapshot?.channels.first(where: { $0.id == id })
            }) else { return }
            let snapshot = LibraryChannelSnapshot(channel)
            controller.setFavorite(snapshot, isFavorite: !controller.libraryStore.isFavorite(channel.id))
        case .toggleSongFavorite:
            guard case let .enabled(isFavorite) = controller.favoriteCurrentSongActionState else { return }
            _ = controller.setFavoriteCurrentSong(isFavorite: !isFavorite)
        case .showLibrary:
            _ = controller.requestLibraryOpen()
            openWindow(id: ProductIdentity.SceneID.library)
        case .toggleAlwaysOnTop:
            controller.libraryStore.setAlwaysOnTop(!controller.libraryStore.alwaysOnTop)
        case .retryPlayback:
            _ = controller.listeningModel.resumePlaybackAtLiveEdge()
        case .signInAgain:
            _ = controller.authenticationModel.retry()
        case .refreshLibrary:
            _ = controller.listeningModel.refresh()
        case .signOut:
            controller.resetListeningBeforeAuthenticationCleanup()
            _ = controller.authenticationModel.signOut()
        }
    }
}

@MainActor
private struct ListeningCommands: Commands {
    let controller: ListeningSessionController?
    let appearanceController: SkinAppearanceController
    let updateChecker: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        if let controller {
            CommandMenu("Player") {
                Button("Previous") {
                    _ = controller.previous()
                }
                .disabled(!controller.commandAvailability.previous)

                Button(controller.commandAvailability.playPauseTitle) {
                    _ = controller.toggleConfirmedPlayback()
                }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(!controller.commandAvailability.playPause)

                Button("Next") {
                    _ = controller.next()
                }
                .disabled(!controller.commandAvailability.next)

                Divider()

                Menu("Appearance") {
                    ForEach(appearanceController.availableAppearances) { appearance in
                        Button {
                            Task { await appearanceController.select(appearance.reference) }
                        } label: {
                            Label(
                                appearance.displayName,
                                systemImage: appearance.reference == appearanceController.selectedReference
                                    ? "checkmark"
                                    : "circle"
                            )
                        }
                        .disabled(appearance.reference == appearanceController.selectedReference)
                    }

                }

                SettingsLink {
                    Text("Manage Appearances…")
                }

                Button("Use Native Appearance") {
                    Task { await appearanceController.restoreNativeAppearance() }
                }

                Divider()

                Button("Show Library") {
                    _ = controller.requestLibraryOpen()
                    openWindow(id: ProductIdentity.SceneID.library)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Focus Search") {
                    controller.requestLibrarySearchFocus()
                    openWindow(id: ProductIdentity.SceneID.library)
                }
                .keyboardShortcut("f", modifiers: .command)

                if let channel = controller.listeningModel.confirmedChannelID.flatMap({ id in
                    controller.listeningModel.state.snapshot?.channels.first(where: { $0.id == id })
                }) {
                    Button(controller.libraryStore.isFavorite(channel.id) ? "Remove from Favorites" : "Add to Favorites") {
                        controller.setFavorite(LibraryChannelSnapshot(channel), isFavorite: !controller.libraryStore.isFavorite(channel.id))
                    }
                }

                let favoriteCurrentSongState = controller.favoriteCurrentSongActionState
                Button(favoriteCurrentSongState.title) {
                    if case let .enabled(isFavorite) = controller.favoriteCurrentSongActionState {
                        _ = controller.setFavoriteCurrentSong(isFavorite: !isFavorite)
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(!favoriteCurrentSongState.isEnabled)
                .accessibilityLabel(favoriteCurrentSongState.accessibilityLabel)
                .accessibilityValue(favoriteCurrentSongState.accessibilityValue)
                .accessibilityHint(favoriteCurrentSongState.accessibilityHint)

                Toggle(
                    "Always on Top",
                    isOn: Binding(
                        get: { controller.libraryStore.alwaysOnTop },
                        set: { controller.libraryStore.setAlwaysOnTop($0) }
                    )
                )

                Divider()

                Button("Audio Output…") {
                    openWindow(id: ProductSceneID.audioOutput)
                }
                .disabled(controller.playbackCoordinator.audioRoutingPlayer == nil)

                Divider()

                Button("Sign Out") {
                    controller.resetListeningBeforeAuthenticationCleanup()
                    _ = controller.authenticationModel.signOut()
                }
                .disabled(controller.authenticationModel.isAttemptInFlight)
            }
        }

        CommandGroup(replacing: .appInfo) {
            Button("About \(ProductIdentity.displayName)") {
                openWindow(id: ProductSceneID.about)
            }

            Divider()

            Button(updateChecker.isChecking ? "Checking for Updates…" : "Check for Updates…") {
                Task { await updateChecker.check(manual: true) }
            }
            .disabled(updateChecker.isChecking)
        }

        CommandGroup(after: .help) {
            Button("Compatibility & Support…") {
                openWindow(id: ProductSceneID.support)
            }
        }

    }
}

private struct LibraryRoot: View {
    let controller: ListeningSessionController

    var body: some View {
        LibraryView(controller: controller)
            .frame(minWidth: 760, minHeight: 540)
            .background(WindowAttachmentView(role: .library, alwaysOnTop: false))
    }
}

private enum ProductSceneID {
    static let audioOutput = "\(ProductIdentity.appBundleIdentifier).audio-output"
    static let about = "\(ProductIdentity.appBundleIdentifier).about"
    static let support = "\(ProductIdentity.appBundleIdentifier).support"
}

/// The unit-test bundle uses the app executable as its host. Keep that host
/// intentionally inert so running tests cannot read, authenticate with, or
/// erase the production Keychain session.
enum OfflineReviewLaunchMode {
    static let reviewModeEnvironmentKey = "\(ProductIdentity.environmentPrefix)_OFFLINE_REVIEW_MODE"
    static let reviewSurfaceEnvironmentKey = "\(ProductIdentity.environmentPrefix)_OFFLINE_REVIEW_SURFACE"
    static let reviewAppearanceEnvironmentKey = "\(ProductIdentity.environmentPrefix)_OFFLINE_REVIEW_APPEARANCE"

    static func isOfflineReviewRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[reviewModeEnvironmentKey] == "1"
    }

    static func isUnitTestHost(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    static func isOfflineReviewMode(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
#if DEBUG
        isOfflineReviewRequested(environment: environment)
#else
        false
#endif
    }
}
