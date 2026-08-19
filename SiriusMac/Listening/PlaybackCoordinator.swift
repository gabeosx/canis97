import AVFoundation
import Foundation
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
    private var generation = 0
    private var resolutionTask: Task<PlaybackResourceResolution, Never>?
    private var observation: (any PlaybackItemObserving)?
    private var installedItemGeneration: Int?

    private(set) var state: LivePlaybackState = .idle
    private(set) var selectedChannelID: LiveChannelID?

    init(
        resolver: any PlaybackResolving,
        runtime: any PlaybackPlayerRuntime = AVFoundationPlaybackRuntime()
    ) {
        self.resolver = resolver
        self.runtime = runtime
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
                    self?.publishFailure(failure, channelID: channelID, generation: commandGeneration)
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
        state = .playing(channelID)
    }

    private func publishPaused(channelID: LiveChannelID, generation: Int) {
        guard self.generation == generation, selectedChannelID == channelID else { return }
        state = .paused
    }

    private func publishFailure(_ failure: LiveListeningFailure, channelID: LiveChannelID, generation: Int) {
        guard self.generation == generation, selectedChannelID == channelID else { return }
        state = .unavailable(failure)
    }

    @discardableResult
    private func supersedeActiveWork(clearItem: Bool) -> Int {
        generation += 1
        resolutionTask?.cancel()
        resolutionTask = nil
        observation?.cancel()
        observation = nil
        installedItemGeneration = nil
        if clearItem {
            runtime.clearCurrentItem()
        }
        return generation
    }
}
