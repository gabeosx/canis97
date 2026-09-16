@preconcurrency import CoreSpotlight
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit
import SiriusXMClient

enum NativeReachActionOutcome: Equatable {
    case accepted(String)
    case authenticationRequired
    case catalogUnavailable
    case channelUnavailable
    case commandUnavailable
}

@MainActor
protocol NativeReachCacheWriting: AnyObject {
    func write(_ snapshot: NativeReachSnapshot)
    func remove()
}

@MainActor
protocol NativeReachSpotlightWriting: AnyObject {
    func replace(with descriptors: [NativeReachSpotlightDescriptor])
    func removeAll()
}

@MainActor
final class NativeReachUserDefaultsCache: NativeReachCacheWriting {
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: NativeReachConstants.appGroupIdentifier)) {
        self.defaults = defaults
    }

    func write(_ snapshot: NativeReachSnapshot) {
        guard let data = snapshot.encoded() else { return }
        defaults?.set(data, forKey: NativeReachConstants.cacheKey)
        WidgetCenter.shared.reloadTimelines(ofKind: NativeReachConstants.widgetKind)
    }

    func remove() {
        defaults?.removeObject(forKey: NativeReachConstants.cacheKey)
        WidgetCenter.shared.reloadTimelines(ofKind: NativeReachConstants.widgetKind)
    }
}

#if DEBUG || CANIS97_ANIMATION_ACCEPTANCE
/// A credential-free playback stand-in used only by the explicit offline review
/// composition. It lets widget actions be exercised end to end without creating
/// a provider session, network request, AVPlayer, or audio output.
@MainActor
final class NativeReachOfflineReviewSession {
    private let cache: any NativeReachCacheWriting
    private let now: @Sendable () -> Date
    private let diagnosticURL: URL?
    private let channels: [NativeReachChannel]
    private let programs: [NativeReachProgram]
    private var selectedIndex = 0
    private var playback: NativeReachPlaybackStatus = .paused

    init(
        cache: any NativeReachCacheWriting = NativeReachUserDefaultsCache(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.cache = cache
        self.now = now
        diagnosticURL = Self.diagnosticURL(environment: environment)
        channels = [
            NativeReachChannel(id: "review-orbit", name: "Orbit", displayNumber: 8, category: "Pop", isFavorite: true),
            NativeReachChannel(id: "review-night-drive", name: "Night Drive", displayNumber: 21, category: "Electronic", isFavorite: true),
            NativeReachChannel(id: "review-listening-room", name: "The Listening Room", displayNumber: 34, category: "Indie", isFavorite: true),
        ].compactMap { $0 }
        programs = [
            NativeReachProgram(title: "A Little More Light", artist: "The Satellites", startedAt: nil),
            NativeReachProgram(title: "City After Midnight", artist: "Neon Avenue", startedAt: nil),
            NativeReachProgram(title: "Everything in Its Own Time", artist: "Juniper & the Coast", startedAt: nil),
        ].compactMap { $0 }
    }

    func start() {
        publish()
    }

    func handle(_ route: NativeReachRoute) -> NativeReachActionOutcome {
        switch route {
        case .library:
            return .accepted("Opening Library")
        case .togglePlayback:
            playback = playback == .playing ? .paused : .playing
        case .previousChannel:
            selectedIndex = (selectedIndex - 1 + channels.count) % channels.count
            playback = .playing
        case .nextChannel:
            selectedIndex = (selectedIndex + 1) % channels.count
            playback = .playing
        case let .tune(channelID):
            guard let index = channels.firstIndex(where: { $0.id == channelID }) else {
                return .channelUnavailable
            }
            selectedIndex = index
            playback = .playing
        }
        publish()
        return .accepted("Offline review command applied")
    }

    private func publish() {
        guard channels.indices.contains(selectedIndex), programs.indices.contains(selectedIndex) else { return }
        let observedAt = now()
        let program = programs[selectedIndex]
        let snapshot = NativeReachSnapshot(
            updatedAt: observedAt,
            playback: playback,
            currentChannel: channels[selectedIndex],
            currentProgram: NativeReachProgram(
                title: program.title,
                artist: program.artist,
                startedAt: observedAt.addingTimeInterval(-90)
            ),
            metadataObservedAt: observedAt,
            favorites: channels
        )
        cache.write(snapshot)
        if let diagnosticURL, let data = snapshot.encoded() {
            try? data.write(to: diagnosticURL, options: .atomic)
        }
    }

    private static func diagnosticURL(environment: [String: String]) -> URL? {
        guard let rawPath = environment["CANIS97_WIDGET_CONTROL_TEST_OUTPUT"] else { return nil }
        let url = URL(fileURLWithPath: rawPath).standardizedFileURL
        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path
        guard url.path.hasPrefix(temporaryRoot + "/") else { return nil }
        return url
    }
}
#endif

@MainActor
final class NativeReachSpotlightIndex: NativeReachSpotlightWriting {
    private let worker = NativeReachSpotlightWorker()

