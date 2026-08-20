import AVFoundation
import AppKit
import Foundation
import Network
import Observation
import OSLog
@_spi(Playback) import SiriusXMClient

/// The only app-side boundary that can consume the package's opaque playback
/// handoff. It deliberately returns semantic outcomes rather than an upstream
/// resource, key, request, URL, or error.
protocol PlaybackResolving: Sendable {
    func resolve(for channelID: LiveChannelID) async -> PlaybackResourceResolution
}

enum PlaybackResourceResolution: Sendable {
    case available(any SiriusXMAppleMediaHandoff)
    case failed(LiveListeningFailure)
}

/// Production resolution delegates every tune to the already composed client.
/// The client remains the sole authority for active-session, entitlement, tune,
/// resource, and optional-key validation.
struct SiriusXMPlaybackResolver: PlaybackResolving {
    let client: SiriusXMClient
    private let telemetry: PlaybackResolutionTelemetry

    init(client: SiriusXMClient, telemetry: PlaybackResolutionTelemetry = .live) {
        self.client = client
        self.telemetry = telemetry
    }

    func resolve(for channelID: LiveChannelID) async -> PlaybackResourceResolution {
        switch await client.resolveLiveStream(for: channelID) {
        case let .available(handoff):
            telemetry.record("available")
            return .available(handoff)
        case .unavailable:
            telemetry.record("unavailable")
            return .failed(.resolutionUnavailable)
        case let .failed(failure):
            telemetry.record(failure.safePlaybackLabel)
            return .failed(Self.map(failure))
        }
    }

    private static func map(_ failure: LiveStreamResolutionFailure) -> LiveListeningFailure {
        switch failure {
        case .authenticationUnavailable: .authorizationUnavailable
        case .entitlementUnavailable: .entitlementUnavailable
        case .selectionUnavailable: .selectionUnavailable
        case .tuneUnavailable, .resourceUnavailable, .malformedResource: .resolutionUnavailable
        case .protectedControl: .protectedControl
        case .networkUnavailable: .networkUnavailable
        case .unsupportedProtection: .unsupported
        case .cancelled: .cancelled
        case .superseded: .superseded
        }
    }
}

struct PlaybackResolutionTelemetry: Sendable {
    private let recorder: @Sendable (String) -> Void

    init(record: @escaping @Sendable (String) -> Void = { _ in }) {
        recorder = record
    }

    static let live: PlaybackResolutionTelemetry = {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.siriusmac.player",
            category: "playback"
        )
        return PlaybackResolutionTelemetry { label in
            logger.info("Sirius Mac playback resolution \(label, privacy: .public)")
        }
    }()

    func record(_ label: String) {
        recorder(label)
    }
}

private extension LiveStreamResolutionFailure {
    var safePlaybackLabel: String {
        switch self {
        case .authenticationUnavailable: "authentication-unavailable"
        case .entitlementUnavailable: "entitlement-unavailable"
        case .selectionUnavailable: "selection-unavailable"
        case .tuneUnavailable: "tune-unavailable"
        case .resourceUnavailable: "resource-unavailable"
        case .malformedResource: "malformed-resource"
        case .protectedControl: "protected-control"
        case .networkUnavailable: "network-unavailable"
        case .unsupportedProtection: "unsupported-protection"
        case .cancelled: "cancelled"
        case .superseded: "superseded"
        }
    }
}

/// A cancellable item observation. It never exposes an AVFoundation error or
/// player-item description to presentation code.
@MainActor
protocol PlaybackItemObserving: AnyObject {
    func cancel()
}

/// A test-injectable delay seam. Recovery never owns a timer or retry loop
/// outside the coordinator, and production keeps the delay in-memory only.
protocol PlaybackRecoverySleeping: Sendable {
    func sleep(for seconds: TimeInterval) async
}

struct PlaybackRecoveryPolicy: Sendable, Equatable {
    let maximumReResolutions: Int
    let stallGrace: TimeInterval
    let backoffs: [TimeInterval]

