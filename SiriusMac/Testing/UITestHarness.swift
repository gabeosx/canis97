#if DEBUG || CANIS97_ANIMATION_ACCEPTANCE
import AppKit
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
    let reviewAppearance: OfflineReviewAppearanceFixture
    let appearanceController: SkinAppearanceController
    let skinImportCoordinator: SkinImportCoordinator

    static func makeIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> OfflineReviewHarness? {
        guard OfflineReviewLaunchMode.isOfflineReviewMode(environment: environment) else { return nil }
        return OfflineReviewHarness(environment: environment)
    }

    private init?(environment: [String: String]) {
        reviewSurface = OfflineReviewSurface(environment: environment)
        reviewAppearance = OfflineReviewAppearanceFixture(environment: environment)
        guard let container = try? ModelContainer(
            for: FavoriteRecord.self,
            FavoriteSongRecord.self,
            RecentRecord.self,
            PlayerPreferenceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else { return nil }
        libraryStore = LibraryStore(modelContainer: container)
        listeningModel = ListeningPresentationModel(flow: UITestCatalogFlow())
        let importer = Self.makeReviewImporter()
        let catalog = SkinAppearanceCatalog.phaseOne.inserting(OfflineReviewAppearanceFixture.legacySchema1Appearance)
        let initialAppearanceName = reviewAppearance.displayName
        appearanceController = SkinAppearanceController(
            catalog: catalog,
            initialReference: catalog.appearances.first(where: { $0.displayName == initialAppearanceName })?.reference ?? .native,
            selectionStore: nil
        )
        skinImportCoordinator = SkinImportCoordinator(
            importer: importer,
            appearanceController: appearanceController
        )
        _ = listeningModel.refresh()
    }

    /// Review imports can only promote into a process-specific temporary store.
    static func makeReviewImporter() -> SkinPackageImporter {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("canis97-offline-review-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        return SkinPackageImporter(store: ManagedSkinStore(applicationSupportDirectory: root))
    }

    func importReviewPackage(at url: URL) async throws -> ValidatedSkinAppearance {
        let result = try await skinImportCoordinator.importAndSelect(url)
        print("OFFLINE-IMPORT: \(result.appearance.displayName), selected=\(result.selected)")
        return result.appearance
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

    func appearance(for fixture: OfflineReviewAppearanceFixture) -> ValidatedSkinAppearance {
        switch fixture {
        case .native:
            .native
        case .legacySchema1:
            OfflineReviewAppearanceFixture.legacySchema1Appearance
        default:
            appearanceController.availableAppearances.first(where: { $0.displayName == fixture.displayName }) ?? .native
        }
    }
}

enum OfflineReviewSurface: String, CaseIterable, Identifiable {
    private static var defaultSurface: Self {
#if CANIS97_ANIMATION_ACCEPTANCE
        .compactHitTesting
#else
        .authenticationOutcomes
#endif
    }

    case compactHitTesting
    case authenticationOutcomes
    case compactEmpty
    case compactPopulated
    case compactPending
    case compactError
    case compactLongText
    case compactAppearanceFailure
    case libraryCollections
    case libraryEmpty
    case libraryError
    case appearanceManagement

    var id: String { rawValue }

    init(environment: [String: String]) {
        self = environment[OfflineReviewLaunchMode.reviewSurfaceEnvironmentKey]
            .flatMap(Self.init(rawValue:)) ?? Self.defaultSurface
    }

    var title: String {
        switch self {
        case .compactHitTesting: "Compact native hit testing"
        case .authenticationOutcomes: "Authentication outcomes"
        case .compactEmpty: "Compact empty"
        case .compactPopulated: "Compact populated"
        case .compactPending: "Compact pending"
        case .compactError: "Compact error"
        case .compactLongText: "Compact long Unicode text"
        case .compactAppearanceFailure: "Compact appearance recovery"
        case .libraryCollections: "Library collections"
        case .libraryEmpty: "Library empty"
        case .libraryError: "Library error"
        case .appearanceManagement: "Appearance management"
        }
    }
}

enum OfflineReviewAppearanceFixture: String, CaseIterable, Identifiable {
    private static var defaultAppearance: Self {
#if CANIS97_ANIMATION_ACCEPTANCE
        .abyssal97
#else
        .native
#endif
    }

    case native
    case legacySchema1
    case signalGlow
    case tapeDeck
    case pixelDesk
    case pocketDisc
    case aquaVista
    case orbitDeck
    case signalGarden
    case exit97
    case quartzDeck
    case abyssal97

    var id: String { rawValue }

    init(environment: [String: String]) {
        self = environment[OfflineReviewLaunchMode.reviewAppearanceEnvironmentKey]
            .flatMap(Self.init(rawValue:)) ?? Self.defaultAppearance
    }

    var title: String {
        switch self {
        case .native: "Native"
        case .legacySchema1: "Legacy schema v1"
        case .signalGlow: "Signal Glow"
        case .tapeDeck: "Tape Deck"
        case .pixelDesk: "Pixel Desk"
        case .pocketDisc: "Pocket Disc"
        case .aquaVista: "Aqua Vista"
        case .orbitDeck: "Orbit Deck"
        case .signalGarden: "Signal Garden"
        case .exit97: "Exit 97"
        case .quartzDeck: "Quartz Deck + Quartz Link"
        case .abyssal97: "Abyssal 97 — Living Ocean"
        }
    }

    var displayName: String { title }

    static let legacySchema1Appearance: ValidatedSkinAppearance = try! SkinManifestValidator.validate(
        Data(
            #"""
            {
              "schemaVersion": 1,
              "identifier": "offline-legacy-schema-1",
              "displayName": "Legacy schema v1",
              "playerBackground": "#101010",
              "metadataPanel": "#202020",
              "accent": "#C6FF00",
              "destructive": "#FF453A",
              "foregroundScheme": "dark",
              "contentPadding": 16,
              "sectionSpacing": 8,
              "cornerRadius": 4,
              "backgroundAsset": null,
              "metadataPanelAsset": null
            }
            """#.utf8
        ),
        classification: .bundled
    )
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
    @State private var selectedAppearance: OfflineReviewAppearanceFixture = .native
    @State private var animationReduceMotion = false
    @State private var animationIsPlaying = true
    @State private var animationBudgetState: AnimatedSkinBudgetState = .withinBudget
    @State private var animationHostPresent = true
    @State private var localReviewAppearance: ValidatedSkinAppearance?
    @State private var localReviewFailure = false
    private let localReviewPath = ProcessInfo.processInfo.environment["CANIS97_OFFLINE_REVIEW_PACKAGE"]
        ?? Bundle.main.url(forResource: "OfflineReview", withExtension: "canis97skin")?.path

    init(harness: OfflineReviewHarness) {
        self.harness = harness
        _selectedSurface = State(initialValue: harness.reviewSurface)
        _selectedAppearance = State(initialValue: harness.reviewAppearance)
    }

    var body: some View {
        if let localReviewPath {
            Group {
                if let localReviewAppearance {
                    OfflineHitTestingReview(appearance: localReviewAppearance)
                } else {
                    Text(localReviewFailure ? "Offline package validation failed" : "Validating offline package…")
                }
            }
            .task {
                guard localReviewAppearance == nil, !localReviewFailure else { return }
                do {
                    localReviewAppearance = try await harness.importReviewPackage(at: URL(fileURLWithPath: localReviewPath))
                } catch {
                    localReviewFailure = true
                    print("OFFLINE-IMPORT: rejected \(String(describing: type(of: error)))")
                }
            }
        } else if harness.reviewSurface == .compactHitTesting {
            OfflineHitTestingReview(appearance: harness.appearanceController.selectedAppearance)
        } else {
            dashboardBody
        }
    }

    private var dashboardBody: some View {
        VStack(spacing: 12) {
            Picker("Offline review surface", selection: $selectedSurface) {
                ForEach(OfflineReviewSurface.allCases) { surface in
                    Text(surface.title).tag(surface)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("offline-review.surface-picker")

            Picker("Offline review appearance", selection: $selectedAppearance) {
                ForEach(OfflineReviewAppearanceFixture.allCases) { fixture in
                    Text(fixture.title).tag(fixture)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("offline-review.appearance-picker")

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
        case .compactHitTesting:
            EmptyView()
        case .authenticationOutcomes:
            OfflineAuthenticationOutcomesView()
        case .compactEmpty, .compactPopulated, .compactPending, .compactError,
             .compactLongText, .compactAppearanceFailure:
            VStack(spacing: 8) {
                animationAcceptanceControls
                if animationHostPresent {
                    CompactPlayerView(
                        presentation: compactPresentation,
                        appearance: reviewAppearance,
                        onAction: { action in
                            if action == .playPause { animationIsPlaying.toggle() }
                        },
                        onAppearanceRecovery: { selectedAppearance = .native },
                        animationBudgetState: animationBudgetState,
                        animationReduceMotionOverride: animationReduceMotion
                    )
                } else {
                    Text("Animated host removed for offline review")
                        .accessibilityIdentifier("offline-review.animation.host-removed")
                }
            }
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
        case .compactLongText:
            .confirmed(
                channel: .init(number: 97, name: "音楽と星空のためのライブ・ラジオ・セッション — مرحبا بالعالم"),
                artwork: .placeholder,
                primaryMetadata: "An unusually long Unicode program title — 音楽と星空のためのライブ・ラジオ・セッション — कलाकार और अतिथि",
                secondaryMetadata: "A deliberately long Unicode artist credit — कलाकार और अतिथि — مرحبا بالعالم",
                playback: .playing,
                isFavorite: false,
                queueAvailability: .both
            )
        case .compactAppearanceFailure: .empty(status: .unavailable(.tryAgain))
        default:
            .confirmed(
                channel: .init(number: 1, name: "Orbit"),
                artwork: .placeholder,
                primaryMetadata: "Offline fixture",
                secondaryMetadata: "No provider access",
                playback: animationIsPlaying ? .playing : .paused,
                isFavorite: false,
                queueAvailability: .none
            )
        }
    }

    private var animationAcceptanceControls: some View {
        HStack(spacing: 8) {
            Toggle("Reduce Motion", isOn: $animationReduceMotion)
                .accessibilityIdentifier("offline-review.animation.reduce-motion")
            Button(animationIsPlaying ? "Pause animation" : "Play animation") {
                animationIsPlaying.toggle()
            }
            .accessibilityIdentifier("offline-review.animation.play-pause")
            Button(animationBudgetState == .withinBudget ? "Exceed budget" : "Restore budget") {
                animationBudgetState = animationBudgetState == .withinBudget ? .exceeded : .withinBudget
            }
            .accessibilityIdentifier("offline-review.animation.budget")
            Toggle("Animated host present", isOn: $animationHostPresent)
                .accessibilityIdentifier("offline-review.animation.host-present")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-review.animation.controls")
    }

    private var reviewAppearance: ValidatedSkinAppearance {
        if selectedSurface == .compactAppearanceFailure {
            return ValidatedSkinAppearance(
                reference: SkinSelectionReference(
                    identifier: SkinIdentifier(rawValue: "offline-appearance-failure")!,
                    classification: .imported
                ),
                displayName: "Offline appearance failure",
                style: .fallback,
                cornerRadius: 4,
                backgroundAssetURL: URL(fileURLWithPath: "/offline/unavailable-decoration.png"),
                metadataPanelAssetURL: nil
            )
        }
        return harness.appearance(for: selectedAppearance)
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

struct OfflineReviewUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Offline review unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text("The synthetic review fixture could not start. No production session was created.")
        }
        .accessibilityIdentifier("offline-review.unavailable")
    }
}

/// Uses the shipping player and window bridge, with no dashboard chrome that
/// could supply its own opaque background or change the player's hit regions.
private struct OfflineHitTestingReview: View {
    let appearance: ValidatedSkinAppearance
    @State private var isPlaying = true
    @State private var songFavorite = false
    @State private var channelFavorite = false
    @State private var probe = OfflineClickThroughProbe()
    @State private var channelNumber = 97
    @State private var reduceMotion = false
    @State private var budgetExceeded = false
    @State private var longMetadata = false
    @State private var artworkTone = 0
    @State private var forcedStatus: CompactPlayerPresentation.Status?
    @State private var topmost = false
    @State private var reviewControlsVisible = false

    private var reviewArtwork: CompactPlayerPresentation.Artwork {
        guard artworkTone != 0 else { return .placeholder }
        let image = NSImage(size: NSSize(width: 96, height: 96))
        image.lockFocus()
        (artworkTone == 1 ? NSColor.white : NSColor.black).setFill()
        NSRect(x: 0, y: 0, width: 96, height: 96).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return .placeholder }
        return .data(ArtworkData(bytes: png, mediaType: .png))
    }

    var body: some View {
        CompactPlayerView(
            presentation: .confirmed(
                channel: .init(number: channelNumber, name: "Offline ocean"),
                artwork: reviewArtwork,
                primaryMetadata: longMetadata ? "A long ocean transmission — 音楽と星空のためのライブ・ラジオ・セッション" : "The Quiet Between",
                secondaryMetadata: "No provider access",
                playback: forcedStatus ?? (isPlaying ? .playing : .paused),
                isFavorite: channelFavorite,
                queueAvailability: .both
            ),
            appearance: appearance,
            favoriteSongActionState: .enabled(isFavorite: songFavorite),
            onAction: { action in
                probe.recordAction(action)
                switch action {
                case .playPause: isPlaying.toggle()
                case .toggleSongFavorite: songFavorite.toggle()
                case .toggleFavorite: channelFavorite.toggle()
                case .next: channelNumber += 1
                case .previous: channelNumber -= 1
                case .showLibrary: reviewControlsVisible = true
                default: break
                }
                print("OFFLINE-STATE: playing=\(isPlaying) song=\(songFavorite) channel=\(channelFavorite) number=\(channelNumber)")
            },
            isAlwaysOnTop: topmost,
            onAlwaysOnTopChanged: { topmost = $0 },
            animationBudgetState: budgetExceeded ? .exceeded : .withinBudget,
            animationReduceMotionOverride: reduceMotion
        )
        .popover(isPresented: $reviewControlsVisible) {
            VStack(alignment: .leading, spacing: 12) {
            Toggle("Review: Reduce Motion", isOn: $reduceMotion)
            Toggle("Review: Exceed budget", isOn: $budgetExceeded)
            Toggle("Review: Long metadata", isOn: $longMetadata)
            Button("Review: Cycle artwork") { artworkTone = (artworkTone + 1) % 3 }
            Button("Review: Minimize") { reviewControlsVisible = false; NSApp.keyWindow?.miniaturize(nil) }
            Button("Review: Loading") { forcedStatus = .pending }
            Button("Review: Error") { forcedStatus = .unavailable(.tryAgain) }
            Button("Review: Idle") { forcedStatus = .stopped }
            Button("Review: Recover") { forcedStatus = nil; isPlaying = true }
                Button("Done") { reviewControlsVisible = false }
            }
            .padding(16)
            .frame(width: 250)
        }
        .background(WindowAttachmentView(
            role: .compact,
            alwaysOnTop: topmost,
            appearance: appearance,
            restoresPersistedFrame: false
        ))
        .background(OfflineClickThroughProbeAttachment(probe: probe))
        .accessibilityValue(probe.summary)
    }
}

/// A separate, inert native window catches real WindowServer click-through.
/// No synthesized events, global event monitors, account data, or disk writes.
@MainActor
@Observable
private final class OfflineClickThroughProbe {
    private(set) var summary = "Detector pending"
    private var backdrop: NSWindow?
    private weak var player: NSWindow?
    private let report = NSTextField(labelWithString: "")
    private var clickCount = 0
    private var actionCount = 0
    private var moveObserver: NSObjectProtocol?

    func attach(to player: NSWindow) {
        guard backdrop == nil else { return }
        self.player = player
        let window = NSWindow(
            contentRect: player.frame.insetBy(dx: -36, dy: -64),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Offline click-through detector"
        window.isReleasedWhenClosed = false
        let catchView = OfflineClickCatcher()
        catchView.onClick = { [weak self] in
            self?.clickCount += 1
            self?.updateReport()
        }
        window.contentView = catchView
        report.frame = NSRect(x: 12, y: 12, width: window.frame.width - 24, height: 42)
        report.autoresizingMask = [.width]
        report.textColor = .white
        report.maximumNumberOfLines = 2
        report.setAccessibilityIdentifier("offline-review.hit-testing.report")
        catchView.addSubview(report)
        backdrop = window
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: player, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateReport() }
        }
        updateReport()
        window.orderFront(nil)
        player.makeKeyAndOrderFront(nil)
        updateReport()
    }

    func recordAction(_ action: CompactPlayerAction) {
        actionCount += 1
        updateReport(lastAction: String(describing: action))
    }

    private func updateReport(lastAction: String = "none") {
        // Keep the detector directly behind the current player frame, including
        // the initial asynchronous import/resize and subsequent drag checks.
        if let player, let backdrop {
            let frame = player.frame.insetBy(dx: -36, dy: -64)
            if backdrop.frame != frame { backdrop.setFrame(frame, display: true) }
            backdrop.order(.below, relativeTo: player.windowNumber)
        }
        let origin = player?.frame.origin ?? .zero
        report.stringValue = "Behind clicks: \(clickCount) | Control actions: \(actionCount) | Last: \(lastAction)\nPlayer origin: \(Int(origin.x)), \(Int(origin.y))"
        summary = "\(report.stringValue) | Detector visible: \(backdrop?.isVisible == true) | Can key: \(player?.canBecomeKey == true) | Key: \(player?.isKeyWindow == true) | Frame: \(player?.frame.size ?? .zero) | Content: \(player?.contentView?.frame.size ?? .zero)"
        print("HIT-TEST: \(summary)")
    }

    func close() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        backdrop?.close()
        backdrop = nil
    }
}

private final class OfflineClickCatcher: NSView {
    var onClick: (() -> Void)?
    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.12, green: 0.23, blue: 0.31, alpha: 1).setFill()
        dirtyRect.fill()
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

private struct OfflineClickThroughProbeAttachment: NSViewRepresentable {
    let probe: OfflineClickThroughProbe
    func makeCoordinator() -> OfflineClickThroughProbe { probe }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            probe.attach(to: window)
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: OfflineClickThroughProbe) {
        coordinator.close()
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