    init() {}

    func replace(with descriptors: [NativeReachSpotlightDescriptor]) {
        Task {
            await worker.replace(with: descriptors)
        }
    }

    func removeAll() {
        Task {
            await worker.removeAll()
        }
    }
}

private actor NativeReachSpotlightWorker {
    private let index = CSSearchableIndex.default()
    private var generation = 0

    func replace(with descriptors: [NativeReachSpotlightDescriptor]) async {
        generation &+= 1
        let requestedGeneration = generation
        let items = descriptors.compactMap(Self.searchableItem)
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: [NativeReachConstants.spotlightDomain])
            guard requestedGeneration == generation, !Task.isCancelled, !items.isEmpty else { return }
            try await index.indexSearchableItems(items)
        } catch {
            // Spotlight is an optional projection. Keep failures contained and
            // allow the next semantic publication to rebuild the whole domain.
        }
    }

    func removeAll() async {
        generation &+= 1
        try? await index.deleteSearchableItems(withDomainIdentifiers: [NativeReachConstants.spotlightDomain])
    }

    private static func searchableItem(_ descriptor: NativeReachSpotlightDescriptor) -> CSSearchableItem? {
        guard let routeURL = descriptor.route.url else { return nil }
        let attributes = CSSearchableItemAttributeSet(contentType: .audio)
        attributes.title = descriptor.title
        attributes.contentDescription = descriptor.subtitle
        attributes.keywords = descriptor.keywords
        attributes.contentURL = routeURL
        let item = CSSearchableItem(
            uniqueIdentifier: descriptor.identifier,
            domainIdentifier: NativeReachConstants.spotlightDomain,
            attributeSet: attributes
        )
        item.expirationDate = .distantFuture
        return item
    }
}

/// Publishes bounded semantic state to macOS integrations. Observation remains
/// attached to the app's one session controller; extensions never create a
/// provider client, polling loop, or playback coordinator.
@MainActor
final class NativeReachService {
    private weak var controller: ListeningSessionController?
    private let cache: any NativeReachCacheWriting
    private let spotlight: any NativeReachSpotlightWriting
    private let now: @Sendable () -> Date
    private var lastSnapshotContent: SnapshotContent?
    private var lastSpotlightDescriptors: [NativeReachSpotlightDescriptor] = []
    private var isObserving = false

    init(
        controller: ListeningSessionController,
        cache: any NativeReachCacheWriting = NativeReachUserDefaultsCache(),
        spotlight: any NativeReachSpotlightWriting = NativeReachSpotlightIndex(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.controller = controller
        self.cache = cache
        self.spotlight = spotlight
        self.now = now
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true
        publish()
        observeChanges()
    }

    func stop() {
        isObserving = false
    }

    private func observeChanges() {
        guard isObserving, let controller else { return }
        withObservationTracking {
            _ = controller.authenticationModel.isReady
            _ = controller.listeningModel.state
            _ = controller.listeningModel.playbackState
            _ = controller.listeningModel.confirmedChannelID
            _ = controller.listeningModel.metadataPresentation.availability
            _ = controller.listeningModel.metadataPresentation.currentLiveProgram
            _ = controller.listeningModel.liveNow?.snapshot
            _ = controller.libraryStore.favoriteChannelIDs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObserving else { return }
                self.publish()
                self.observeChanges()
            }
        }
    }

