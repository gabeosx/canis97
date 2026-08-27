#if DEBUG
import SwiftData
import SwiftUI
import SiriusXMClient

/// A deliberately narrow, offline composition selected before production session
/// construction. It is credential-free and has no provider, media, or durable
/// storage dependencies.
@MainActor
@Observable
final class OfflineReviewHarness {
    let listeningModel: ListeningPresentationModel
    let libraryStore: LibraryStore
    private(set) var tuneCount = 0
    private(set) var confirmedChannelID: LiveChannelID?
    private(set) var lastOriginIDs: [LiveChannelID] = []
    let reviewSurface: OfflineReviewSurface
    let appearanceController: SkinAppearanceController
    let skinImportCoordinator: SkinImportCoordinator

    static func makeIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> OfflineReviewHarness? {
        guard OfflineReviewLaunchMode.isOfflineReviewMode(environment: environment) else { return nil }
        return OfflineReviewHarness(environment: environment)
    }

    private init(environment: [String: String]) {
        reviewSurface = OfflineReviewSurface(environment: environment)
        let container = try! ModelContainer(
            for: FavoriteRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        libraryStore = LibraryStore(modelContainer: container)
        listeningModel = ListeningPresentationModel(flow: UITestCatalogFlow())
        let importer = SkinPackageImporter()
        appearanceController = SkinAppearanceController(catalog: .phaseOne, selectionStore: nil)
        skinImportCoordinator = SkinImportCoordinator(
            importer: importer,
            appearanceController: appearanceController
        )
        _ = listeningModel.refresh()
    }

    func tune(channelID: LiveChannelID, originIDs: [LiveChannelID]) -> Bool {
        guard originIDs.contains(channelID),
              listeningModel.state.snapshot?.channels.contains(where: { $0.id == channelID }) == true
        else { return false }
        listeningModel.select(channelID)
        confirmedChannelID = channelID
        lastOriginIDs = originIDs
        tuneCount += 1
        return true
    }

    func appearance(named displayName: String) -> ValidatedSkinAppearance {
        appearanceController.availableAppearances.first(where: { $0.displayName == displayName }) ?? .native
    }
}

enum OfflineReviewSurface: String, CaseIterable, Identifiable {
    case authenticationOutcomes
    case compactEmpty
    case compactPopulated
    case compactPending
    case compactError
    case libraryCollections
    case libraryEmpty
    case libraryError
    case appearanceManagement
    case nativeAppearance
    case signalGlowAppearance
    case tapeDeckAppearance

    var id: String { rawValue }

    init(environment: [String: String]) {
        self = environment[OfflineReviewLaunchMode.reviewSurfaceEnvironmentKey]
            .flatMap(Self.init(rawValue:)) ?? .authenticationOutcomes
    }

    var title: String {
        switch self {
        case .authenticationOutcomes: "Authentication outcomes"
        case .compactEmpty: "Compact empty"
        case .compactPopulated: "Compact populated"
        case .compactPending: "Compact pending"
        case .compactError: "Compact error"
        case .libraryCollections: "Library collections"
        case .libraryEmpty: "Library empty"
        case .libraryError: "Library error"
        case .appearanceManagement: "Appearance management"
        case .nativeAppearance: "Native"
        case .signalGlowAppearance: "Signal Glow"
        case .tapeDeckAppearance: "Tape Deck"
        }
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

struct OfflineReviewCompactRoot: View {
    let harness: OfflineReviewHarness
    @Environment(\.openWindow) private var openWindow
    @State private var selectedSurface: OfflineReviewSurface

    init(harness: OfflineReviewHarness) {
        self.harness = harness
        _selectedSurface = State(initialValue: harness.reviewSurface)
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Offline review surface", selection: $selectedSurface) {
                ForEach(OfflineReviewSurface.allCases) { surface in
                    Text(surface.title).tag(surface)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("offline-review.surface-picker")

            reviewContent
        }
        .background(WindowAttachmentView(
            role: .compact,
            alwaysOnTop: false,
            restoresPersistedFrame: false,
            contentRegionAccessibilityIdentifier: "compact.content-region"
        ))
        .onAppear {
            if selectedSurface == .libraryCollections {
                openWindow(id: ProductIdentity.SceneID.library)
            }
        }
        .onChange(of: selectedSurface) { _, surface in
            if surface == .libraryCollections {
                openWindow(id: ProductIdentity.SceneID.library)
            }
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        switch selectedSurface {
        case .authenticationOutcomes:
            OfflineAuthenticationOutcomesView()
        case .compactEmpty, .compactPopulated, .compactPending, .compactError,
             .nativeAppearance, .signalGlowAppearance, .tapeDeckAppearance:
            CompactPlayerView(
                presentation: compactPresentation,
                appearance: reviewAppearance,
                onAction: { _ in }
            )
        case .libraryCollections:
            OfflineReviewLibraryRoot(harness: harness)
        case .libraryEmpty:
            ContentUnavailableView {
                Label("No saved channels", systemImage: "music.note.list")
            } description: {
                Text("Offline review fixture; no provider request was made.")
            }
        case .libraryError:
            ContentUnavailableView {
                Label("Library unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Offline review fixture; no provider request was made.")
            }
        case .appearanceManagement:
            SkinManagementView(
                appearanceController: harness.appearanceController,
                skinImportCoordinator: harness.skinImportCoordinator
            )
        }
    }

    private var compactPresentation: CompactPlayerPresentation {
        switch selectedSurface {
        case .compactEmpty: .empty()
        case .compactPending: .empty(status: .pending)
        case .compactError: .empty(status: .unavailable(.tryAgain))
        default:
            .confirmed(
                channel: .init(number: 1, name: "Orbit"),
                artwork: .placeholder,
                primaryMetadata: "Offline fixture",
                secondaryMetadata: "No provider access",
                playback: .playing,
                isFavorite: false,
                queueAvailability: .none
            )
        }
    }

    private var reviewAppearance: ValidatedSkinAppearance {
        switch selectedSurface {
        case .signalGlowAppearance: harness.appearance(named: "Signal Glow")
        case .tapeDeckAppearance: harness.appearance(named: "Tape Deck")
        default: .native
        }
    }
}

struct OfflineReviewLibraryRoot: View {
    let harness: OfflineReviewHarness

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
        .background(WindowAttachmentView(
            role: .library,
            alwaysOnTop: false,
            restoresPersistedFrame: false
        ))
    }
}

private struct OfflineAuthenticationOutcomesView: View {
    var body: some View {
        List(ClosedAuthenticationTerminal.allCases, id: \.rawValue) { terminal in
            let copy = ClosedAuthenticationOracle.presentation(for: terminal)
            Label(copy.title, systemImage: copy.iconName)
                .accessibilityLabel(copy.title)
                .accessibilityValue(copy.message)
        }
        .accessibilityIdentifier("offline-review.authentication-outcomes")
    }
}
#endif
