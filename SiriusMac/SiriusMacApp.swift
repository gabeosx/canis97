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
        let state = controller.compactSurface
        VStack(alignment: .leading, spacing: 12) {
            Label("Sirius Mac", systemImage: "dot.radiowaves.left.and.right")
                .font(.title2)
            Text(compactStatus(state))
                .foregroundStyle(.secondary)
                .accessibilityLabel(compactStatus(state))
            if let primary = state.metadataPrimaryText {
                Text(primary)
                    .font(.body)
                    .lineLimit(2)
                    .accessibilityLabel("Current program: \(primary)")
            }
            if let secondary = state.metadataSecondaryText {
                Text(secondary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel(state.usesMetadataFallback ? "Channel: \(secondary)" : "Artist: \(secondary)")
            }
            Button("Show Library") {
                _ = controller.requestLibraryOpen()
                openWindow(id: "sirius-library")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sirius Mac compact player")
    }

    private func compactStatus(_ state: ListeningSurfaceState) -> String {
        guard state.activeChannelID != nil else {
            return "Nothing Playing"
        }
        guard let channelLabel = controller.listeningModel.confirmedChannelLabel else {
            return "Playing current channel"
        }
        return "Playing \(channelLabel)"
    }
}

private struct LibraryRoot: View {
    let controller: ListeningSessionController

    var body: some View {
        ListeningView(model: controller.listeningModel)
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