    init(
        maximumReResolutions: Int = 2,
        stallGrace: TimeInterval = 8,
        backoffs: [TimeInterval] = [1, 3]
    ) {
        self.maximumReResolutions = max(0, maximumReResolutions)
        self.stallGrace = max(0, stallGrace)
        self.backoffs = Array(backoffs.prefix(max(0, maximumReResolutions))).map { max(0, $0) }
    }
}

/// All noisy media, path, and workspace notifications are reduced to this
/// closed semantic input before the coordinator may consider re-resolution.
enum PlaybackRecoverySignal: Sendable, Equatable {
    case stalled
    case resourceExpired
    case decoderFailed
    case networkBecameUnavailable
    case networkBecameAvailable
    case willSleep
    case didWake
    case authorizationLost
    case entitlementLost
    case protectedControl
    case unsupported
}

@MainActor
protocol NetworkPathObserving: AnyObject, Sendable {
    func start(_ onAvailabilityChange: @escaping @MainActor @Sendable (Bool) -> Void)
    func cancel()
}

@MainActor
protocol WorkspacePowerObserving: AnyObject, Sendable {
    func start(
        onWillSleep: @escaping @MainActor @Sendable () -> Void,
        onDidWake: @escaping @MainActor @Sendable () -> Void
    )
    func cancel()
}

/// The production monitor provides only availability eligibility. Its callback
/// cannot resolve a channel or manipulate an AVPlayer. It is composed at the
/// app boundary so generic coordinators and their tests never start a system
/// monitor implicitly.
@MainActor
final class SystemNetworkPathObserver: NetworkPathObserving {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.siriusmac.playback.recovery-path")
    private var started = false

    func start(_ onAvailabilityChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let available = path.status == .satisfied
            Task { @MainActor in onAvailabilityChange(available) }
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}

/// Production workspace power notifications are reduced to lifecycle
/// eligibility signals; they have no direct access to the provider resolver or
/// active item. App composition opts into them explicitly.
@MainActor
final class SystemWorkspacePowerObserver: WorkspacePowerObserving {
    private var tokens: [NSObjectProtocol] = []

    func start(
        onWillSleep: @escaping @MainActor @Sendable () -> Void,
        onDidWake: @escaping @MainActor @Sendable () -> Void
    ) {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        tokens = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in onWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in onDidWake() }
            },
        ]
    }

    func cancel() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
    }
}

/// Generic coordinators are deliberately inert. This keeps previews, unit
/// tests, and dependency-injected compositions from retaining XPC-backed
/// system observers merely by constructing playback state.
@MainActor
private final class InertNetworkPathObserver: NetworkPathObserving {
    func start(_: @escaping @MainActor @Sendable (Bool) -> Void) {}
    func cancel() {}
}

@MainActor
private final class InertWorkspacePowerObserver: WorkspacePowerObserving {
    func start(
        onWillSleep _: @escaping @MainActor @Sendable () -> Void,
        onDidWake _: @escaping @MainActor @Sendable () -> Void
    ) {}

    func cancel() {}
}

private struct SystemPlaybackRecoverySleeper: PlaybackRecoverySleeping {
    func sleep(for seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }
}

private struct RecoveryIncident: Equatable {
    let generation: Int
    let channelID: LiveChannelID
    let identifier = UUID()
}

/// Narrow AVFoundation ownership used by the coordinator and deterministic
/// offline tests. Production has exactly one implementation and one player.
@MainActor
protocol PlaybackPlayerRuntime: AnyObject {
    func observe(
        _ item: AVPlayerItem,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) -> any PlaybackItemObserving
    func install(_ item: AVPlayerItem)
    func requestPlay()
    func requestPause()
    func clearCurrentItem()
}

