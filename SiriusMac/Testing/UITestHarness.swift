#if DEBUG
import SwiftData
import SwiftUI
import SiriusXMClient

/// A deliberately narrow, offline composition used only by launched UI tests.
/// It creates no production session, credential store, network client, media
/// runtime, or durable SwiftData container.
@MainActor
@Observable
final class UITestHarness {
    let listeningModel: ListeningPresentationModel
    let libraryStore: LibraryStore
    private(set) var tuneCount = 0
    private(set) var confirmedChannelID: LiveChannelID?
    private(set) var lastOriginIDs: [LiveChannelID] = []
    private var isTuneInFlight = false

    static func makeIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UITestHarness? {
        guard SiriusMacLaunchMode.isUITestMode(environment: environment) else { return nil }
        return UITestHarness()
    }

    private init() {
        let container = try! ModelContainer(
            for: FavoriteRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        libraryStore = LibraryStore(modelContainer: container)
        listeningModel = ListeningPresentationModel(flow: UITestCatalogFlow())
        _ = listeningModel.refresh()
    }

    func tune(channelID: LiveChannelID, originIDs: [LiveChannelID]) -> Bool {
        guard !isTuneInFlight,
              originIDs.contains(channelID),
              listeningModel.state.snapshot?.channels.contains(where: { $0.id == channelID }) == true
        else { return false }
        isTuneInFlight = true
        listeningModel.select(channelID)
        confirmedChannelID = channelID
        lastOriginIDs = originIDs
        tuneCount += 1
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.isTuneInFlight = false
        }
        return true
    }
}

private final class UITestCatalogFlow: ListeningFlow, Sendable {
    func catalog() async -> CatalogAvailability {
        .snapshot(LiveCatalogSnapshot(
            channels: [
                LiveChannel(id: LiveChannelID("ui-test-1"), name: "Orbit", displayNumber: 1, category: "Fixture"),
                LiveChannel(id: LiveChannelID("ui-test-2"), name: "Nova", displayNumber: 2, category: "Fixture"),
            ],
            freshness: .fresh
        ))
    }
}

struct UITestCompactRoot: View {
    let harness: UITestHarness
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        CompactPlayerView(
            presentation: .confirmed(
                channel: .init(number: 1, name: "Orbit"),
                artwork: .placeholder,
                primaryMetadata: "Offline fixture",
                secondaryMetadata: "No provider access",
                playback: .playing,
                isFavorite: false,
                queueAvailability: .none
            ),
            onAction: { _ in }
        )
        .background(WindowAttachmentView(role: .compact, alwaysOnTop: false))
        .onAppear { openWindow(id: "sirius-library") }
    }
}

struct UITestLibraryRoot: View {
    let harness: UITestHarness

    var body: some View {
        VStack(spacing: 0) {
            LibraryView(
                model: harness.listeningModel,
                libraryStore: harness.libraryStore,
                onTune: harness.tune(channelID:originIDs:)
            )
            Text("\(harness.tuneCount)")
                .accessibilityIdentifier("library.tune-count")
                .accessibilityLabel("Tune count")
                .accessibilityValue("\(harness.tuneCount)")
                .accessibilityHint(harness.confirmedChannelID?.rawValue ?? "No confirmed channel")
                .frame(width: 1, height: 1)
                .opacity(0.01)
            Text(harness.lastOriginIDs.map(\.rawValue).joined(separator: ","))
                .accessibilityIdentifier("library.tune-origin")
                .accessibilityLabel("Tune origin")
                .accessibilityValue(harness.lastOriginIDs.map(\.rawValue).joined(separator: ","))
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .background(WindowAttachmentView(role: .library, alwaysOnTop: false))
    }
}
#endif