    private func publish() {
        guard let controller else { return }
        guard controller.authenticationModel.isReady else {
            lastSnapshotContent = nil
            lastSpotlightDescriptors = []
            cache.remove()
            spotlight.removeAll()
            return
        }

        let channels = controller.listeningModel.state.snapshot?.channels ?? []
        let orderedFavoriteIDs = controller.libraryStore.favoriteChannelIDs
        let favoriteIDs = Set(orderedFavoriteIDs)
        let semanticChannels = channels.compactMap { channel in
            NativeReachChannel(
                id: channel.id.rawValue,
                name: channel.name,
                displayNumber: channel.displayNumber,
                category: channel.category,
                isFavorite: favoriteIDs.contains(channel.id)
            )
        }
        let descriptors = NativeReachSpotlightDescriptor.channels(semanticChannels)
        if descriptors != lastSpotlightDescriptors {
            lastSpotlightDescriptors = descriptors
            spotlight.replace(with: descriptors)
        }

        let currentChannel = controller.listeningModel.confirmedChannelID.flatMap { currentID in
            semanticChannels.first(where: { $0.id == currentID.rawValue })
        }
        let metadata = controller.listeningModel.metadataPresentation
        let currentProgram: NativeReachProgram? = metadata.availability == .current
            ? metadata.currentLiveProgram.flatMap {
                NativeReachProgram(title: $0.title, artist: $0.artist, startedAt: $0.startedAt)
            }
            : nil
        let observedAt = metadata.availability == .current
            ? controller.listeningModel.liveNow?.snapshot?.observedAt
            : nil
        var channelsByID: [String: NativeReachChannel] = [:]
        for channel in semanticChannels where channelsByID[channel.id] == nil {
            channelsByID[channel.id] = channel
        }
        let content = SnapshotContent(
            playback: Self.playbackStatus(controller.listeningModel.playbackState),
            currentChannel: currentChannel,
            currentProgram: currentProgram,
            metadataObservedAt: observedAt,
            favorites: orderedFavoriteIDs.compactMap { channelsByID[$0.rawValue] }
        )
        guard content != lastSnapshotContent else { return }
        lastSnapshotContent = content
        cache.write(NativeReachSnapshot(
            updatedAt: now(),
            playback: content.playback,
            currentChannel: content.currentChannel,
            currentProgram: content.currentProgram,
            metadataObservedAt: content.metadataObservedAt,
            favorites: content.favorites
        ))
    }

    private static func playbackStatus(_ state: LivePlaybackState) -> NativeReachPlaybackStatus {
        switch state {
        case .playing: .playing
        case .paused: .paused
        case .idle, .awaitingLiveContract, .stopped: .stopped
        case .unavailable: .unavailable
        }
    }

    private struct SnapshotContent: Equatable {
        let playback: NativeReachPlaybackStatus
        let currentChannel: NativeReachChannel?
        let currentProgram: NativeReachProgram?
        let metadataObservedAt: Date?
        let favorites: [NativeReachChannel]
    }
}

@MainActor
@Observable
final class NativeReachRuntime {
    static let shared = NativeReachRuntime()

    private weak var controller: ListeningSessionController?
    private var service: NativeReachService?
#if DEBUG || CANIS97_ANIMATION_ACCEPTANCE
    private var offlineReviewSession: NativeReachOfflineReviewSession?
#endif
    private(set) var libraryRequestGeneration = 0

    private init() {}

    func install(controller: ListeningSessionController) {
        service?.stop()
#if DEBUG || CANIS97_ANIMATION_ACCEPTANCE
        offlineReviewSession = nil
#endif
        self.controller = controller
        let service = NativeReachService(controller: controller)
        self.service = service
        service.start()
    }

#if DEBUG || CANIS97_ANIMATION_ACCEPTANCE
    func installOfflineReview(environment: [String: String] = ProcessInfo.processInfo.environment) {
        service?.stop()
        service = nil
        controller = nil
        let session = NativeReachOfflineReviewSession(environment: environment)
        offlineReviewSession = session
        session.start()
    }
#endif

    func uninstall() {
        service?.stop()
        service = nil
        controller = nil
#if DEBUG || CANIS97_ANIMATION_ACCEPTANCE
        offlineReviewSession = nil
#endif
    }

    func handle(_ url: URL) -> NativeReachActionOutcome {
        guard let route = NativeReachRoute(url: url) else { return .commandUnavailable }
        return handle(route)
    }