/// Owns exactly one AVPlayer for the entire composed application graph.
@MainActor
final class AVFoundationPlaybackRuntime: PlaybackPlayerRuntime {
    private let player = AVPlayer()
    private let telemetry: PlaybackRuntimeTelemetry
    private var activeObservation: AVFoundationItemObservation?

    init(telemetry: PlaybackRuntimeTelemetry = .live) {
        self.telemetry = telemetry
    }

    func observe(
        _ item: AVPlayerItem,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) -> any PlaybackItemObserving {
        activeObservation?.cancel()
        let observation = AVFoundationItemObservation(
            item: item,
            player: player,
            onReady: onReady,
            onPlaying: onPlaying,
            onPaused: onPaused,
            onFailure: onFailure,
            telemetry: telemetry
        )
        activeObservation = observation
        return observation
    }

    func install(_ item: AVPlayerItem) {
        telemetry.record("item-installed")
        player.replaceCurrentItem(with: item)
    }

    func requestPlay() {
        telemetry.record("play-requested")
        activeObservation?.requestPlayConfirmation()
        player.play()
    }

    func requestPause() {
        activeObservation?.requestPauseConfirmation()
        player.pause()
    }

    func clearCurrentItem() {
        activeObservation?.cancel()
        activeObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

struct PlaybackRuntimeTelemetry: Sendable {
    private let recorder: @Sendable (String) -> Void

    init(record: @escaping @Sendable (String) -> Void = { _ in }) {
        recorder = record
    }

    static let live: PlaybackRuntimeTelemetry = {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.siriusmac.player",
            category: "playback"
        )
        return PlaybackRuntimeTelemetry { label in
            logger.info("Sirius Mac playback runtime \(label, privacy: .public)")
        }
    }()

    func record(_ label: String) {
        recorder(label)
    }

    static func failureLabel(_ error: Error?, resourceURI: String? = nil) -> String {
        guard let error = error as NSError? else { return "item-failed-no-error" }
        let domain: String
        switch error.domain {
        case AVFoundationErrorDomain: domain = "avfoundation"
        case NSURLErrorDomain: domain = "url-loading"
        case "CoreMediaErrorDomain": domain = "core-media"
        default: domain = "other"
        }
        return "item-failed-\(domain)-\(error.code)-\(resourceKind(resourceURI))"
    }

    static func resourceKind(_ uri: String?) -> String {
        guard let uri, let path = URL(string: uri)?.path.lowercased() else { return "resource-unknown" }
        if path.contains("/playback/key/v1/") { return "resource-key" }
        if path.hasSuffix(".m3u8") { return "resource-manifest" }
        if path.hasSuffix(".aac") || path.hasSuffix(".ts") || path.hasSuffix(".m4s") {
            return "resource-media"
        }
        return "resource-other"
    }
}

@MainActor
private final class AVFoundationItemObservation: PlaybackItemObserving {
    private var itemStatusObservation: NSKeyValueObservation?
    private var playerRateObservation: NSKeyValueObservation?
    private var playerControlObservation: NSKeyValueObservation?
    private var expectsPlaying = false
    private var expectsPaused = false
    private var deliveredReady = false
    private var isCancelled = false
    private let player: AVPlayer
    private let onReady: @MainActor @Sendable () -> Void
    private let onPlaying: @MainActor @Sendable () -> Void
    private let onPaused: @MainActor @Sendable () -> Void
    private let onFailure: @MainActor @Sendable (LiveListeningFailure) -> Void
    private let telemetry: PlaybackRuntimeTelemetry

