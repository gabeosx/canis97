import AVFoundation
import AppKit
import Foundation
import Network
import Observation
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

    func resolve(for channelID: LiveChannelID) async -> PlaybackResourceResolution {
        switch await client.resolveLiveStream(for: channelID) {
        case let .available(handoff):
            .available(handoff)
        case .unavailable:
            .failed(.resolutionUnavailable)
        case let .failed(failure):
            .failed(Self.map(failure))
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
    private var activeObservation: AVFoundationItemObservation?

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
            onFailure: onFailure
        )
        activeObservation = observation
        return observation
    }

    func install(_ item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
    }

    func requestPlay() {
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

    init(
        item: AVPlayerItem,
        player: AVPlayer,
        onReady: @escaping @MainActor @Sendable () -> Void,
        onPlaying: @escaping @MainActor @Sendable () -> Void,
        onPaused: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (LiveListeningFailure) -> Void
    ) {
        self.player = player
        self.onReady = onReady
        self.onPlaying = onPlaying
        self.onPaused = onPaused
        self.onFailure = onFailure
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
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
            onReady()
        case .failed:
            onFailure(.decoderUnavailable)
        case .unknown, .readyToPlay:
            break
        @unknown default:
            onFailure(.unsupported)
        }
    }

    private func confirmPlayerState() {
        guard !isCancelled else { return }
        if expectsPlaying,
           player.timeControlStatus == .playing,
           player.rate > 0 {
            expectsPlaying = false
            onPlaying()
        } else if expectsPaused,
                  player.currentItem != nil,
                  player.timeControlStatus != .playing,
                  player.rate == 0 {
            expectsPaused = false
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
    private var installedItemGeneration: Int?
    private var networkAvailable = true
    private var sleeping = false
    private var recoveryPendingAfterReconnect = false

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
        // A pause is a user command boundary even when the currently audible
        // item predates the recovery task. It prevents a late recovered item
        // from installing or restarting playback after the user pauses.
        if recoveryIncident != nil || recoveryPendingAfterReconnect {
            cancelRecovery()
            recoveryPendingAfterReconnect = false
        }
        guard installedItemGeneration == generation else {
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
        _ = supersedeActiveWork(clearItem: true)
        selectedChannelID = nil
        state = .stopped
    }

    /// Event sources call this method only. They never call the resolver or
    /// AVFoundation runtime directly, so duplicate/stale observations cannot
    /// multiply provider activity.
    func handleRecoverySignal(_ signal: PlaybackRecoverySignal) {
        switch signal {
        case .networkBecameUnavailable:
            networkAvailable = false
            recoveryPendingAfterReconnect = selectedChannelID != nil
            cancelRecovery()
        case .willSleep:
            sleeping = true
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
            } else {
                _ = beginRecoveryIfEligible(stallGrace: false)
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
            guard generation == commandGeneration, selectedChannelID == channelID else { return }
            let observed = runtime.observe(
                item,
                onReady: { [weak self] in
                    self?.installReadyItem(item, channelID: channelID, generation: commandGeneration)
                },
                onPlaying: { [weak self] in
                    self?.publishPlaying(channelID: channelID, generation: commandGeneration)
                },
                onPaused: { [weak self] in
                    self?.publishPaused(channelID: channelID, generation: commandGeneration)
                },
                onFailure: { [weak self] failure in
                    self?.handleObservedFailure(failure, channelID: channelID, generation: commandGeneration)
                }
            )
            guard generation == commandGeneration, selectedChannelID == channelID else {
                observed.cancel()
                return
            }
            observation = observed
        case let .failed(failure):
            state = .unavailable(failure)
        }
    }

    private func installReadyItem(_ item: AVPlayerItem, channelID: LiveChannelID, generation: Int) {
        guard self.generation == generation, selectedChannelID == channelID else { return }
        installedItemGeneration = generation
        runtime.install(item)
        runtime.requestPlay()
    }

    private func publishPlaying(channelID: LiveChannelID, generation: Int) {
        guard self.generation == generation, selectedChannelID == channelID else { return }
        completeRecoveryIncident(for: channelID)
        state = .playing(channelID)
    }

    private func publishPaused(channelID: LiveChannelID, generation: Int) {
        guard self.generation == generation, selectedChannelID == channelID else { return }
        state = .paused
    }

    private func handleObservedFailure(_ failure: LiveListeningFailure, channelID: LiveChannelID, generation: Int) {
        guard self.generation == generation, selectedChannelID == channelID else { return }
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
        let observed = runtime.observe(
            item,
            onReady: { [weak self] in
                self?.installReadyRecoveredItem(item, incident: incident)
            },
            onPlaying: { [weak self] in
                self?.publishRecoveredPlaying(incident)
            },
            onPaused: { [weak self] in
                self?.publishRecoveredPaused(incident)
            },
            onFailure: { [weak self] failure in
                self?.handleRecoveredFailure(failure, incident: incident)
            }
        )
        guard isCurrent(incident) else {
            observed.cancel()
            return
        }
        observation?.cancel()
        observation = observed
    }

    private func installReadyRecoveredItem(_ item: AVPlayerItem, incident: RecoveryIncident) {
        guard isCurrent(incident) else { return }
        installReadyItem(item, channelID: incident.channelID, generation: incident.generation)
    }

    private func publishRecoveredPlaying(_ incident: RecoveryIncident) {
        guard isCurrent(incident) else { return }
        publishPlaying(channelID: incident.channelID, generation: incident.generation)
    }

    private func publishRecoveredPaused(_ incident: RecoveryIncident) {
        guard isCurrent(incident) else { return }
        publishPaused(channelID: incident.channelID, generation: incident.generation)
    }

    private func handleRecoveredFailure(_ failure: LiveListeningFailure, incident: RecoveryIncident) {
        guard isCurrent(incident) else { return }
        handleObservedFailure(failure, channelID: incident.channelID, generation: incident.generation)
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
        observation?.cancel()
        observation = nil
        installedItemGeneration = nil
        if clearItem {
            runtime.clearCurrentItem()
        }
        return generation
    }
}
