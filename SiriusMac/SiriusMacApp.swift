import Foundation
import SwiftUI

@main
struct SiriusMacApp: App {
    private let sessionController: ListeningSessionController?

    init() {
        sessionController = Self.makeSessionController()
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

    var body: some View {
        CompactPlayerView(presentation: presentation, onAction: perform)
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
            if presentation.transport?.playPause == .pause {
                _ = controller.listeningModel.pausePlayback()
            } else if controller.listeningModel.confirmedChannelID != nil {
                _ = controller.listeningModel.resumePlaybackAtLiveEdge()
            }
        case .next:
            _ = controller.next()
        case .toggleFavorite:
            guard let channel = controller.listeningModel.confirmedChannelID.flatMap({ id in
                controller.listeningModel.state.snapshot?.channels.first(where: { $0.id == id })
            }) else { return }
            let snapshot = LibraryChannelSnapshot(channel)
            controller.libraryStore.setFavorite(snapshot, isFavorite: !controller.libraryStore.isFavorite(channel.id))
        case .showLibrary:
            _ = controller.requestLibraryOpen()
            openWindow(id: "sirius-library")
        case .toggleAlwaysOnTop:
            // Window policy remains owned by Plan 03-05's scoped AppKit adapter.
            break
        }
    }
}

private struct LibraryRoot: View {
    let controller: ListeningSessionController

    var body: some View {
        LibraryView(controller: controller)
            .frame(minWidth: 760, minHeight: 540)
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