    init(
        item: AVPlayerItem,
        player: AVPlayer,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void,
        telemetry: PlaybackRuntimeTelemetry
    ) {
        self.player = player
        self.onReady = onReady
        self.onPlaying = onPlaying
        self.onPaused = onPaused
        self.onFailure = onFailure
        self.telemetry = telemetry
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleItemStatus(item.status)
            }
        }
        playerRateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.confirmPlayerState() }
        }
        playerControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.confirmPlayerState() }
        }
    }

    func requestPlayConfirmation() {
        expectsPlaying = true
        expectsPaused = false
        confirmPlayerState()
    }

    func requestPauseConfirmation() {
        expectsPaused = true
        expectsPlaying = false
        confirmPlayerState()
    }

    func cancel() {
        isCancelled = true
        itemStatusObservation?.invalidate()
        playerRateObservation?.invalidate()
        playerControlObservation?.invalidate()
        itemStatusObservation = nil
        playerRateObservation = nil
        playerControlObservation = nil
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status) {
        guard !isCancelled else { return }
        switch status {
        case .readyToPlay where !deliveredReady:
            deliveredReady = true
            telemetry.record("item-ready")
            onReady()
        case .failed:
            telemetry.record(failureLabel())
            onFailure(.decoderUnavailable)
        case .unknown, .readyToPlay:
            break
        @unknown default:
            onFailure(.unsupported)
        }
    }

    private func failureLabel() -> String {
        let item = player.currentItem
        return PlaybackRuntimeTelemetry.failureLabel(
            item?.error,
            resourceURI: item?.errorLog()?.events.last?.uri
        )
    }

    private func confirmPlayerState() {
        guard !isCancelled else { return }
        if expectsPlaying,
           player.timeControlStatus == .playing,
           player.rate > 0 {
            expectsPlaying = false
            telemetry.record("playing-confirmed")
            onPlaying()
        } else if expectsPaused,
                  player.currentItem != nil,
                  player.timeControlStatus != .playing,
                  player.rate == 0 {
            expectsPaused = false
            telemetry.record("paused-confirmed")
            onPaused()
        }
    }
}

/// The single composition-owned authority for all listening controls. Commands
/// invalidate only obsolete resource/item work; presentation changes follow
/// semantic resolution and observed AVFoundation state, never a command intent.
@MainActor
@Observable
final class PlaybackCoordinator {
    private struct PendingReady {
        let channelID: LiveChannelID
        let generation: Int
        let observationID: UUID
        let incident: RecoveryIncident?
    }

    private struct PreInstallationFailure {
        let failure: LiveListeningFailure
        let observationID: UUID
    }

    private let resolver: any PlaybackResolving
    private let runtime: any PlaybackPlayerRuntime
    private let recoveryPolicy: PlaybackRecoveryPolicy
    private let sleeper: any PlaybackRecoverySleeping
    private let networkObserver: any NetworkPathObserving
    private let workspaceObserver: any WorkspacePowerObserving
    private var generation = 0
    private var resolutionTask: Task<PlaybackResourceResolution, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryIncident: RecoveryIncident?
    private var observation: (any PlaybackItemObserving)?
    private var observationID: UUID?
    private var installedItemGeneration: Int?
    private var playRequestedItemGeneration: Int?
    private var pendingReady: PendingReady?
    private var preInstallationFailure: PreInstallationFailure?
    private var networkAvailable = true
    private var sleeping = false
    private var recoveryPendingAfterReconnect = false
    private var playbackMayRecover = false

    private(set) var state: LivePlaybackState = .idle
    private(set) var selectedChannelID: LiveChannelID?

    init(
        resolver: any PlaybackResolving,
        runtime: any PlaybackPlayerRuntime = AVFoundationPlaybackRuntime(),
        recoveryPolicy: PlaybackRecoveryPolicy = PlaybackRecoveryPolicy(),
        sleeper: any PlaybackRecoverySleeping = SystemPlaybackRecoverySleeper(),
        networkObserver: (any NetworkPathObserving)? = nil,
        workspaceObserver: (any WorkspacePowerObserving)? = nil
    ) {
        self.resolver = resolver
        self.runtime = runtime
        self.recoveryPolicy = recoveryPolicy
        self.sleeper = sleeper
        let networkObserver = networkObserver ?? InertNetworkPathObserver()
        let workspaceObserver = workspaceObserver ?? InertWorkspacePowerObserver()
        self.networkObserver = networkObserver
        self.workspaceObserver = workspaceObserver
        networkObserver.start { [weak self] available in
            self?.handleRecoverySignal(available ? .networkBecameAvailable : .networkBecameUnavailable)
        }
        workspaceObserver.start(
            onWillSleep: { [weak self] in self?.handleRecoverySignal(.willSleep) },
            onDidWake: { [weak self] in self?.handleRecoverySignal(.didWake) }
        )
    }