    func handle(_ route: NativeReachRoute) -> NativeReachActionOutcome {
#if DEBUG || CANIS97_ANIMATION_ACCEPTANCE
        if let offlineReviewSession {
            if route == .library {
                libraryRequestGeneration &+= 1
            }
            return offlineReviewSession.handle(route)
        }
#endif
        switch route {
        case .library:
            libraryRequestGeneration &+= 1
            _ = controller?.requestLibraryOpen()
            return .accepted("Opening Library")
        case .togglePlayback:
            return togglePlayback()
        case .previousChannel:
            return previousChannel()
        case .nextChannel:
            return nextChannel()
        case let .tune(channelID):
            return tune(channelID: channelID)
        }
    }

    func channelEntities() -> [NativeReachChannel] {
        guard let controller, controller.authenticationModel.isReady else { return [] }
        let favorites = Set(controller.libraryStore.favoriteChannelIDs)
        return (controller.listeningModel.state.snapshot?.channels ?? []).compactMap { channel in
            NativeReachChannel(
                id: channel.id.rawValue,
                name: channel.name,
                displayNumber: channel.displayNumber,
                category: channel.category,
                isFavorite: favorites.contains(channel.id)
            )
        }
    }

    func tune(channelID: String) -> NativeReachActionOutcome {
        guard let controller else { return .commandUnavailable }
        guard controller.authenticationModel.isReady else { return .authenticationRequired }
        let channels = controller.listeningModel.state.snapshot?.channels ?? []
        guard !channels.isEmpty else { return .catalogUnavailable }
        let identity = LiveChannelID(channelID)
        guard let channel = channels.first(where: { $0.id == identity }) else { return .channelUnavailable }
        let origin = channels.map(\.id)
        guard controller.tune(channelID: identity, originIDs: origin) != nil else { return .commandUnavailable }
        return .accepted("Tuning to \(channel.name ?? "channel")")
    }

    func togglePlayback() -> NativeReachActionOutcome {
        guard let controller else { return .commandUnavailable }
        guard controller.authenticationModel.isReady else { return .authenticationRequired }
        let wasPlaying = controller.commandAvailability.pause
        guard controller.toggleConfirmedPlayback() != nil else { return .commandUnavailable }
        return .accepted(wasPlaying ? "Paused" : "Playing")
    }

    func stopPlayback() -> NativeReachActionOutcome {
        guard let controller else { return .commandUnavailable }
        guard controller.authenticationModel.isReady else { return .authenticationRequired }
        guard controller.commandAvailability.stop,
              controller.listeningModel.stopPlayback() != nil
        else { return .commandUnavailable }
        return .accepted("Stopped")
    }

    func previousChannel() -> NativeReachActionOutcome {
        guard let controller else { return .commandUnavailable }
        guard controller.authenticationModel.isReady else { return .authenticationRequired }
        guard controller.previous() != nil else { return .commandUnavailable }
        return .accepted("Tuning previous channel")
    }

    func nextChannel() -> NativeReachActionOutcome {
        guard let controller else { return .commandUnavailable }
        guard controller.authenticationModel.isReady else { return .authenticationRequired }
        guard controller.next() != nil else { return .commandUnavailable }
        return .accepted("Tuning next channel")
    }

    func whatIsPlaying() -> NativeReachActionOutcome {
        guard let controller else { return .commandUnavailable }
        guard controller.authenticationModel.isReady else { return .authenticationRequired }
        guard let channelID = controller.listeningModel.confirmedChannelID,
              let channel = controller.listeningModel.state.snapshot?.channels.first(where: { $0.id == channelID })
        else { return .commandUnavailable }
        let metadata = controller.listeningModel.metadataPresentation
        let channelName = channel.name ?? channel.displayNumber.map { "Channel \($0)" } ?? "Current channel"
        if metadata.availability == .current, let program = metadata.currentLiveProgram {
            let detail = program.artist.map { "\($0) — \(program.title)" } ?? program.title
            return .accepted("\(detail) on \(channelName)")
        }
        return .accepted("\(channelName) is playing")
    }
}

/// Connects Spotlight, widget, and Shortcut deep links to SwiftUI's scene
/// system without giving those integrations their own session authority.
@MainActor
struct NativeReachSceneBridge: ViewModifier {
    @Bindable var runtime: NativeReachRuntime
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                _ = runtime.handle(url)
            }
            .onChange(of: runtime.libraryRequestGeneration) { _, _ in
                openWindow(id: ProductIdentity.SceneID.library)
            }
    }
}
