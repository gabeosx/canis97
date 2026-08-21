import AppKit
import MediaPlayer
import SiriusXMClient

/// The finite system-command set for live radio. There is deliberately no
/// position, scrub, interval-skip, or separate Stop control.
enum SystemRemoteCommand: CaseIterable, Hashable {
    case playPause, previous, next
    case changePlaybackPosition, seekForward, seekBackward
    case skipForward, skipBackward, stop

    static let liveInappropriateCommands: [Self] = [
        .changePlaybackPosition, .seekForward, .seekBackward,
        .skipForward, .skipBackward, .stop,
    ]
}

enum SystemRemoteCommandStatus: Equatable { case success, commandFailed }

@MainActor protocol RemoteCommandTarget: AnyObject {}

@MainActor
protocol RemoteCommandCenterControlling: AnyObject {
    func setEnabled(_ isEnabled: Bool, for command: SystemRemoteCommand)
    func addTarget(for command: SystemRemoteCommand, handler: @escaping () -> SystemRemoteCommandStatus) -> any RemoteCommandTarget
    func removeTarget(_ target: any RemoteCommandTarget, for command: SystemRemoteCommand)
}

enum SystemPlaybackState: Equatable { case playing, paused }

/// Allow-listed Now Playing values only. It cannot carry a provider response,
/// session value, transport URL, or renderer/skin-authored display text.
struct SystemNowPlayingInfo: Equatable {
    let title: String
    let artist: String?
    let channelName: String?
    let artwork: ArtworkData?
    let playbackState: SystemPlaybackState
    let playbackRate: Double
}

@MainActor
protocol NowPlayingInfoPublishing: AnyObject {
    func publish(_ info: SystemNowPlayingInfo?)
}

@MainActor
final class SystemMediaController {
    struct Actions {
        let playPause: () -> SystemRemoteCommandStatus
        let previous: () -> SystemRemoteCommandStatus
        let next: () -> SystemRemoteCommandStatus
    }

    private let commandCenter: any RemoteCommandCenterControlling
    private let nowPlayingPublisher: any NowPlayingInfoPublishing
    private let actions: Actions
    private var targets: [(SystemRemoteCommand, any RemoteCommandTarget)] = []
    private var isStarted = false
    private var isShutdown = false

    init(commandCenter: any RemoteCommandCenterControlling, nowPlayingPublisher: any NowPlayingInfoPublishing, actions: Actions) {
        self.commandCenter = commandCenter
        self.nowPlayingPublisher = nowPlayingPublisher
        self.actions = actions
    }

    func start() {
        guard !isStarted, !isShutdown else { return }
        isStarted = true
        for command in SystemRemoteCommand.liveInappropriateCommands { commandCenter.setEnabled(false, for: command) }
        install(.playPause, handler: actions.playPause)
        install(.previous, handler: actions.previous)
        install(.next, handler: actions.next)
    }

    func publish(_ info: SystemNowPlayingInfo?) { nowPlayingPublisher.publish(info) }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        for (command, target) in targets { commandCenter.removeTarget(target, for: command) }
        targets.removeAll()
        nowPlayingPublisher.publish(nil)
    }

    private func install(_ command: SystemRemoteCommand, handler: @escaping () -> SystemRemoteCommandStatus) {
        commandCenter.setEnabled(true, for: command)
        targets.append((command, commandCenter.addTarget(for: command, handler: handler)))
    }
}

@MainActor
final class SystemRemoteCommandCenterAdapter: RemoteCommandCenterControlling {
    private final class Target: RemoteCommandTarget {
        let command: MPRemoteCommand
        let token: Any
        init(command: MPRemoteCommand, token: Any) { self.command = command; self.token = token }
    }

    private let center: MPRemoteCommandCenter
    init(center: MPRemoteCommandCenter = .shared()) { self.center = center }

    func setEnabled(_ isEnabled: Bool, for command: SystemRemoteCommand) { remoteCommand(for: command).isEnabled = isEnabled }

    func addTarget(for command: SystemRemoteCommand, handler: @escaping () -> SystemRemoteCommandStatus) -> any RemoteCommandTarget {
        let remoteCommand = remoteCommand(for: command)
        let token = remoteCommand.addTarget { _ in
            return switch handler() {
            case .success: .success
            case .commandFailed: .commandFailed
            }
        }
        return Target(command: remoteCommand, token: token)
    }

    func removeTarget(_ target: any RemoteCommandTarget, for _: SystemRemoteCommand) {
        guard let target = target as? Target else { return }
        target.command.removeTarget(target.token)
    }

    private func remoteCommand(for command: SystemRemoteCommand) -> MPRemoteCommand {
        switch command {
        case .playPause: center.togglePlayPauseCommand
        case .previous: center.previousTrackCommand
        case .next: center.nextTrackCommand
        case .changePlaybackPosition: center.changePlaybackPositionCommand
        case .seekForward: center.seekForwardCommand
        case .seekBackward: center.seekBackwardCommand
        case .skipForward: center.skipForwardCommand
        case .skipBackward: center.skipBackwardCommand
        case .stop: center.stopCommand
        }
    }
}

@MainActor
final class SystemNowPlayingInfoAdapter: NowPlayingInfoPublishing {
    private let infoCenter: MPNowPlayingInfoCenter
    init(infoCenter: MPNowPlayingInfoCenter = .default()) { self.infoCenter = infoCenter }

    func publish(_ info: SystemNowPlayingInfo?) {
        guard let info else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            return
        }
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: info.playbackRate,
        ]
        if let artist = info.artist { values[MPMediaItemPropertyArtist] = artist }
        if let channelName = info.channelName { values[MPMediaItemPropertyAlbumTitle] = channelName }
        if let artwork = info.artwork, let image = NSImage(data: artwork.bytes) {
            values[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        infoCenter.nowPlayingInfo = values
        infoCenter.playbackState = info.playbackState == .playing ? .playing : .paused
    }
}