    deinit {
        let networkObserver = networkObserver
        let workspaceObserver = workspaceObserver
        Task { @MainActor in
            networkObserver.cancel()
            workspaceObserver.cancel()
        }
    }

    func tune(_ channelID: LiveChannelID) async {
        let commandGeneration = supersedeActiveWork(clearItem: true)
        selectedChannelID = channelID
        await resolveAndInstall(channelID, commandGeneration: commandGeneration)
    }

    func pause() async {
        guard selectedChannelID != nil else {
            state = .unavailable(.selectionUnavailable)
            return
        }
        playbackMayRecover = false
        // A pause is a user command boundary even when the currently audible
        // item predates the recovery task. It prevents a late recovered item
        // from installing or restarting playback after the user pauses.
        if recoveryIncident != nil || recoveryPendingAfterReconnect {
            cancelRecovery()
            recoveryPendingAfterReconnect = false
        }
        guard installedItemGeneration == generation,
              playRequestedItemGeneration == generation
        else {
            // A pause command is a serialization boundary. An unresolved tune
            // must not later install or begin audio after the user paused.
            _ = supersedeActiveWork(clearItem: true)
            state = .idle
            return
        }
        runtime.requestPause()
    }

    func resumeLiveEdge() async {
        guard let channelID = selectedChannelID else {
            state = .unavailable(.selectionUnavailable)
            return
        }
        let commandGeneration = supersedeActiveWork(clearItem: true)
        await resolveAndInstall(channelID, commandGeneration: commandGeneration)
    }

    func stop() async {
        guard selectedChannelID != nil || state != .stopped else { return }
        _ = supersedeActiveWork(clearItem: true)
        selectedChannelID = nil
        state = .stopped
    }

    /// Authentication session teardown must revoke playback synchronously before
    /// its caller can suspend for credential cleanup. This coordinator owns no
    /// credential storage; it only invalidates the active media authority.
    func invalidateForSessionEnd() {
        guard selectedChannelID != nil || observation != nil || state != .idle else { return }
        _ = supersedeActiveWork(clearItem: true)
        selectedChannelID = nil
        state = .idle
    }

    /// Event sources call this method only. They never call the resolver or
    /// AVFoundation runtime directly, so duplicate/stale observations cannot
    /// multiply provider activity.
    func handleRecoverySignal(_ signal: PlaybackRecoverySignal) {
        switch signal {
        case .networkBecameUnavailable:
            networkAvailable = false
            recoveryPendingAfterReconnect = playbackMayRecover
            cancelRecovery()
        case .willSleep:
            sleeping = true
            recoveryPendingAfterReconnect = playbackMayRecover
            cancelRecovery()
        case .networkBecameAvailable:
            networkAvailable = true
            if recoveryPendingAfterReconnect, beginRecoveryIfEligible(stallGrace: false) {
                recoveryPendingAfterReconnect = false
            }
        case .didWake:
            sleeping = false
            if recoveryPendingAfterReconnect, beginRecoveryIfEligible(stallGrace: false) {
                recoveryPendingAfterReconnect = false
            }
        case .stalled:
            beginRecoveryIfEligible(stallGrace: true)
        case .resourceExpired, .decoderFailed:
            beginRecoveryIfEligible(stallGrace: false)
        case .authorizationLost:
            terminateRecovery(with: .authorizationUnavailable)
        case .entitlementLost:
            terminateRecovery(with: .entitlementUnavailable)
        case .protectedControl:
            terminateRecovery(with: .protectedControl)
        case .unsupported:
            terminateRecovery(with: .unsupported)
        }
    }

