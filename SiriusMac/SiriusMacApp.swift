import Foundation
import SwiftUI

@main
struct SiriusMacApp: App {
    private let sessionController: ListeningSessionController?
    private let terminationObserver: ApplicationTerminationObserver?

    init() {
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
        guard !SiriusMacLaunchMode.isUnitTestHost(environment: environment) else { return nil }
        return ListeningSessionController()
    }

    var body: some Scene {
        WindowGroup("Sirius Mac", id: "sirius-compact") {
            if let sessionController {
                CompactAuthenticationRoot(controller: sessionController)
            } else {
                Color.clear
                    .frame(minWidth: 760, minHeight: 620)
                    .accessibilityHidden(true)
            }
        }
        .defaultSize(width: 760, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            ListeningCommands(controller: sessionController)
        }

        Window("Library", id: "sirius-library") {
            if let sessionController {
                LibraryRoot(controller: sessionController)
            } else {
                Color.clear
                    .frame(minWidth: 760, minHeight: 540)
                    .accessibilityHidden(true)
            }
        }
        .defaultSize(width: 980, height: 700)
        .windowResizability(.contentMinSize)
    }
}

private struct CompactAuthenticationRoot: View {
    let controller: ListeningSessionController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if controller.authenticationModel.isReady {
                CompactListeningSlice(controller: controller)
            } else {
                AuthenticationView(controller: controller)
                    .frame(minWidth: 760, minHeight: 620)
            }
        }
        .onChange(of: controller.authenticationModel.isReady, initial: true) { _, isReady in
            guard isReady, controller.requestLibraryOpen() else { return }
            openWindow(id: "sirius-library")
        }
    }
}

private struct CompactListeningSlice: View {
    let controller: ListeningSessionController
    @Environment(\.openWindow) private var openWindow
    @State private var lastConfirmedPresentation: CompactPlayerPresentation?

    var body: some View {
        let current = presentation
        CompactPlayerView(
            presentation: current.retainingConfirmedContent(from: lastConfirmedPresentation),
            onAction: perform,
            isAlwaysOnTop: controller.libraryStore.alwaysOnTop,
            onAlwaysOnTopChanged: controller.libraryStore.setAlwaysOnTop
        )
        .background(
            WindowAttachmentView(
                role: .compact,
                alwaysOnTop: controller.libraryStore.alwaysOnTop
            )
        )
        .onChange(of: current, initial: true) { _, next in
            guard next.channelIdentity != nil else { return }
            lastConfirmedPresentation = next
        }
    }

    private var presentation: CompactPlayerPresentation {
        let model = controller.listeningModel
        let channel = model.confirmedChannelID.flatMap { id in
            model.state.snapshot?.channels.first(where: { $0.id == id })
        }
        return CompactPlayerPresentation.project(
            channel: channel,
            metadata: model.metadataPresentation.state,
            primaryMetadata: controller.compactSurface.metadataPrimaryText,
            secondaryMetadata: controller.compactSurface.metadataSecondaryText,
            playback: model.playbackState,
            isFavorite: channel.map { controller.libraryStore.isFavorite($0.id) } ?? false,
            queueAvailability: controller.queueAvailability
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
        case .showLibrary:
            _ = controller.requestLibraryOpen()
            openWindow(id: "sirius-library")
        case .toggleAlwaysOnTop:
            controller.libraryStore.setAlwaysOnTop(!controller.libraryStore.alwaysOnTop)
        case .retryPlayback:
            _ = controller.listeningModel.resumePlaybackAtLiveEdge()
        case .signInAgain:
            _ = controller.authenticationModel.retry()
        case .refreshLibrary:
            _ = controller.listeningModel.refresh()
        }
    }
}

@MainActor
private struct ListeningCommands: Commands {
    let controller: ListeningSessionController?
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

                Button("Show Library") {
                    _ = controller.requestLibraryOpen()
                    openWindow(id: "sirius-library")
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Focus Search") {
                    controller.requestLibrarySearchFocus()
                    openWindow(id: "sirius-library")
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Clear Recents") {
                    controller.libraryStore.clearRecents()
                }
                .disabled(controller.libraryStore.recents.isEmpty)

                if let channel = controller.listeningModel.confirmedChannelID.flatMap({ id in
                    controller.listeningModel.state.snapshot?.channels.first(where: { $0.id == id })
                }) {
                    Button(controller.libraryStore.isFavorite(channel.id) ? "Remove from Favorites" : "Add to Favorites") {
                        controller.setFavorite(LibraryChannelSnapshot(channel), isFavorite: !controller.libraryStore.isFavorite(channel.id))
                    }
                }

                Toggle(
                    "Always on Top",
                    isOn: Binding(
                        get: { controller.libraryStore.alwaysOnTop },
                        set: { controller.libraryStore.setAlwaysOnTop($0) }
                    )
                )
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

/// The unit-test bundle uses the app executable as its host. Keep that host
/// intentionally inert so running tests cannot read, authenticate with, or
/// erase the production Keychain session.
enum SiriusMacLaunchMode {
    static func isUnitTestHost(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