    private func resolveAndInstall(_ channelID: LiveChannelID, commandGeneration: Int) async {
        let resolver = resolver
        let task = Task { await resolver.resolve(for: channelID) }
        resolutionTask = task
        let resolution = await task.value
        guard generation == commandGeneration,
              selectedChannelID == channelID,
              !Task.isCancelled
        else { return }
        resolutionTask = nil

        switch resolution {
        case let .available(handoff):
            guard let item = handoff.makePlayerItem() else {
                state = .unavailable(.resolutionUnavailable)
                return
            }
            observeAndInstall(item, channelID: channelID, generation: commandGeneration, incident: nil)
        case let .failed(failure):
            state = .unavailable(failure)
        }
    }

    private func observeAndInstall(
        _ item: AVPlayerItem,
        channelID: LiveChannelID,
        generation: Int,
        incident: RecoveryIncident?
    ) {
        let identifier = UUID()
        observation?.cancel()
        observation = nil
        observationID = identifier
        installedItemGeneration = nil
        playRequestedItemGeneration = nil
        pendingReady = nil
        preInstallationFailure = nil
        let observed = runtime.observe(
            item,
            onReady: { [weak self] in
                self?.handleReadySignal(
                    channelID: channelID,
                    generation: generation,
                    observationID: identifier,
                    incident: incident
                )
            },
            onPlaying: { [weak self] in
                self?.publishPlaying(
                    channelID: channelID,
                    generation: generation,
                    observationID: identifier,
                    incident: incident
                )
            },
            onPaused: { [weak self] in
                self?.publishPaused(
                    channelID: channelID,
                    generation: generation,
                    observationID: identifier,
                    incident: incident
                )
            },
            onFailure: { [weak self] failure in
                self?.handleObservedFailure(
                    failure,
                    channelID: channelID,
                    generation: generation,
                    observationID: identifier,
                    incident: incident
                )
            }
        )
        guard isCurrentObservation(
            channelID: channelID,
            generation: generation,
            observationID: identifier,
            incident: incident
        ) else {
            observed.cancel()
            clearPreInstallationState(for: identifier)
            return
        }
        if preInstallationFailure?.observationID == identifier {
            observed.cancel()
            clearPreInstallationState(for: identifier)
            observationID = nil
            return
        }
        observation = observed
        runtime.install(item)
        guard isCurrentObservation(
            channelID: channelID,
            generation: generation,
            observationID: identifier,
            incident: incident
        ) else { return }
        installedItemGeneration = generation
        consumePendingReady(
            channelID: channelID,
            generation: generation,
            observationID: identifier,
            incident: incident
        )
    }

    private func handleReadySignal(
        channelID: LiveChannelID,
        generation: Int,
        observationID: UUID,
        incident: RecoveryIncident?
    ) {
        guard isCurrentObservation(
            channelID: channelID,
            generation: generation,
            observationID: observationID,
            incident: incident
        ) else { return }
        guard installedItemGeneration == generation else {
            pendingReady = PendingReady(
                channelID: channelID,
                generation: generation,
                observationID: observationID,
                incident: incident
            )
            return
        }
        requestPlayForReadyItem(
            channelID: channelID,
            generation: generation,
            observationID: observationID,
            incident: incident
        )
    }

    private func consumePendingReady(
        channelID: LiveChannelID,
        generation: Int,
        observationID: UUID,
        incident: RecoveryIncident?
    ) {
        guard let pendingReady,
              pendingReady.channelID == channelID,
              pendingReady.generation == generation,
              pendingReady.observationID == observationID,
              pendingReady.incident == incident
        else { return }
        self.pendingReady = nil
        requestPlayForReadyItem(
            channelID: channelID,
            generation: generation,
            observationID: observationID,
            incident: incident
        )
    }

    private func requestPlayForReadyItem(
        channelID: LiveChannelID,
        generation: Int,
        observationID: UUID,
        incident: RecoveryIncident?
    ) {
        guard isCurrentItem(
            channelID: channelID,
            generation: generation,
            observationID: observationID,
            incident: incident
        ) else { return }
        guard playRequestedItemGeneration != generation else { return }
        playRequestedItemGeneration = generation
        runtime.requestPlay()
    }

    private func publishPlaying(
        channelID: LiveChannelID,
        generation: Int,
        observationID: UUID,
        incident: RecoveryIncident?
    ) {
        guard isCurrentItem(
            channelID: channelID,
            generation: generation,
            observationID: observationID,
            incident: incident
        ) else { return }
        completeRecoveryIncident(for: channelID)
        playbackMayRecover = true
        state = .playing(channelID)
    }

    private func publishPaused(
        channelID: LiveChannelID,
        generation: Int,
        observationID: UUID,
        incident: RecoveryIncident?
    ) {
        guard isCurrentItem(
            channelID: channelID,
            generation: generation,
            observationID: observationID,
            incident: incident
        ) else { return }
        playbackMayRecover = false
        recoveryPendingAfterReconnect = false
        cancelRecovery()
        state = .paused
    }

    private func handleObservedFailure(
        _ failure: LiveListeningFailure,
        channelID: LiveChannelID,
        generation: Int,
        observationID: UUID,
        incident: RecoveryIncident?
    ) {
        guard isCurrentObservation(
            channelID: channelID,
            generation: generation,
            observationID: observationID,
            incident: incident
        ) else { return }
        clearPreInstallationState(for: observationID)
        if installedItemGeneration != generation {
            preInstallationFailure = PreInstallationFailure(failure: failure, observationID: observationID)
        }
        publishObservedFailure(failure)
    }

    private func publishObservedFailure(_ failure: LiveListeningFailure) {
        state = .unavailable(failure)
        switch failure {
        case .networkUnavailable:
            handleRecoverySignal(.resourceExpired)
        case .decoderUnavailable:
            handleRecoverySignal(.decoderFailed)
        case .authorizationUnavailable:
            handleRecoverySignal(.authorizationLost)
        case .entitlementUnavailable:
            handleRecoverySignal(.entitlementLost)
        case .protectedControl:
            handleRecoverySignal(.protectedControl)
        case .unsupported:
            handleRecoverySignal(.unsupported)
        case .catalogUnavailable, .selectionUnavailable, .resolutionUnavailable,
             .bufferingUnavailable, .cancelled, .superseded, .recoveryExhausted:
            break
        }
    }

    @discardableResult
    private func beginRecoveryIfEligible(stallGrace: Bool) -> Bool {
        guard recoveryIncident == nil,
              playbackMayRecover,
              recoveryPolicy.maximumReResolutions > 0,
              networkAvailable,
              !sleeping,
              let channelID = selectedChannelID
        else { return false }

        let incident = RecoveryIncident(generation: generation, channelID: channelID)
        recoveryIncident = incident
        if stallGrace {
            state = .unavailable(.bufferingUnavailable)
        }
        recoveryTask = Task { [weak self] in
            await self?.runRecovery(incident, waitsForStallGrace: stallGrace)
        }
        return true
    }

    private func runRecovery(_ incident: RecoveryIncident, waitsForStallGrace: Bool) async {
        if waitsForStallGrace {
            await sleeper.sleep(for: recoveryPolicy.stallGrace)
            guard isCurrent(incident) else { return }
        }

        for attempt in 0 ..< recoveryPolicy.maximumReResolutions {
            let backoff = attempt < recoveryPolicy.backoffs.count ? recoveryPolicy.backoffs[attempt] : 0
            await sleeper.sleep(for: backoff)
            guard isCurrent(incident) else { return }

            let resolution = await resolver.resolve(for: incident.channelID)
            guard isCurrent(incident) else { return }
            switch resolution {
            case let .available(handoff):
                installRecoveredItem(handoff, incident: incident)
                return
            case let .failed(failure) where isTerminalRecoveryFailure(failure):
                terminateRecovery(with: failure)
                return
            case .failed:
                continue
            }
        }

        guard isCurrent(incident) else { return }
        terminateRecovery(with: .recoveryExhausted)
    }

    private func installRecoveredItem(_ handoff: any SiriusXMAppleMediaHandoff, incident: RecoveryIncident) {
        guard isCurrent(incident), let item = handoff.makePlayerItem() else {
            if isCurrent(incident) { terminateRecovery(with: .resolutionUnavailable) }
            return
        }
        observeAndInstall(
            item,
            channelID: incident.channelID,
            generation: incident.generation,
            incident: incident
        )
    }

    private func isCurrentItem(
        channelID: LiveChannelID,
        generation: Int,
        observationID: UUID?,
        incident: RecoveryIncident?
    ) -> Bool {
        guard isCurrentObservation(
            channelID: channelID,
            generation: generation,
            observationID: observationID,
            incident: incident
        ), installedItemGeneration == generation || observationID == nil
        else { return false }

        return true
    }

    private func isCurrentObservation(
        channelID: LiveChannelID,
        generation: Int,
        observationID: UUID?,
        incident: RecoveryIncident?
    ) -> Bool {
        guard self.generation == generation,
              selectedChannelID == channelID
        else { return false }
        if let observationID, self.observationID != observationID {
            return false
        }
        if let incident {
            guard recoveryIncident == nil || recoveryIncident == incident else { return false }
            return self.generation == incident.generation && selectedChannelID == incident.channelID &&
                networkAvailable && !sleeping && !Task.isCancelled
        }
        return recoveryIncident == nil
    }

    private func clearPreInstallationState(for observationID: UUID) {
        if pendingReady?.observationID == observationID {
            pendingReady = nil
        }
        if preInstallationFailure?.observationID == observationID {
            preInstallationFailure = nil
        }
    }

    private func isCurrent(_ incident: RecoveryIncident) -> Bool {
        recoveryIncident == incident && generation == incident.generation &&
            selectedChannelID == incident.channelID && networkAvailable && !sleeping && !Task.isCancelled
    }

    private func completeRecoveryIncident(for channelID: LiveChannelID) {
        guard recoveryIncident?.channelID == channelID else { return }
        recoveryTask = nil
        recoveryIncident = nil
    }

    private func terminateRecovery(with failure: LiveListeningFailure) {
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryIncident = nil
        recoveryPendingAfterReconnect = false
        playbackMayRecover = false
        state = .unavailable(failure)
    }

    private func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryIncident = nil
    }

    private func isTerminalRecoveryFailure(_ failure: LiveListeningFailure) -> Bool {
        switch failure {
        case .authorizationUnavailable, .entitlementUnavailable, .protectedControl,
             .cancelled, .superseded, .unsupported:
            true
        case .catalogUnavailable, .selectionUnavailable, .resolutionUnavailable,
             .networkUnavailable, .bufferingUnavailable, .decoderUnavailable,
             .recoveryExhausted:
            false
        }
    }

    @discardableResult
    private func supersedeActiveWork(clearItem: Bool) -> Int {
        generation += 1
        resolutionTask?.cancel()
        resolutionTask = nil
        cancelRecovery()
        recoveryPendingAfterReconnect = false
        playbackMayRecover = false
        observation?.cancel()
        observation = nil
        observationID = nil
        installedItemGeneration = nil
        playRequestedItemGeneration = nil
        pendingReady = nil
        preInstallationFailure = nil
        if clearItem {
            runtime.clearCurrentItem()
        }
        return generation
    }
}
